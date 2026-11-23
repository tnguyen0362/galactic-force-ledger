/**
 * Offline harness test for the goal-loop extension: stubs the Pi API and proves that
 *   1. the four commands register,
 *   2. /goal sends a kickoff and marks the loop active,
 *   3. agent_settled sends a continuation (the loop actually loops),
 *   4. .goal/STOP stops it and no further continuation is sent,
 *   5. .goal/PAUSE defers instead of firing.
 */
import { mkdirSync, writeFileSync, rmSync, existsSync } from "node:fs";

const REPO = "C:/tmp/goaltest";
process.env.GF_REPO = REPO;
mkdirSync(`${REPO}/.goal`, { recursive: true });
writeFileSync(`${REPO}/REQUIREMENT_COVERAGE.csv`, "id,spec_anchor,requirement,required_count,present_count,status\nLC-001,x,y,3,1,ABSENT\nLC-002,x,y,1,0,PARTIAL\n");

const commands = new Map();
const handlers = new Map();
const sent = [];
let fakePi;
fakePi = {
	registerCommand: (name, def) => commands.set(name, def),
	on: (event, fn) => {
		if (!handlers.has(event)) handlers.set(event, []);
		handlers.get(event).push(fn);
	},
	sendUserMessage: (text) => sent.push(String(text)),
	appendEntry: () => {},
	registerTool: () => {},
};

const mod = await import("file:///C:/Users/tnguy/.pi/agent/extensions/goal-loop.ts");
mod.default(fakePi);

const ui = { notify: (m) => console.log("   notify:", m) };
const ctx = { ui, isIdle: () => true }; // no sendUserMessage: this is the real command context

const results = [];
const check = (name, ok, detail = "") => {
	results.push({ name, ok, detail });
	console.log(`${ok ? "PASS" : "FAIL"}  ${name}${detail ? " — " + detail : ""}`);
};

check("commands registered", ["goal", "goal-stop", "goal-status", "goal-resume"].every((c) => commands.has(c)),
	[...commands.keys()].join(","));
check("agent_settled handler registered", (handlers.get("agent_settled") ?? []).length === 1);

// 1) /goal
await commands.get("goal").handler("ship the station", ctx);
check("/goal sent kickoff", sent.length === 1 && sent[0].includes("GOAL LOOP START"));
check("kickoff names the ledger + capture step", sent[0].includes("REQUIREMENT_COVERAGE.csv") && sent[0].includes("screen_capture"));

// 2) settle -> continuation
const settle = handlers.get("agent_settled")[0];
await settle({ aborted: false }, ctx);
await new Promise((r) => setTimeout(r, 1200));
check("agent_settled sent a continuation (loop runs)", sent.length === 2 && sent[1].includes("continuation 1"),
	`sent=${sent.length}`);
check("continuation reports ledger counts", sent[1].includes("ABSENT 1") && sent[1].includes("PARTIAL 1"));

// 3) PAUSE defers
writeFileSync(`${REPO}/.goal/PAUSE`, "owner in studio");
await settle({ aborted: false }, ctx);
await new Promise((r) => setTimeout(r, 1200));
check("PAUSE defers (no new message)", sent.length === 2, `sent=${sent.length}`);
rmSync(`${REPO}/.goal/PAUSE`, { force: true });
await new Promise((r) => setTimeout(r, 6000));
check("resumes after PAUSE removed", sent.length === 3, `sent=${sent.length}`);

// 4) STOP halts
writeFileSync(`${REPO}/.goal/STOP`, "owner said stop");
await settle({ aborted: false }, ctx);
await new Promise((r) => setTimeout(r, 1200));
check("STOP halts the loop", sent.length === 3, `sent=${sent.length}`);

// 5) /goal refuses to start while STOP exists
const before = sent.length;
await commands.get("goal").handler("", ctx);
check("/goal refuses to start under STOP", sent.length === before);

// 6) abort stops the loop
rmSync(`${REPO}/.goal/STOP`, { force: true });
await commands.get("goal").handler("again", ctx);
await settle({ aborted: true }, ctx);
const afterAbort = sent.length;
await settle({ aborted: false }, ctx);
await new Promise((r) => setTimeout(r, 1200));
check("abort (Escape) stops the loop", sent.length === afterAbort, `sent=${sent.length}`);

// The original bug: ctx.sendUserMessage is not a function on this host.
let threw = false;
try {
	await commands.get("goal-stop").handler("", ctx);
	rmSync(`${REPO}/.goal/STOP`, { force: true });
	await commands.get("goal").handler("regression", ctx);
} catch (error) {
	threw = true;
	console.log("   handler threw:", String(error));
}
check("command handlers work without ctx.sendUserMessage", !threw);

const failed = results.filter((r) => !r.ok);
console.log(`\n${results.length - failed.length}/${results.length} checks passed`);
if (failed.length) process.exitCode = 1;
