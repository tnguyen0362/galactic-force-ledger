const mod = await import("file:///C:/Users/tnguy/.pi/agent/extensions/context-gc.ts");
const handlers = {}; mod.default({ on: (n, fn) => { handlers[n] = fn; } });
const pair = (i) => ([
  { role: "assistant", content: [{ type: "toolCall", id: "c" + i, name: "x", arguments: { code: "Z".repeat(8000) } }] },
  { role: "toolResult", toolCallId: "c" + i, toolName: "x", content: [{ type: "text", text: "Y".repeat(6000) }] },
]);
const body = []; for (let i = 0; i < 300; i += 1) body.push(...pair(i));
const ctx = { getContextUsage: () => ({ tokens: 950000, contextWindow: 1000000 }), compact: () => {} };
const first = await handlers.context({ messages: body }, ctx);
const grown = [...body, ...pair("new1")];
const second = await handlers.context({ messages: grown }, ctx);
const third = await handlers.context({ messages: grown }, ctx);
const a = JSON.stringify(first?.messages ?? body).length;
const b = JSON.stringify(second?.messages ?? grown).length;
const c = JSON.stringify(third?.messages ?? grown).length;
console.log(JSON.stringify({ firstMB: +(a/1e6).toFixed(2), secondGrewByNewOnlyMB: +(b/1e6).toFixed(2), thirdIdentical: b === c }));
