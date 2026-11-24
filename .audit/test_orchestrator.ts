// Headless test for the GF orchestrator. A fake delegation bus answers the extension's request events,
// so the whole pipeline (planner -> workers -> gate -> stop/advance) is exercised without an LLM.
// Run: node --experimental-strip-types test_orchestrator.ts
import { mkdirSync, readFileSync, rmSync, existsSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";

const repo = join(tmpdir(), `gf-orch-${Date.now()}`);
mkdirSync(join(repo, ".goal"), { recursive: true });
mkdirSync(join(repo, "REPO"), { recursive: true });
process.env.GF_REPO = repo;

// Minimal ledger + work state so the planner prompt has something real to read.
const header = '"requirement_id","area","requirement","status"';
const rows = [
	'"S04-001","Combat","weapon roster complete","MISSING"',
	'"S04-002","Combat","hitscan authority","UNKNOWN"',
	'"S08-003","Missions","fifteen variants","MISSING"',
];
writeFileSync(join(repo, "REQUIREMENT_COVERAGE.csv"), [header, ...rows].join("\n") + "\n", "utf8");
writeFileSync(join(repo, "WORK_STATE.md"), "## current\nelimination family written, unverified\n", "utf8");

const results: string[] = [];
const check = (name: string, cond: boolean, detail = "") => results.push(`${cond ? "PASS" : "FAIL"}  ${name}${detail ? ` — ${detail}` : ""}`);

// --- fake event bus -------------------------------------------------------------------------
type Handler = (payload: any) => void;
const handlers = new Map<string, Handler[]>();
const events = {
	on(event: string, fn: Handler) {
		const list = handlers.get(event) ?? [];
		list.push(fn);
		handlers.set(event, list);
		return () => handlers.set(event, (handlers.get(event) ?? []).filter((h) => h !== fn));
	},
	emit(event: string, payload: any) {
		for (const fn of handlers.get(event) ?? []) fn(payload);
	},
};

let plan: any;
let gateVerdict = "ACCEPTED — evidence checks out";
const seen: any[] = [];
let plannerError = false;

// The fake runtime: answers every request the orchestrator emits.
events.on("prompt-template:subagent:request", (req: any) => {
	seen.push({ nodeId: req.nodeId, agent: req.agent, model: req.model, context: req.context });
	const reply = (status: string, value: any) =>
		setTimeout(
			() =>
				events.emit("prompt-template:subagent:response", {
					requestId: req.requestId,
					ownerRunId: req.ownerRunId,
					nodeId: req.nodeId,
					status,
					result: { kind: "text", text: value },
					usage: { input: 1000, output: 200 },
				}),
			5,
		);

	if (req.nodeId === "planner") {
		const text = plannerError ? "not json at all" : "```json\n" + JSON.stringify(plan) + "\n```";
		reply("completed", text);
		return;
	}
	if (req.nodeId.endsWith(":gate")) {
		reply("completed", gateVerdict);
		return;
	}
	reply("completed", `worker report for ${req.nodeId}`);
});

// --- extension under test -------------------------------------------------------------------
const sent: string[] = [];
const pi = {
	events,
	registerTool(def: any) {
		(globalThis as any).__tool = def;
	},
	sendMessage(message: any) {
		sent.push(String(message?.content ?? ""));
	},
};

const mod = await import(`file:///C:/Users/tnguy/.pi/agent/extensions/gf-orchestrator.ts?t=${Date.now()}`);
mod.default(pi as any);
const tool = (globalThis as any).__tool;
check("registers gf_orchestrate", Boolean(tool) && tool.name === "gf_orchestrate");

const call = (params: any) => tool.execute("call", params, undefined, undefined, {});

// --- pure helpers ---------------------------------------------------------------------------
{
	const good = { objective: "o", batches: [{ id: "b1", title: "t", rows: ["S04-001"], workers: [{ task: "do the thing properly with files" }], verify: "npm test" }] };
	const ok = mod.validatePlan(good);
	check("validatePlan accepts a well-formed plan", ok.plan !== null, ok.errors.join(";"));

	const noVerify = JSON.parse(JSON.stringify(good));
	delete noVerify.batches[0].verify;
	check("validatePlan rejects a batch without a check", mod.validatePlan(noVerify).plan === null);

	const manyWorkers = JSON.parse(JSON.stringify(good));
	manyWorkers.batches[0].workers = [{ task: "aaaa bbbb cccc dddd eeee" }, { task: "aaaa bbbb cccc dddd eeee" }, { task: "aaaa bbbb cccc dddd eeee" }, { task: "aaaa bbbb cccc dddd eeee" }];
	check("validatePlan enforces the worker cap", mod.validatePlan(manyWorkers, 3).plan === null);

	const shortTask = JSON.parse(JSON.stringify(good));
	shortTask.batches[0].workers = [{ task: "do it" }];
	check("validatePlan rejects a vague worker task", mod.validatePlan(shortTask).plan === null, "a task under 20 chars is not a brief");

	const prompt = mod.buildPlannerPrompt("3 rows — MISSING 2", "S04-001 …", "work state body");
	check("planner prompt states the JSON shape", prompt.includes('"batches"') && prompt.includes("Return ONLY JSON"));
	check("planner prompt carries the ledger sample", prompt.includes("S04-001"));
}

// --- happy path: one batch, gate accepts ----------------------------------------------------
{
	plan = {
		objective: "close the weapon roster rows",
		batches: [
			{
				id: "b1",
				title: "weapon roster",
				rows: ["S04-001", "S04-002"],
				workers: [
					{ agent: "worker", task: "Add SMG-03 to Configs/Weapons with the spec stats, then verify by requiring the module.", context: "fresh" },
					{ agent: "worker", task: "Audit hitscan authority in CombatService and report the exact line that validates range.", context: "fresh" },
				],
				verify: "node .audit/check_weapons.mjs",
			},
		],
	};
	seen.length = 0;
	const out = await call({ action: "start", batches: 1, blockedOn: "weapon roster rows are unverified and I cannot tell which config fields the spec requires" });
	const text = out.content[0].text as string;
	check("planner launched with the strong model", seen[0]?.nodeId === "planner" && seen[0]?.model === "deepseek-v4-pro", JSON.stringify(seen[0]));
	check("two workers launched in parallel", seen.filter((s) => s.nodeId.includes(":worker")).length === 2);
	check("gate launched after workers", seen.some((s) => s.nodeId.endsWith(":gate")));
	check("plan written to .goal/ORCH_PLAN.json", existsSync(join(repo, ".goal", "ORCH_PLAN.json")));
	check("run reports PASS", text.includes("b1 PASS"), text.split("\n").slice(0, 3).join(" | "));
	check("owner is notified with the summary", sent.length === 1 && sent[0].includes("orchestrator —"));
	const log = readFileSync(join(repo, ".goal", "ORCH_LOG.jsonl"), "utf8").trim().split("\n");
	check("log records worker and gate stages", log.some((l) => l.includes('"stage":"worker"')) && log.some((l) => l.includes('"stage":"gate"')), `${log.length} entries`);
	check("log records the batch outcome", log.some((l) => l.includes('"stage":"batch"')));
}

// --- gate rejects: pipeline stops and does not advance --------------------------------------
{
	gateVerdict = "REJECTED — the worker cited no file paths";
	seen.length = 0;
	plan = {
		objective: "two batches",
		batches: [
			{ id: "b1", title: "first", rows: ["S04-001"], workers: [{ agent: "worker", task: "Implement the weapon config change and prove it loads.", context: "fresh" }], verify: "check" },
			{ id: "b2", title: "second", rows: ["S08-003"], workers: [{ agent: "worker", task: "Implement the mission variant and prove it spawns.", context: "fresh" }], verify: "check" },
		],
	};
	const out = await call({ action: "start", batches: 2, blockedOn: "two batches are queued and the first cannot be trusted without a gate" });
	const text = out.content[0].text as string;
	check("rejected gate stops the pipeline", text.includes("pipeline stopped"), text.split("\n").find((l) => l.includes("STOP")) ?? "");
	check("second batch never launched", !seen.some((s) => s.nodeId.startsWith("b2")), seen.map((s) => s.nodeId).join(","));
}

// --- escalation guard: no blocker named, nothing launched -------------------------------------
{
	seen.length = 0;
	const out = await call({ action: "start", batches: 1 });
	check("refuses start without a named blocker", String(out.content[0].text).includes("name the blocker"));
	check("refused start launches nothing", seen.length === 0, `launched ${seen.length}`);
}

// --- planner failure is reported, not thrown -------------------------------------------------
{
	plannerError = true;
	const out = await call({ action: "start", batches: 1, blockedOn: "weapon roster rows are unverified and I cannot tell which config fields the spec requires" });
	const text = out.content[0].text as string;
	check("unparseable plan stops with a reason", text.includes("STOPPED:") && text.includes("unparseable"), text.split("\n")[0]);
	plannerError = false;
}

// --- status + abort --------------------------------------------------------------------------
{
	const status = await call({ action: "status" });
	check("status reports idle after runs", String(status.content[0].text).includes("idle"));
	const abort = await call({ action: "abort" });
	check("abort is acknowledged", String(abort.content[0].text).includes("abort requested"));
}

// --- missing event bus is an error, not a crash ----------------------------------------------
{
	const pi2 = { registerTool(def: any) { (globalThis as any).__tool2 = def; }, sendMessage() {} };
	mod.default(pi2 as any);
	const tool2 = (globalThis as any).__tool2;
	const out = await tool2.execute("c", { action: "start" }, undefined, undefined, {});
	check("missing event bus reports instead of throwing", String(out.content[0].text).includes("event bus is unavailable"));
}

console.log(results.join("\n"));
const failed = results.filter((r) => r.startsWith("FAIL")).length;
console.log(`\n${results.length - failed}/${results.length} passed`);
rmSync(repo, { recursive: true, force: true });
process.exit(failed === 0 ? 0 : 1);
