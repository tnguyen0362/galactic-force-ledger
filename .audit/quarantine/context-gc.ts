/**
 * Context GC — prune old screenshots and shorten old bulk tool output before it reaches the model.
 *
 * Measured, not assumed: in one long build session the tool traffic was 108 MB, of which
 * screen_capture was 105.1 MB across 389 calls (avg 270 KB of base64). Everything else combined was
 * under 3 MB, and that was still mostly whole-module Lua source dumps. Context reached 818k tokens and
 * compacted at that size. The text of the work was never the problem — the frames and the repeated
 * dumps were.
 *
 * Safety properties, in order of importance:
 * 1. It never removes a message. Images are replaced by a text stub inside the same tool result, and
 *    long text is shortened in place. Tool-call pairing stays valid and the model still sees that the
 *    call happened and what it was for.
 * 2. Decisions are permanent and recorded by tool-call id, so the prefix is stable between prunes.
 *    Re-deciding what to keep on every call would invalidate the prompt cache continuously.
 * 3. It is conservative by default and only tightens as context approaches the soft limit, so a
 *    prune is rare rather than per-request.
 *
 * Findings survive because a frame or a dump is one artefact among several: VISUAL_REVIEW.md,
 * ASSET_DEBT.csv, WORK_STATE.md and the ledger carry the conclusions they supported.
 */
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";

const STATE_FILE = process.env.GF_CONTEXT_GC_STATE ?? join(process.env.HOME ?? process.env.USERPROFILE ?? ".", ".pi", "context-gc.json");
const IMAGE_TRIGGER = Number(process.env.GF_IMAGE_GC_TRIGGER ?? 12);
const IMAGE_KEEP = Number(process.env.GF_IMAGE_GC_KEEP ?? 3);
const TEXT_MIN_CHARS = Number(process.env.GF_TEXT_GC_MIN ?? 8000);
const TEXT_KEEP_RESULTS = Number(process.env.GF_TEXT_GC_KEEP ?? 5);
// Soft limit. The owner asked for pruning to start around 600k rather than waiting for the 1M wall
// (the last session first compacted at 1.08M and then at 818k). Past this point the limits tighten.
const SOFT_TOKENS = Number(process.env.GF_CONTEXT_GC_SOFT ?? 600_000);

interface GcState {
	images: Record<string, number>;
	texts: Record<string, number>;
	prunes: number;
	lastAt?: string;
	/** Latched mode. Persisted so a restart does not re-enter loose mode mid-crisis. */
	tight?: boolean;
	/** Timestamps of recent tight<->loose transitions, for the sawtooth detector. */
	flips?: number[];
}

function load(): GcState {
	try {
		const raw = JSON.parse(readFileSync(STATE_FILE, "utf8")) as Partial<GcState>;
		return {
			images: raw.images ?? {},
			texts: raw.texts ?? {},
			prunes: raw.prunes ?? 0,
			lastAt: raw.lastAt,
			tight: raw.tight === true,
			flips: Array.isArray(raw.flips) ? raw.flips.filter((n) => typeof n === "number") : [],
		};
	} catch {
		return { images: {}, texts: {}, prunes: 0 };
	}
}

function save(state: GcState): void {
	try {
		mkdirSync(dirname(STATE_FILE), { recursive: true });
		writeFileSync(STATE_FILE, JSON.stringify(state), "utf8");
	} catch {
		/* pruning is best effort; a failed write must never break a request */
	}
}

interface Msg {
	role?: string;
	toolCallId?: string;
	toolName?: string;
	content?: unknown;
}

function isImage(part: unknown): part is { type: "image"; data?: string } {
	return typeof part === "object" && part !== null && (part as { type?: string }).type === "image";
}
function isText(part: unknown): part is { type: "text"; text?: string } {
	return typeof part === "object" && part !== null && (part as { type?: string }).type === "text";
}

/** Map every toolCall id to its name and raw arguments, so duplicate calls can be recognised. */
function callIndex(messages: Msg[]): Map<string, { name: string; args: string }> {
	const index = new Map<string, { name: string; args: string }>();
	for (const m of messages) {
		if (!Array.isArray(m.content)) continue;
		for (const part of m.content as unknown[]) {
			if (typeof part !== "object" || part === null) continue;
			const call = part as { type?: string; id?: string; name?: string; arguments?: unknown };
			if (call.type !== "toolCall" || typeof call.id !== "string") continue;
			index.set(call.id, { name: String(call.name ?? ""), args: typeof call.arguments === "string" ? call.arguments : JSON.stringify(call.arguments ?? "") });
		}
	}
	return index;
}

function shorten(text: string, keepHead: number, keepTail: number, label: string): string {
	const dropped = text.length - keepHead - keepTail;
	if (dropped <= 0) return text;
	return `${text.slice(0, keepHead)}\n… [context-gc shortened ${Math.round(dropped / 1024)} KB from ${label}; re-run the tool if you need the middle]\n${text.slice(-keepTail)}`;
}

export default function contextGc(pi: ExtensionAPI): void {
	const state = load();
	let reportedAt = 0;
	const sawtooth: string[] = [];

	pi.on("context", async (event, ctx) => {
		const messages = (event.messages ?? []) as Msg[];

		// Rough token estimate: text chars are ~3.4 per token here, an image counts as ~1300 tokens.
		let chars = 0;
		let images = 0;
		for (const m of messages) {
			if (!Array.isArray(m.content)) continue;
			for (const part of m.content as unknown[]) {
				if (isImage(part)) images += 1;
				else if (isText(part)) chars += part.text?.length ?? 0;
				else if (typeof part === "object" && part !== null) chars += JSON.stringify(part).length;
			}
		}
		// Pi knows the real number (getContextUsage); the character heuristic is only a fallback so the
		// module stays testable headlessly. Bias high on purpose: overshooting the limit is the costly side.
		let estimate = Math.round(chars / 3.4 + images * 1300);
		try {
			const usage = (ctx as { getContextUsage?: () => { tokens: number | null } | undefined } | undefined)?.getContextUsage?.();
			if (usage && typeof usage.tokens === "number" && usage.tokens > 0) estimate = usage.tokens;
		} catch {
			/* no usage available: keep the estimate */
		}

		// Hysteresis, because a single-threshold pruner sawtooths: cross 600k, prune just under it,
		// grow, cross again, forever. Enter tight at SOFT, leave only below FLOOR (70% of it), and while
		// tight keep pruning until the projected size is under FLOOR rather than stopping at the trigger.
		const SOFT = SOFT_TOKENS;
		const FLOOR = Math.round(SOFT * 0.7);
		let tight = state.tight === true;
		if (estimate >= SOFT) tight = true;
		else if (tight && estimate <= FLOOR) tight = false;
		// Sawtooth detector. Hysteresis stops per-request flapping, but a context that keeps re-growing to
		// the trigger is a summarisation problem, not a pruning one: at that point the right move is a real
		// compaction (which keeps a summary) rather than more elision (which keeps nothing).
		const flips = (state.flips ?? []).filter((t) => Date.now() - t < 20 * 60_000);
		if (flips.length >= 3) {
			state.flips = [];
			save(state);
			try {
				(ctx as { compact?: (o?: unknown) => void } | undefined)?.compact?.({
					customInstructions:
						"Preserve verbatim where possible: the owner goal, the goal-loop iteration, every requirement id under discussion, " +
						"file paths, measured numbers and the open failures. This compaction fired because pruning alone was oscillating, " +
						"so the summary must carry the working state, not just a narrative.",
				});
			} catch {
				/* compaction is optional; pruning already happened */
			}
		}
		let modeChanged = false;
		if (state.tight !== tight) {
			state.tight = tight;
			modeChanged = true;
			state.flips = [...flips, Date.now()];
			sawtooth.push(tight ? "entered tight" : "left tight");
		}
		const target = tight ? FLOOR : Number.POSITIVE_INFINITY;
		let projected = estimate;

		const textMin = tight ? 2500 : TEXT_MIN_CHARS;
		const textKeep = tight ? 1 : TEXT_KEEP_RESULTS;
		const imageKeep = tight ? 1 : IMAGE_KEEP;

		// Index the image carriers and the tool results that carry text.
		const imageCarriers: { message: Msg; partIndex: number; id: string; bytes: number; name: string }[] = [];
		const textCarriers: { message: Msg; partIndex: number; id: string; length: number; name: string }[] = [];
		const toolResults: Msg[] = [];
		for (const message of messages) {
			if (!Array.isArray(message.content)) continue;
			const content = message.content as unknown[];
			if (message.role === "toolResult") toolResults.push(message);
			for (let i = 0; i < content.length; i += 1) {
				const part = content[i];
				const id = `${message.toolCallId ?? "x"}:${i}`;
				if (isImage(part)) {
					imageCarriers.push({
						message,
						partIndex: i,
						id,
						bytes: typeof part.data === "string" ? part.data.length : 0,
						name: message.toolName ?? "capture",
					});
				} else if (isText(part) && (part.text?.length ?? 0) >= textMin) {
					textCarriers.push({ message, partIndex: i, id, length: part.text?.length ?? 0, name: message.toolName ?? "tool" });
				}
			}
		}

		const recentResults = new Set(toolResults.slice(-textKeep));
		const touched = new Set<Msg>();
		const calls = callIndex(messages);
		const rewritten = new Map<Msg, unknown[]>();
		let changed = 0;
		let savedTokens = 0;

		function slot(m: Msg): unknown[] {
			let content = rewritten.get(m);
			if (!content) {
				content = [...(m.content as unknown[])];
				rewritten.set(m, content);
			}
			return content;
		}

		function elideImage(c: (typeof imageCarriers)[number], index: number): void {
			state.images[c.id] = c.bytes;
			slot(c.message)[c.partIndex] = {
				type: "text",
				text: `[screenshot elided by context-gc: ${c.name} #${index}, ${Math.round(c.bytes / 1024)} KB — what it showed is recorded in VISUAL_REVIEW.md]`,
			};
			projected -= 1300;
			savedTokens += 1300;
			changed += 1;
		}

		function shortenText(c: (typeof textCarriers)[number]): void {
			const part = (c.message.content as { text?: string }[])[c.partIndex];
			const original = part.text ?? "";
			const head = tight ? 700 : 1200;
			const tail = tight ? 200 : 400;
			const next = shorten(original, head, tail, c.name);
			state.texts[c.id] = c.length;
			slot(c.message)[c.partIndex] = { type: "text", text: next };
			const saved = Math.max(0, original.length - next.length);
			projected -= saved / 3.4;
			savedTokens += saved / 3.4;
			changed += 1;
		}

		// 1. Re-apply every decision made earlier. The projected session still holds the original bytes,
		// so skipping this would let pruned frames and dumps back in as soon as a later call looked calm.
		let priorImages = 0;
		for (const c of imageCarriers) {
			if (!state.images[c.id]) continue;
			priorImages += 1;
			slot(c.message)[c.partIndex] = {
				type: "text",
				text: `[screenshot elided by context-gc: ${c.name} #${priorImages}, ${Math.round(c.bytes / 1024)} KB — what it showed is recorded in VISUAL_REVIEW.md]`,
			};
			changed += 1;
		}
		for (const message of toolResults) {
			if (!message.toolCallId) continue;
			if (!state.texts[`dup:${message.toolCallId}`]) continue;
			const content = message.content as { type?: string; text?: string }[];
			for (let i = 0; i < content.length; i += 1) {
				if (content[i].type !== "text") continue;
				if (touched.has(message)) continue;
				const call = calls.get(message.toolCallId);
				slot(message)[i] = {
					type: "text",
					text: `[context-gc: duplicate call superseded by a later identical ${call?.name ?? "call"} — the newest copy of this output is kept in full]`,
				};
				changed += 1;
			}
		}
		for (const c of textCarriers) {
			if (!state.texts[c.id]) continue;
			const part = (c.message.content as { text?: string }[])[c.partIndex];
			slot(c.message)[c.partIndex] = {
				type: "text",
				text: shorten(part.text ?? "", tight ? 700 : 1200, tight ? 200 : 400, c.name),
			};
			changed += 1;
		}

		// 2. Duplicate collapse. Block-level: when the same tool was called with the same arguments more
		// than once, every copy but the newest is superseded — re-reading a module after editing it is the
		// single most common waste in this project, and the newest copy is the one that is still true.
		const byArgs = new Map<string, Msg[]>();
		for (const message of toolResults) {
			if (!message.toolCallId) continue;
			const call = calls.get(message.toolCallId);
			if (!call) continue;
			const size = (message.content as { type?: string; text?: string }[]).reduce((n, part) => n + (part.type === "text" ? (part.text?.length ?? 0) : 0), 0);
			if (size < 800) continue;
			const key = `${call.name}::${call.args}`;
			const list = byArgs.get(key) ?? [];
			list.push(message);
			byArgs.set(key, list);
		}
		for (const [, list] of byArgs) {
			if (list.length < 2) continue;
			const newest = list[list.length - 1];
			for (const stale of list.slice(0, -1)) {
				if (state.texts[`dup:${stale.toolCallId}`]) continue;
				const content = stale.content as { type?: string; text?: string }[];
				for (let i = 0; i < content.length; i += 1) {
					const part = content[i];
					if (part.type !== "text" || (part.text?.length ?? 0) < 800) continue;
					const saved = part.text?.length ?? 0;
					slot(stale)[i] = {
						type: "text",
						text: `[context-gc: duplicate call superseded by a later identical ${(calls.get(stale.toolCallId) ?? { name: "call" }).name} — ${Math.round(saved / 1024)} KB dropped; the newest copy of this output is kept in full]`,
					};
					state.texts[`dup:${stale.toolCallId}`] = saved;
					projected -= saved / 3.4;
					changed += 1;
					savedTokens += saved / 3.4;
					touched.add(stale);
				}
			}
		}

		// 3. Prune fresh items, oldest first, until the projection is under the target.
		const liveImages = imageCarriers.filter((c) => !state.images[c.id]);
		const imageCandidates = tight
			? liveImages.slice(0, Math.max(0, liveImages.length - imageKeep))
			: liveImages.length > IMAGE_TRIGGER
				? liveImages.slice(0, liveImages.length - imageKeep)
				: [];
		let index = priorImages;
		for (const c of imageCandidates) {
			index += 1;
			elideImage(c, index);
		}

		// Oldest first: the oldest bulk output is the least likely to be needed verbatim. Order is taken
		// from one index pass rather than indexOf inside a comparator (that was O(n log n) scans).
		const order = new Map<Msg, number>();
		for (let i = 0; i < messages.length; i += 1) order.set(messages[i], i);
		const textCandidates = textCarriers
			.filter((c) => !state.texts[c.id] && !recentResults.has(c.message))
			.sort((a, b) => (order.get(a.message) ?? 0) - (order.get(b.message) ?? 0));
		for (const c of textCandidates) {
			if (tight && projected <= target) break;
			shortenText(c);
		}

		// A mode change must persist even when nothing was rewritten, otherwise the latch is lost and the
		// next request re-decides from scratch — which is the sawtooth this exists to prevent.
		if (changed === 0 && !modeChanged) return;
		state.prunes += 1;
		state.lastAt = new Date().toISOString();
		save(state);

		if (Date.now() - reportedAt > 60_000) {
			reportedAt = Date.now();
			try {
				pi.sendMessage?.({
					role: "system",
					content: `context-gc: ~${estimate.toLocaleString()} -> ~${Math.max(0, Math.round(projected)).toLocaleString()} tokens this pass (soft ${SOFT.toLocaleString()}, floor ${FLOOR.toLocaleString()}); ${tight ? "tight mode" : "normal mode"}${sawtooth.length ? ` (${sawtooth.slice(-1)[0]})` : ""}; ${Object.keys(state.images).length} screenshot(s) elided, ${Object.keys(state.texts).length} bulk result(s) shortened in total.`,
				} as never);
			} catch {
				/* notification is optional */
			}
		}

		return { messages: messages.map((m) => (rewritten.has(m) ? { ...m, content: rewritten.get(m) } : m)) as never };
	});
}
