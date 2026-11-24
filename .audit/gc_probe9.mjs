const mod = await import("file:///C:/Users/tnguy/.pi/agent/extensions/context-gc.ts");
const handlers = {}; mod.default({ on: (n, fn) => { handlers[n] = fn; } });
const pair = (i) => ([
  { role: "assistant", content: [{ type: "toolCall", id: "c" + i, name: "x", arguments: { code: "Z".repeat(8000) } }] },
  { role: "toolResult", toolCallId: "c" + i, toolName: "x", content: [{ type: "text", text: "Y".repeat(6000) }] },
]);
const body = []; for (let i = 0; i < 300; i += 1) body.push(...pair(i));
const tail = [{ role: "toolResult", toolCallId: "live", toolName: "x", content: [{ type: "text", text: "LIVE" }] }];
const messages = [...body, ...Array.from({ length: 7 }, (_, i) => ({ role: "toolResult", toolCallId: "r" + i, content: [{ type: "text", text: "recent" }] })), ...tail];
const ctx = { getContextUsage: () => ({ tokens: 944000, contextWindow: 1000000 }), compact: () => {} };
const first = await handlers.context({ messages }, ctx);
const second = await handlers.context({ messages }, ctx);
const a = JSON.stringify(first?.messages ?? messages).length;
const b = JSON.stringify(second?.messages ?? messages).length;
const tailIntact = (first?.messages ?? messages).at(-1) === tail[0];
console.log(JSON.stringify({ firstPrunedMB: +(a/1e6).toFixed(2), secondSameMB: +(b/1e6).toFixed(2), stable: a === b, tailIntact }));
