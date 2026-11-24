// Headless harness for the goal loop. No Pi, no Studio: a fake ExtensionAPI records what the loop
// would send, and the ledger/state files live in a temp repo so the real .goal/ is untouched.
//
// Run: node --experimental-strip-types test_goal_loop.ts
import { mkdirSync, writeFileSync, readFileSync, existsSync, rmSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";

const repo = join(tmpdir(), `gf-loop-test-${Date.now()}`);
mkdirSync(join(repo, ".goal"), { recursive: true });
process.env.GF_REPO = repo;

// Minimal ledger so ledgerLine() reports something real instead of "ledger unreadable".
writeFileSync(
	join(repo, "REQUIREMENT_COVERAGE.csv"),
	'"requirement_id","status"\n"S00-001","UNKNOWN"\n"S00-002","VERIFIED"\n',
	"utf8",
);

const sent: string[] = [];
const commands = new Map<string, { handler: (args: string, ctx: any) => Promise<void> }>();
const handlers = new Map<string, ((event: any, ctx: any) => Promise<void>)[]>();

const pi = {
	registerCommand(name: string, def: any) {
		commands.set(name, def);
	},
	on(event: string, fn: any) {
		const list = handlers.get(event) ?? [];
		list.push(fn);
		handlers.set(event, list);
		return () => {};
	},
	sendUserMessage(text: string) {
		sent.push(text);
	},
};

const ctx = { ui: { notify: (m: string) => sent.push(`[notify] ${m}`) } };

async function fire(event: string, payload: any = {}) {
	for (const fn of handlers.get(event) ?? []) await fn({ type: event, ...payload }, ctx);
}

const mod = await import(new URL("file:///C:/Users/tnguy/.pi/agent/extensions/goal-loop.ts").href);
mod.default(pi as any);

const results: string[] = [];
function check(name: string, cond: boolean, detail = "") {
	results.push(`${cond ? "PASS" : "FAIL"}  ${name}${detail ? ` — ${detail}` : ""}`);
}

// 1. Commands registered.
check("registers /goal, /goal-stop, /goal-status, /goal-resume, /goal-unpause", ["goal", "goal-stop", "goal-status", "goal-resume", "goal-unpause"].every((c) => commands.has(c)));

// 2. Start with an explicit goal.
await commands.get("goal")!.handler("Ship the beta build", ctx);
check("kickoff carries the owner goal", sent.some((m) => m.includes("GOAL LOOP START") && m.includes("Ship the beta build")));
check("goal persisted", readFileSync(join(repo, ".goal", "ACTIVE_GOAL"), "utf8").includes("Ship the beta build"));
check("state persisted active", JSON.parse(readFileSync(join(repo, ".goal", "LOOP_STATE.json"), "utf8")).active === true);

// 3. A settled turn sends a continuation that still carries the goal.
sent.length = 0;
await fire("agent_settled", { aborted: false });
await new Promise((r) => setTimeout(r, 1200));
check("continuation carries the goal", sent[0]?.includes("GOAL (from the owner, still binding): Ship the beta build") === true, sent[0]?.slice(0, 80));

// 4. Compaction → next continuation is a resume packet that names the durable files.
sent.length = 0;
await fire("session_compact", { reason: "threshold", compactionEntry: {}, fromExtension: false, willRetry: false });
await fire("agent_settled", { aborted: false });
await new Promise((r) => setTimeout(r, 1200));
const packet = sent[0] ?? "";
check("post-compaction message says it is a resume", packet.includes("after a context compaction"));
check("resume packet names WORK_STATE.md", packet.includes("WORK_STATE.md"));
check("resume packet names the ledger", packet.includes("REQUIREMENT_COVERAGE.csv"));
check("resume packet restates the goal", packet.includes("Ship the beta build"));

// 5. Reload re-arms from LOOP_STATE.json. A reload gives a brand-new extension instance with empty
// in-memory state, so this section imports the module again with a cache-busting query instead of
// reusing the instance above.
const before = JSON.parse(readFileSync(join(repo, ".goal", "LOOP_STATE.json"), "utf8")).iteration;
await fire("session_shutdown", { reason: "reload" });
const sent2: string[] = [];
const handlers2 = new Map<string, ((event: any, ctx: any) => Promise<void>)[]>();
const pi2 = {
	registerCommand() {},
	on(event: string, fn: any) {
		const list = handlers2.get(event) ?? [];
		list.push(fn);
		handlers2.set(event, list);
		return () => {};
	},
	sendUserMessage(text: string) {
		sent2.push(text);
	},
};
const mod2 = await import(`file:///C:/Users/tnguy/.pi/agent/extensions/goal-loop.ts?fresh=${Date.now()}`);
mod2.default(pi2 as any);
for (const fn of handlers2.get("session_start") ?? []) await fn({ type: "session_start", reason: "reload" } as any, ctx);
await new Promise((r) => setTimeout(r, 1200));
check("reload re-injects a turn", sent2.some((m) => m.includes("after a context compaction")), sent2.join("|").slice(0, 120));
const after = JSON.parse(readFileSync(join(repo, ".goal", "LOOP_STATE.json"), "utf8")).iteration;
check("reload preserves iteration count", after > before, `${before} -> ${after}`);

// 6. Circuit breaker: hitting the compaction limit pauses instead of spinning.
for (let i = 0; i < 4; i += 1) await fire("session_compact", { reason: "threshold", compactionEntry: {}, fromExtension: false, willRetry: false });
check("compaction limit writes .goal/PAUSE", existsSync(join(repo, ".goal", "PAUSE")));
const paused = readFileSync(join(repo, ".goal", "PAUSE"), "utf8");
check("pause reason is recorded", paused.includes("compaction"), paused.trim());

// 7. After a pause, a settled turn must NOT send anything.
sent.length = 0;
await fire("agent_settled", { aborted: false });
await new Promise((r) => setTimeout(r, 1200));
check("paused loop stays silent", sent.filter((m) => !m.startsWith("[notify]")).length === 0, sent.join("|"));

// 8. STOP wins over an active loop.
rmSync(join(repo, ".goal", "PAUSE"));
writeFileSync(join(repo, ".goal", "STOP"), "owner said stop\n", "utf8");
await commands.get("goal")!.handler("", ctx);
check("refuses to start while STOP exists", sent.some((m) => m.includes("Refusing to start")));

console.log(results.join("\n"));
const failed = results.filter((r) => r.startsWith("FAIL")).length;
console.log(`\n${results.length - failed}/${results.length} passed`);
rmSync(repo, { recursive: true, force: true });
process.exit(failed === 0 ? 0 : 1);
