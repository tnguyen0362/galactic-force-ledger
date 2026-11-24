const mod = await import("file:///C:/Users/tnguy/.pi/agent/extensions/context-gc.ts");
const handlers = {}; mod.default({ on: (n, fn) => { handlers[n] = fn; } });
const pair = (i) => ([
  { role: "assistant", content: [{ type: "toolCall", id: "c" + i, name: "x", arguments: { code: "Z".repeat(8000) } }] },
  { role: "toolResult", toolCallId: "c" + i, toolName: "x", content: [{ type: "text", text: "Y".repeat(6000) }] },
]);
const big = []; for (let i = 0; i < 300; i += 1) big.push(...pair(i));
big.push(...Array.from({ length: 8 }, (_, i) => ({ role: "toolResult", toolCallId: "r" + i, content: [{ type: "text", text: "recent" }] })));
const small = big.slice(-8);
// The key test: report a LOW usage (as if the previous request was pruned) while sending a BIG payload.
const lowUsageCtx = { getContextUsage: () => ({ tokens: 297000, contextWindow: 1000000 }), compact: () => {} };
const highUsageCtx = { getContextUsage: () => ({ tokens: 950000, contextWindow: 1000000 }), compact: () => {} };
const withLow = await handlers.context({ messages: big }, lowUsageCtx);
const withHigh = await handlers.context({ messages: big }, highUsageCtx);
const smallOut = await handlers.context({ messages: small }, lowUsageCtx);
const size = (o) => o?.messages ? JSON.stringify(o.messages).length : null;
console.log(JSON.stringify({
  bigWithLowUsagePruned: size(withLow) !== null && size(withLow) < 1.0e6,
  bigWithHighUsagePruned: size(withHigh) !== null && size(withHigh) < 1.0e6,
  identicalResult: size(withLow) === size(withHigh),
  smallPassedThrough: smallOut === undefined,
}));
