const mod = await import("file:///C:/Users/tnguy/.pi/agent/extensions/context-gc.ts");
const handlers = {};
mod.default({ on: (n, fn) => { handlers[n] = fn; } });
const big = (id) => ({ role: "toolResult", toolName: "bash", toolCallId: id, content: [{ type: "text", text: "Y".repeat(4000) }] });
const messages = [...Array.from({ length: 1500 }, (_, i) => big("t" + i)), ...Array.from({ length: 8 }, (_, i) => big("r" + i))];
const ctx = (tokens) => ({ getContextUsage: () => ({ tokens, contextWindow: 1000000 }), compact: () => {} });

// mid-loop: last message is a tool result, loop not settled -> must do nothing
const midLoop = await handlers.context({ messages }, ctx(800000));
const afterMidLoop = midLoop === undefined;

// settle the loop, then the next context call should prune to <= 60%
await handlers.agent_settled({ aborted: false }, ctx(800000));
const pruned = await handlers.context({ messages }, ctx(800000));
const out = pruned?.messages ?? messages;
const chars = JSON.stringify(out).length;
const est = Math.round(chars / 3.5);
const secondCallUnchanged = (await handlers.context({ messages }, ctx(800000))) === undefined;

// below trigger: even when settled, no pruning
await handlers.agent_settled({ aborted: false }, ctx(800000));
const lowUsage = (await handlers.context({ messages }, ctx(500000))) === undefined;

console.log(JSON.stringify({ midLoopUnchanged: afterMidLoop, prunedEstTokens: est, under60Pct: est <= 600000, secondCallUnchanged, lowUsageUnchanged: lowUsage }));
