// Headless test for image-gc. Builds fake tool-result messages carrying image parts, runs the real
// extension, and asserts the safety properties that matter:
//   - never drops a message, only image bytes inside it
//   - keeps the newest KEEP images and prunes down when the count passes TRIGGER
//   - elisions are permanent (second call does not re-prune, so the prefix is stable)
//   - below the trigger nothing is touched
//
// Run: node --experimental-strip-types test_image_gc.ts
import { mkdirSync, rmSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";

const dir = join(tmpdir(), `gf-image-gc-${Date.now()}`);
mkdirSync(dir, { recursive: true });
process.env.GF_IMAGE_GC_STATE = join(dir, "state.json");
process.env.GF_IMAGE_GC_TRIGGER = "12";
process.env.GF_IMAGE_GC_KEEP = "3";

const handlers: ((e: any) => Promise<any>)[] = [];
const pi = {
	on(event: string, fn: any) {
		if (event === "context") handlers.push(fn);
		return () => {};
	},
	sendMessage() {},
};

const mod = await import(`file:///C:/Users/tnguy/.pi/agent/extensions/image-gc.ts?t=${Date.now()}`);
mod.default(pi as any);
const run = (messages: any[]) => handlers[0]({ type: "context", messages });

function makeMsg(i: number, imageBytes = 1000) {
	return {
		role: "toolResult",
		toolCallId: `call_${i}`,
		toolName: "screen_capture",
		content: [
			{ type: "text", text: `capture ${i}` },
			{ type: "image", data: "A".repeat(imageBytes), mimeType: "image/jpeg" },
		],
	};
}
const countImages = (msgs: any[]) =>
	msgs.reduce((n, m) => n + (Array.isArray(m.content) ? m.content.filter((p: any) => p?.type === "image").length : 0), 0);

const results: string[] = [];
const check = (name: string, cond: boolean, detail = "") => results.push(`${cond ? "PASS" : "FAIL"}  ${name}${detail ? ` — ${detail}` : ""}`);

// 1. Under the trigger: untouched.
{
	const msgs = [makeMsg(1), makeMsg(2), makeMsg(3)];
	const out = await run(msgs);
	check("below trigger: no rewrite", out === undefined, `returned ${out === undefined ? "undefined" : "messages"}`);
	check("below trigger: all images intact", countImages(msgs) === 3);
}

// 2. Over the trigger: pruned to KEEP, every message survives, text survives.
{
	const msgs = Array.from({ length: 20 }, (_, i) => makeMsg(i + 10));
	const out = await run(msgs);
	const result = out?.messages ?? msgs;
	check("above trigger: returns messages", Array.isArray(out?.messages));
	check("above trigger: keeps exactly KEEP images", countImages(result) === 3, `images=${countImages(result)}`);
	check("above trigger: message count unchanged", result.length === msgs.length, `${result.length} vs ${msgs.length}`);
	check("above trigger: tool results still present", result.every((m: any) => m.role === "toolResult" && m.toolCallId));
	check("above trigger: text parts preserved", result.every((m: any) => m.content.some((p: any) => p.type === "text")));
	const stubs = result.flatMap((m: any) => m.content.filter((p: any) => p.type === "text" && p.text.includes("elided by image-gc")));
	check("above trigger: stubs explain the elision", stubs.length === 17, `stubs=${stubs.length}`);
	check("above trigger: newest captures kept", result.slice(-3).every((m: any) => m.content.some((p: any) => p.type === "image")));

	// 3. Stability: with the ORIGINALS projected again (which is what Pi does) the elisions are
	// re-applied, so the same 3 images stay live and the boundary does not move.
	const again = await run(msgs);
	const second = again?.messages ?? msgs;
	check("original projection re-applies elisions", countImages(second) === 3, `images=${countImages(second)}`);
}

// 4. New captures above the trigger prune again, and old elisions stay elided.
{
	// 20 originals (17 already elided, 3 kept) plus 12 fresh captures: 15 live, above the trigger.
	const msgs = [...Array.from({ length: 20 }, (_, i) => makeMsg(i + 10)), ...Array.from({ length: 12 }, (_, i) => makeMsg(i + 100))];
	const out = await run(msgs);
	const result = out?.messages ?? msgs;
	check("new captures: pruned back to KEEP live", countImages(result) === 3, `images=${countImages(result)}`);
	check("new captures: newest three survive", result.slice(-3).every((m: any) => m.content.some((p: any) => p.type === "image")));
	const saved = JSON.parse(readFileSync(process.env.GF_IMAGE_GC_STATE!, "utf8"));
	check("state file records every elision", Object.keys(saved).length === 29, `ids=${Object.keys(saved).length}`);
}

console.log(results.join("\n"));
const failed = results.filter((r) => r.startsWith("FAIL")).length;
console.log(`\n${results.length - failed}/${results.length} passed`);
rmSync(dir, { recursive: true, force: true });
process.exit(failed === 0 ? 0 : 1);
