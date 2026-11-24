const mod = await import("file:///C:/Users/tnguy/.pi/agent/extensions/context-gc.ts");
const handlers = {}; mod.default({ on: (n, fn) => { handlers[n] = fn; } });
const pair = (i) => ([
  { role: "assistant", content: [{ type: "toolCall", id: "c" + i, name: "x", arguments: { code: "Z".repeat(8000) } }] },
  { role: "toolResult", toolCallId: "c" + i, toolName: "x", content: [{ type: "text", text: "Y".repeat(6000) }] },
]);
const body = []; for (let i = 0; i < 300; i += 1) body.push(...pair(i));
const ctx = { getContextUsage: () => ({ tokens: 940000, contextWindow: 1000000 }), compact: () => {} };
const midLoop = await handlers.context({ messages: [...body, { role: "toolResult", toolCallId: "c299", content: [{ type: "text", text: "z" }] }] }, ctx);
const finalReply = await handlers.context({ messages: [...body, { role: "assistant", content: [{ type: "text", text: "done" }] }] }, ctx);
const out = finalReply?.messages ?? [];
console.log(JSON.stringify({ midLoopBlocked: midLoop === undefined, prunedOnFinalReply: out.length > 0, messagesAfter: out.length }));
