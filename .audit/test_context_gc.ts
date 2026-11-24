// Headless test for context-gc: image elision, bulk-text shortening, soft-limit tightening, stability.
// Run: node --experimental-strip-types test_context_gc.ts
import { mkdirSync, rmSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";

const dir = join(tmpdir(), `gf-context-gc-${Date.now()}`);
mkdirSync(dir, { recursive: true });
process.env.GF_CONTEXT_GC_STATE = join(dir, "state.json");
delete process.env.GF_CONTEXT_GC_SOFT;

const results: string[] = [];
const check = (name: string, cond: boolean, detail = "") => results.push(`${cond ? "PASS" : "FAIL"}  ${name}${detail ? ` — ${detail}` : ""}`);

async function freshModule(tag: string) {
	const handlers: any[] = [];
	const pi = {
		on(event: string, fn: any) {
			if (event === "context") handlers.push(fn);
			return () => {};
		},
		sendMessage() {},
	};
	const mod = await import(`file:///C:/Users/tnguy/.pi/agent/extensions/context-gc.ts?t=${tag}`);
	mod.default(pi as any);
	return async (messages: any[]) => {
		const out = await handlers[0]({ type: "context", messages });
		return out?.messages ?? messages;
	};
}

const img = (i: number, bytes = 1000) => ({
	role: "toolResult",
	toolCallId: `img_${i}`,
	toolName: "screen_capture",
	content: [
		{ type: "text", text: `capture ${i}` },
		{ type: "image", data: "A".repeat(bytes), mimeType: "image/jpeg" },
	],
});
const bulk = (i: number, chars = 20000) => ({
	role: "toolResult",
	toolCallId: `bulk_${i}`,
	toolName: "execute_luau",
	content: [{ type: "text", text: `HEAD-${i}-` + "x".repeat(chars) + `-TAIL-${i}` }],
});
const userMsg = (i: number) => ({ role: "user", content: [{ type: "text", text: `instruction ${i}` }] });
const countImages = (msgs: any[]) => msgs.reduce((n, m) => n + (Array.isArray(m.content) ? m.content.filter((p: any) => p?.type === "image").length : 0), 0);
const isShortened = (msgs: any[], id: string) => {
	const m = msgs.find((x: any) => x.toolCallId === id);
	return Boolean(m?.content?.[0]?.text?.includes("context-gc shortened"));
};

// 1. Calm context: nothing touched.
{
	const run = await freshModule("calm");
	const msgs = [img(1), img(2), bulk(1, 3000), userMsg(1)];
	const out = await run(msgs);
	check("below thresholds: images intact", countImages(out) === 2);
	check("below thresholds: small text intact", !isShortened(out, "bulk_1"));
}

// 2. Images above the trigger prune to KEEP, messages survive.
{
	const run = await freshModule("images");
	const msgs = Array.from({ length: 20 }, (_, i) => img(i));
	const out = await run(msgs);
	check("images: keeps 3 live", countImages(out) === 3, `images=${countImages(out)}`);
	check("images: no message dropped", out.length === 20);
	check("images: stub explains what was there", out[0].content.some((p: any) => String(p.text ?? "").includes("elided by context-gc")));
}

// 3. Old bulk text is shortened, recent bulk text is not.
{
	const run = await freshModule("text");
	const msgs = [
		bulk(1, 20000), userMsg(1), bulk(2, 20000), userMsg(2), bulk(3, 20000), userMsg(3),
		bulk(4, 20000), userMsg(4), bulk(5, 20000), userMsg(5),
		bulk(6, 20000), bulk(7, 20000), bulk(8, 20000), bulk(9, 20000), bulk(10, 20000),
	];
	const out = await run(msgs);
	check("text: oldest bulk result shortened", isShortened(out, "bulk_1"));
	check("text: recent bulk results untouched", !isShortened(out, "bulk_10"), `bulk_10 shortened=${isShortened(out, "bulk_10")}`);
	const shortened = out.find((m: any) => m.toolCallId === "bulk_1").content[0].text;
	check("text: shortened keeps head and tail", shortened.includes("HEAD-1-") && shortened.includes("-TAIL-1"));
	check("text: shortened stays small", shortened.length < 3000, `len=${shortened.length}`);
}

// 4. Stability: feeding the originals again re-applies the same decisions.
{
	const run = await freshModule("stable");
	const msgs = [bulk(1, 20000), userMsg(1), bulk(6, 20000), bulk(7, 20000), bulk(8, 20000), bulk(9, 20000), bulk(10, 20000)];
	const out = await run(msgs);
	check("stability: prior decision still applied", isShortened(out, "bulk_1"));
	check("stability: nothing new shortened", !isShortened(out, "bulk_6"), `bulk_6 shortened=${isShortened(out, "bulk_6")}`);
}

// 5. Soft limit: above 600k estimated tokens the limits tighten (images to 1, text from 2.5 KB).
{
	process.env.GF_CONTEXT_GC_SOFT = "1000";
	process.env.GF_CONTEXT_GC_STATE = join(dir, "tight.json");
	const run = await freshModule("tight");
	const msgs = [bulk(50, 4000), userMsg(0), ...Array.from({ length: 6 }, (_, i) => img(100 + i))];
	const out = await run(msgs);
	check("soft limit: images pruned to 1", countImages(out) === 1, `images=${countImages(out)}`);
	check("soft limit: medium text now pruned", isShortened(out, "bulk_50"));
	delete process.env.GF_CONTEXT_GC_SOFT;
}


// 6. Hysteresis: enter tight at 600k, stay tight until the context drops below 70% of it. This is the
// sawtooth guard. A single threshold would prune to just under 600k and drift straight back over it.
{
	process.env.GF_CONTEXT_GC_SOFT = "600000";
	process.env.GF_CONTEXT_GC_STATE = join(dir, "hysteresis.json");
	const run = await freshModule("hysteresis");
	const bigText = (i: number, chars: number) => ({
		role: "toolResult",
		toolCallId: `h_${i}`,
		toolName: "execute_luau",
		content: [{ type: "text", text: `H${i}-` + "y".repeat(chars) }],
	});
	const tightNow = () => JSON.parse(readFileSync(process.env.GF_CONTEXT_GC_STATE!, "utf8")).tight === true;

	// ~700k tokens of old bulk text: 120 results at 20 KB each (2.4M chars / 3.4).
	await run([...Array.from({ length: 120 }, (_, i) => bigText(i, 20000)), userMsg(1), userMsg(2)]);
	check("hysteresis: enters tight above the soft limit", tightNow());

	// ~500k: above the floor, below the soft limit. Must stay tight instead of flip-flopping.
	await run([bigText(500, 1700000), userMsg(3), userMsg(4)]);
	check("hysteresis: stays tight between floor and soft", tightNow(), "500k must not reopen loose mode");

	// Small context: below the floor, so it releases.
	await run([userMsg(5), userMsg(6)]);
	check("hysteresis: leaves tight below the floor", !tightNow());
	delete process.env.GF_CONTEXT_GC_SOFT;
}

// 7. Duplicate collapse: the same tool called twice with the same arguments keeps only the newest copy.
{
	process.env.GF_CONTEXT_GC_STATE = join(dir, "dup.json");
	const run = await freshModule("dup");
	const call = (id: string, args: string) => ({ role: "assistant", content: [{ type: "toolCall", id, name: "read", arguments: args }] });
	const result = (id: string, chars = 9000) => ({ role: "toolResult", toolCallId: id, toolName: "read", content: [{ type: "text", text: `BODY-${id}-` + "z".repeat(chars) }] });
	const msgs = [
		call("c1", '{"path":"src/a.ts"}'), result("c1"),
		call("c2", '{"path":"src/b.ts"}'), result("c2"),
		call("c3", '{"path":"src/a.ts"}'), result("c3"),
		...Array.from({ length: 5 }, (_, i) => userMsg(200 + i)),
	];
	const out = await run(msgs);
	const stale = out.find((m: any) => m.toolCallId === "c1").content[0].text;
	const fresh = out.find((m: any) => m.toolCallId === "c3").content[0].text;
	const other = out.find((m: any) => m.toolCallId === "c2").content[0].text;
	check("duplicates: older identical call is superseded", stale.includes("duplicate call superseded"), stale.slice(0, 60));
	check("duplicates: newest identical call is kept in full", fresh.startsWith("BODY-c3-") && fresh.length > 8000);
	check("duplicates: different arguments untouched", other.startsWith("BODY-c2-"));
}

// 8. Sawtooth: repeated tight/loose flips ask Pi for a real compaction instead of more elision.
{
	process.env.GF_CONTEXT_GC_SOFT = "1000";
	process.env.GF_CONTEXT_GC_STATE = join(dir, "sawtooth.json");
	const compactions: any[] = [];
	const handlers: any[] = [];
	const pi = { on(_e: string, fn: any) { handlers.push(fn); return () => {}; }, sendMessage() {} };
	const mod = await import(`file:///C:/Users/tnguy/.pi/agent/extensions/context-gc.ts?t=${Date.now()}-saw`);
	mod.default(pi as any);
	const ctx = { getContextUsage: () => ({ tokens: 700000, contextWindow: 1000000 }), compact: (o: any) => compactions.push(o) };
	const run = async (msgs: any[]) => (await handlers[0]({ type: "context", messages: msgs }, ctx))?.messages ?? msgs;

	await run([userMsg(1)]);
	await run([userMsg(2)]);
	await run([userMsg(3)]);
	check("sawtooth: no compaction on a stable mode", compactions.length === 0, `compactions=${compactions.length}`);
	delete process.env.GF_CONTEXT_GC_SOFT;
}

console.log(results.join("\n"));
const failed = results.filter((r) => r.startsWith("FAIL")).length;
console.log(`\n${results.length - failed}/${results.length} passed`);
rmSync(dir, { recursive: true, force: true });
process.exit(failed === 0 ? 0 : 1);
