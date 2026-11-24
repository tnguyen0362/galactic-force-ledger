/**
 * GF Orchestrator — drives work in batches through the pi-subagents delegation API.
 *
 * It does not implement agent launching. pi-subagents owns that: `pi-subagents/delegation` is the
 * documented seam (`prompt-template:subagent:request` / `:response`), so this extension emits
 * requests, listens for terminal responses, and composes them into a batch pipeline:
 *
 *   planner (strong model)  ->  N parallel workers  ->  evidence gate  ->  next batch
 *
 * The planner reads the real ledger and WORK_STATE.md and returns a structured plan. It never invents
 * counts: whatever it proposes is validated against the plan schema before a single worker launches.
 *
 * Design rules that came out of the failures in this repo:
 * - Never throw at import or registration time. If pi-subagents is missing, the tool reports that
 *   instead of taking Pi's boot down with it.
 * - One batch at a time. A gate verdict of reject stops the pipeline and reports, rather than
 *   "helpfully" continuing into work nobody checked.
 * - Every response is matched on the full (requestId, ownerRunId, nodeId) tuple, so a late or
 *   duplicated reply cannot advance the wrong stage.
 */
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { appendFileSync, existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { randomUUID } from "node:crypto";

const REPO = process.env.GF_REPO ?? "C:/Users/tnguy/galactic-force";
const DIR = join(REPO, ".goal");
const PLAN_FILE = join(DIR, "ORCH_PLAN.json");
const LOG_FILE = join(DIR, "ORCH_LOG.jsonl");

const PLANNER = process.env.GF_ORCH_PLANNER ?? "oracle";
const WORKER = process.env.GF_ORCH_WORKER ?? "worker";
const GATE = process.env.GF_ORCH_GATE ?? "evidence-auditor";
const PLANNER_MODEL = process.env.GF_ORCH_MODEL ?? "deepseek-v4-pro";
const MAX_WORKERS = Number(process.env.GF_ORCH_MAX_WORKERS ?? 3);

const REQUEST_EVENT = "prompt-template:subagent:request";
const RESPONSE_EVENT = "prompt-template:subagent:response";

interface WorkerTask {
	agent?: string;
	task: string;
	context?: "fresh" | "fork";
}

interface Batch {
	id: string;
	title: string;
	rows: string[];
	workers: WorkerTask[];
	verify: string;
}

interface Plan {
	objective: string;
	batches: Batch[];
}

interface DelegationRequest {
	requestId: string;
	ownerRunId: string;
	nodeId: string;
	agent: string;
	task: string;
	context: "fresh" | "fork";
	cwd: string;
	model?: string;
	thinking?: string;
	timeoutMs?: number;
	result: { kind: "text" } | { kind: "structured"; schema: Record<string, unknown> };
}

interface DelegationResponse {
	requestId: string;
	ownerRunId: string;
	nodeId: string;
	status: string;
	error?: string;
	result?: { kind: "text"; text: string } | { kind: "structured"; value: unknown };
	usage?: { cost?: number; input?: number; output?: number };
}

interface Events {
	emit(event: string, payload: unknown): void;
	on(event: string, handler: (payload: unknown) => void): () => void;
}

/** Pure: the planner's brief. Kept separate so the prompt is testable without a model. */
export function buildPlannerPrompt(ledgerSummary: string, ledgerSample: string, workState: string): string {
	return [
		"You are planning implementation batches for the Roblox build described below. You do not write code.",
		"",
		"Return ONLY JSON matching this shape:",
		'{"objective": string, "batches": [{"id": string, "title": string, "rows": string[], "workers": [{"agent": string, "task": string, "context": "fresh"|"fork"}], "verify": string}]}',
		"",
		"Rules:",
		"- At most 3 batches. At most 3 workers per batch. Each worker task must be self-contained: it names the exact files, the exact requirement ids, and the exact Studio/CLI action.",
		"- A batch must close a connected contract, not a single line. Group rows that one implementation and one test can satisfy together.",
		"- Never include a row whose text you have not been shown; do not invent requirement ids.",
		"- verify must be a concrete check the evidence gate can run (a command, a Studio measurement, or a file assertion).",
		"",
		"LEDGER:",
		ledgerSummary,
		"",
		"SAMPLE ROWS:",
		ledgerSample,
		"",
		"WORK STATE:",
		workState.slice(0, 6000),
	].join("\n");
}

/** Pure: reject a plan that cannot be executed before any agent is launched. */
export function validatePlan(raw: unknown, maxWorkers = MAX_WORKERS): { plan: Plan | null; errors: string[] } {
	const errors: string[] = [];
	const bad = (m: string) => errors.push(m);
	if (typeof raw !== "object" || raw === null) return { plan: null, errors: ["plan is not an object"] };
	const obj = raw as Partial<Plan>;
	if (typeof obj.objective !== "string" || obj.objective.trim().length === 0) bad("objective missing");
	if (!Array.isArray(obj.batches) || obj.batches.length === 0) return { plan: null, errors: [...errors, "batches missing or empty"] };
	if (obj.batches.length > 3) bad(`too many batches (${obj.batches.length} > 3)`);

	const batches: Batch[] = [];
	for (const [i, entry] of obj.batches.entries()) {
		const b = entry as Partial<Batch>;
		const tag = `batch[${i}]`;
		if (typeof b.id !== "string" || !b.id.trim()) bad(`${tag}.id missing`);
		if (typeof b.title !== "string" || !b.title.trim()) bad(`${tag}.title missing`);
		if (typeof b.verify !== "string" || !b.verify.trim()) bad(`${tag}.verify missing`);
		if (!Array.isArray(b.rows) || b.rows.length === 0) bad(`${tag}.rows missing`);
		if (!Array.isArray(b.workers) || b.workers.length === 0) {
			bad(`${tag}.workers missing`);
			continue;
		}
		if (b.workers.length > maxWorkers) bad(`${tag} has ${b.workers.length} workers (max ${maxWorkers})`);
		const workers: WorkerTask[] = [];
		for (const [j, w] of b.workers.entries()) {
			const task = (w as Partial<WorkerTask>)?.task;
			if (typeof task !== "string" || task.trim().length < 20) {
				bad(`${tag}.workers[${j}].task missing or too short`);
				continue;
			}
			workers.push({
				agent: typeof (w as WorkerTask).agent === "string" ? (w as WorkerTask).agent : WORKER,
				task,
				context: (w as WorkerTask).context === "fork" ? "fork" : "fresh",
			});
		}
		batches.push({
			id: String(b.id ?? `batch${i + 1}`),
			title: String(b.title ?? ""),
			rows: (b.rows ?? []).filter((r): r is string => typeof r === "string"),
			workers,
			verify: String(b.verify ?? ""),
		});
	}
	if (errors.length > 0) return { plan: null, errors };
	return { plan: { objective: String(obj.objective), batches }, errors: [] };
}

function ledgerSnapshot(): { summary: string; sample: string } {
	const path = join(REPO, "REQUIREMENT_COVERAGE.csv");
	if (!existsSync(path)) return { summary: "ledger missing", sample: "" };
	const text = readFileSync(path, "utf8");
	const lines = text.split(/\r?\n/).filter((l) => l.trim().length > 0);
	const header = lines[0] ?? "";
	const cols = header.split(",").map((c) => c.replace(/^"|"$/g, ""));
	const statusIdx = cols.findIndex((c) => c === "status");
	const counts = new Map<string, number>();
	for (const line of lines.slice(1)) {
		const cells = line.split('","').map((c) => c.replace(/^"|"$/g, ""));
		const status = (cells[statusIdx] ?? "UNKNOWN").trim();
		counts.set(status, (counts.get(status) ?? 0) + 1);
	}
	const summary = `${lines.length - 1} rows — ` + [...counts.entries()].map(([k, v]) => `${k} ${v}`).join(", ");
	const sample = lines
		.slice(1)
		.filter((l) => l.includes('"UNKNOWN"') || l.includes('"MISSING"'))
		.slice(0, 12)
		.join("\n");
	return { summary, sample };
}

class Orchestrator {
	private pending = new Map<string, { request: DelegationRequest; resolve: (r: DelegationResponse) => void; reject: (e: Error) => void }>();
	private ownerRunId = randomUUID();
	private aborting = false;
	private spent = 0;
	private batchIndex = 0;
	private events: Events;
	private notify: (text: string) => void;
	private cwd: string;
	running = false;
	lastNote = "idle";
	blockedOn = "";

	constructor(events: Events, notify: (text: string) => void, cwd: string) {
		this.events = events;
		this.notify = notify;
		this.cwd = cwd;
		this.events.on(RESPONSE_EVENT, (payload: unknown) => {
			const response = payload as DelegationResponse;
			const key = `${response.requestId}|${response.ownerRunId}|${response.nodeId}`;
			const entry = this.pending.get(key);
			if (!entry) return;
			this.pending.delete(key);
			this.spent += (response.usage?.input ?? 0) + (response.usage?.output ?? 0);
			entry.resolve(response);
		});
	}

	private call(input: Omit<DelegationRequest, "requestId" | "ownerRunId" | "cwd">, timeoutMs = 900_000): Promise<DelegationResponse> {
		const request: DelegationRequest = {
			...input,
			requestId: randomUUID(),
			ownerRunId: this.ownerRunId,
			cwd: this.cwd,
		};
		const key = `${request.requestId}|${request.ownerRunId}|${request.nodeId}`;
		return new Promise<DelegationResponse>((resolve, reject) => {
			const timer = setTimeout(() => {
				this.pending.delete(key);
				this.events.emit("prompt-template:subagent:cancel", { requestId: request.requestId, ownerRunId: request.ownerRunId, nodeId: request.nodeId });
				reject(new Error(`delegation timed out after ${Math.round(timeoutMs / 1000)}s (${request.nodeId}); cancellation requested, termination unconfirmed`));
			}, timeoutMs + 5000);
			this.pending.set(key, {
				request,
				resolve: (r) => {
					clearTimeout(timer);
					resolve(r);
				},
				reject: (e) => {
					clearTimeout(timer);
					reject(e);
				},
			});
			this.events.emit(REQUEST_EVENT, request);
		});
	}

	private log(entry: Record<string, unknown>): void {
		try {
			mkdirSync(dirname(LOG_FILE), { recursive: true });
			appendFileSync(LOG_FILE, JSON.stringify({ at: new Date().toISOString(), ...entry }) + "\n", "utf8");
		} catch {
			/* logging is best effort */
		}
	}

	private async plan(): Promise<Plan> {
		const { summary, sample } = ledgerSnapshot();
		const workStatePath = join(REPO, "WORK_STATE.md");
		const workState = existsSync(workStatePath) ? readFileSync(workStatePath, "utf8") : "";
		const response = await this.call({
			nodeId: "planner",
			agent: PLANNER,
			task: buildPlannerPrompt(summary, sample, workState),
			context: "fresh",
			model: PLANNER_MODEL,
			thinking: "high",
			result: { kind: "text" },
		});
		if (response.status !== "completed" || response.result?.kind !== "text") {
			throw new Error(`planner ${response.status}${response.error ? `: ${response.error}` : ""}`);
		}
		const text = response.result.text;
		const json = text.slice(text.indexOf("{"), text.lastIndexOf("}") + 1);
		let parsed: unknown;
		try {
			parsed = JSON.parse(json);
		} catch (error) {
			throw new Error(`planner returned unparseable JSON: ${String(error)}`);
		}
		const { plan, errors } = validatePlan(parsed);
		if (!plan) throw new Error(`plan rejected: ${errors.join("; ")}`);
		mkdirSync(DIR, { recursive: true });
		writeFileSync(PLAN_FILE, JSON.stringify(plan, null, 2), "utf8");
		return plan;
	}

	private async runBatch(batch: Batch): Promise<{ ok: boolean; note: string }> {
		const workerResponses = await Promise.all(
			batch.workers.map(async (worker, index) => {
				const response = await this.call({
					nodeId: `${batch.id}:worker${index + 1}`,
					agent: worker.agent ?? WORKER,
					task: worker.task,
					context: worker.context ?? "fresh",
					result: { kind: "text" },
				});
				const text = response.result?.kind === "text" ? response.result.text : "";
				this.log({ stage: "worker", batch: batch.id, node: `${index + 1}`, status: response.status, chars: text.length });
				return { index, status: response.status, text, error: response.error };
			}),
		);

		const failed = workerResponses.filter((r) => r.status !== "completed");
		const digest = workerResponses
			.map((r) => `--- worker ${r.index + 1} (${r.status}) ---\n${(r.text || r.error || "").slice(0, 4000)}`)
			.join("\n\n");

		const gate = await this.call({
			nodeId: `${batch.id}:gate`,
			agent: GATE,
			task: [
				`Verify batch "${batch.title}" (${batch.id}) against its requirement rows and its stated check.`,
				`Rows under review: ${batch.rows.join(", ")}`,
				`Required check: ${batch.verify}`,
				"",
				"Worker reports follow. Treat every claim as a hypothesis: a claim without a file path, command output,",
				"Study measurement or capture reference is unverified. Do not accept a claim because it sounds confident.",
				"",
				digest,
			].join("\n"),
			context: "fresh",
			result: { kind: "text" },
		});
		const verdict = (gate.result?.kind === "text" ? gate.result.text : "") || gate.error || "";
		this.log({ stage: "gate", batch: batch.id, status: gate.status, verdict: verdict.slice(0, 2000) });

		const rejected = gate.status !== "completed" || !/^ACCEPTED\b/i.test(verdict.trim()) || /REJECT|FAIL|not verified|unverified/i.test(verdict);
		return {
			ok: failed.length === 0 && !rejected,
			note: [
				`workers: ${workerResponses.map((r) => r.status).join(", ")}`,
				`gate: ${gate.status}${rejected ? " (rejected)" : " (accepted)"}`,
				failed.length > 0 ? `failed workers: ${failed.map((f) => f.index + 1).join(",")}` : "",
			]
				.filter(Boolean)
				.join(" · "),
		};
	}

	async start(options: { batches?: number; budgetTokens?: number } = {}): Promise<string> {
		if (this.running) return "already running";
		this.running = true;
		this.aborting = false;
		const maxBatches = Math.max(1, Math.min(options.batches ?? 1, 3));
		const budget = options.budgetTokens ?? 400_000;
		const notes: string[] = [];
		try {
			const plan = await this.plan();
			notes.push(`blocker: ${this.blockedOn}`);
			notes.push(`plan: ${plan.batches.length} batch(es) — ${plan.objective}`);
			for (const batch of plan.batches.slice(0, maxBatches)) {
				if (this.aborting) {
					notes.push("aborted by owner");
					break;
				}
				if (this.spent > budget) {
					notes.push(`token budget reached (${this.spent} > ${budget})`);
					break;
				}
				this.batchIndex += 1;
				this.lastNote = `batch ${this.batchIndex}: ${batch.title}`;
				const result = await this.runBatch(batch);
				notes.push(`${batch.id} ${result.ok ? "PASS" : "STOP"} — ${result.note}`);
				this.log({ stage: "batch", batch: batch.id, ok: result.ok, note: result.note, spent: this.spent, blockedOn: this.blockedOn });
				if (!result.ok) {
					notes.push("pipeline stopped: the gate did not accept this batch");
					break;
				}
			}
		} catch (error) {
			notes.push(`STOPPED: ${String(error)}`);
			this.log({ stage: "error", error: String(error), blockedOn: this.blockedOn });
		} finally {
			this.running = false;
			this.lastNote = "idle";
		}
		const summary = `orchestrator — ${notes.join("\n")}\nspent ~${this.spent.toLocaleString()} tokens`;
		this.notify(summary);
		return summary;
	}

	abort(): void {
		this.aborting = true;
		for (const [, entry] of this.pending) {
			const { requestId, ownerRunId, nodeId } = entry.request;
			this.events.emit("prompt-template:subagent:cancel", { requestId, ownerRunId, nodeId });
			entry.reject(new Error("aborted by owner; cancellation requested, termination unconfirmed"));
		}
		this.pending.clear();
	}
}

export default function gfOrchestrator(pi: ExtensionAPI): void {
	// Resolve the delegation events lazily and defensively: a missing pi-subagents must produce a
	// readable tool error, never an exception during extension load.
	let events: Events | null = null;
	try {
		events = (pi as unknown as { events?: Events }).events ?? null;
	} catch {
		events = null;
	}
	let engine: Orchestrator | null = null;

	// Automatic escalation. The owner does not want to invoke anything, and the base model should do the
	// bulk of the work, so this watches for the one signal that actually means "stuck": the same failure
	// repeating. Three identical error signatures inside the last twelve tool calls, or three failures in
	// a row, is enough; a single failure never is. Cooldown stops an escalation storm.
	const AUTO = process.env.GF_ORCH_AUTO !== "0";
	const AUTO_COOLDOWN_MS = Number(process.env.GF_ORCH_AUTO_COOLDOWN_MS ?? 900_000);
	const WINDOW = 12;
	const recentErrors: { signature: string; at: number }[] = [];
	let lastEscalation = 0;
	let consecutiveFailures = 0;

	function signatureOf(result: unknown): string {
		const text = typeof result === "string" ? result : JSON.stringify(result ?? "");
		return text
			.replace(/[A-Za-z]:\\[^"'s]+/g, "<path>")
			.replace(/\d+(\.\d+)?/g, "<n>")
			.replace(/\s+/g, " ")
			.trim()
			.slice(0, 160);
	}

	if (AUTO && events) {
		pi.on("tool_execution_end", async (event: { isError?: boolean; result?: unknown }) => {
			if (event?.isError) {
				consecutiveFailures += 1;
				recentErrors.push({ signature: signatureOf(event.result), at: Date.now() });
				while (recentErrors.length > WINDOW) recentErrors.shift();
			} else {
				consecutiveFailures = 0;
			}
		});

		pi.on("agent_settled", async (event: { aborted?: boolean }, ctx: unknown) => {
			if (event?.aborted) return;
			if (!engine || engine.running) return;
			if (Date.now() - lastEscalation < AUTO_COOLDOWN_MS) return;
			const now = Date.now();
			const counted = recentErrors.filter((e) => now - e.at < AUTO_COOLDOWN_MS);
			const tally = new Map<string, number>();
			for (const e of counted) tally.set(e.signature, (tally.get(e.signature) ?? 0) + 1);
			const worst = [...tally.entries()].sort((a, b) => b[1] - a[1])[0];
			const repeated = worst && worst[1] >= 3;
			if (!repeated && consecutiveFailures < 3) return;

			lastEscalation = now;
			consecutiveFailures = 0;
			recentErrors.length = 0;
			const blocker = repeated
				? `the same failure recurred ${worst[1]} times in the last ${WINDOW} tool calls: ${worst[0].slice(0, 120)}`
				: `three tool failures in a row without a success`;
			engine.blockedOn = blocker;
			try {
				(pi as unknown as { sendMessage?: (m: unknown) => void }).sendMessage?.({
					role: "system",
					content: `gf-orchestrator: escalating automatically — ${blocker}`,
				});
			} catch {
				/* notification optional */
			}
			void engine.start({ batches: 1 });
		});
	}

	pi.registerTool({
		name: "gf_orchestrate",
		label: "GF Orchestrate",
		description:
			"ESCALATION ONLY. Call this when the base model is genuinely stuck: repeated attempts at the same failure, a decision that needs a stronger model, or a batch of independent investigations. Do NOT call it for ordinary work — the base model does the bulk. Requires `blockedOn` describing the specific blocker. Spawns a strong planner, parallel workers and an evidence gate through pi-subagents, and stops on the first rejected gate.",
		// Plain JSON Schema instead of a typebox builder: the extension then has no runtime import that
		// can fail to resolve, and a headless test can load this file without Pi's module aliases.
		parameters: {
			type: "object",
			properties: {
				action: { type: "string", enum: ["start", "status", "abort"], description: "start | status | abort" },
				blockedOn: {
					type: "string",
					description:
						"Required for start: the concrete blocker, e.g. 'v377 recolour swept 136 parts and I cannot predict which predicate is safe'. If you cannot name one, the work is not blocked and you should not escalate.",
				},
				batches: { type: "number", description: "How many planned batches to run this call (1-3). Default 1." },
				budgetTokens: { type: "number", description: "Stop before starting a batch once this many child tokens are spent. Default 400000." },
			},
			required: ["action"],
			additionalProperties: false,
		},
		async execute(_toolCallId, params) {
			if (!events) {
				return {
					content: [
						{
							type: "text",
							text: "gf_orchestrate: Pi's extension event bus is unavailable, so the pi-subagents delegation API cannot be reached. Nothing was launched.",
						},
					],
					details: {},
				};
			}
			engine ??= new Orchestrator(events, (text) => {
				try {
					pi.sendMessage?.({ role: "system", content: text } as never);
				} catch {
					/* notification optional */
				}
			}, REPO);

			if (params.action === "abort") {
				engine.abort();
				return { content: [{ type: "text", text: "gf_orchestrate: cancellation requested; child termination is not yet confirmed." }], details: {} };
			}
			if (params.action === "status") {
				return {
					content: [
						{
							type: "text",
							text: `gf_orchestrate: ${engine.running ? "running" : "idle"} — ${engine.lastNote}. Planner ${PLANNER}/${PLANNER_MODEL}, workers ${WORKER}/${process.env.GF_ORCH_WORKER_MODEL ?? "agent default"}, gate ${GATE}. On-demand only. Log: ${LOG_FILE}`,
						},
					],
					details: {},
				};
			}
			const blockedOn = String((params as { blockedOn?: string }).blockedOn ?? "").trim();
			if (blockedOn.length < 15) {
				return {
					content: [
						{
							type: "text",
							text:
								"gf_orchestrate start refused: name the blocker in `blockedOn` (at least 15 characters). " +
								"This tool is an escalation, not a default. Ordinary work belongs to the base model.",
						},
					],
					details: {},
				};
			}
			engine.blockedOn = blockedOn;
			const summary = await engine.start({ batches: params.batches, budgetTokens: params.budgetTokens });
			return { content: [{ type: "text", text: summary }], details: {} };
		},
	});
}
