const mod = await import("file:///C:/Users/tnguy/.pi/agent/extensions/context-gc.ts");
const handlers = {}; mod.default({ on: (n, fn) => { handlers[n] = fn; } });
const pair = (i) => ([
  { role: "assistant", content: [{ type: "toolCall", id: "c" + i, name: "x", arguments: { code: "Z".repeat(8000) } }] },
  { role: "toolResult", toolCallId: "c" + i, toolName: "x", content: [{ type: "text", text: "Y".repeat(6000) }] },
]);
const body = []; for (let i = 0; i < 300; i += 1) body.push(...pair(i));
const recent = Array.from({ length: 8 }, (_, i) => ({ role: "toolResult", toolCallId: "r" + i, content: [{ type: "text", text: "recent" }] }));
const messages = [...body, ...recent];
let compacts = 0;
const makeCtx = (tokens) => ({ getContextUsage: () => ({ tokens, contextWindow: 1000000 }), compact: () => { compacts += 1; } });
// stored size 950k: three pruned requests should now trigger compaction (previously unreachable)
for (let i = 0; i < 3; i += 1) await handlers.context({ messages }, makeCtx(950000));
const afterHigh = compacts;
// stored size 300k: no compaction, and no pruning either (below trigger)
for (let i = 0; i < 2; i += 1) await handlers.context({ messages }, makeCtx(300000));
console.log(JSON.stringify({ compactsAfter3High: afterHigh, compactsAfterLow: compacts }));
