const mod = await import("file:///C:/Users/tnguy/.pi/agent/extensions/context-gc.ts");
const handlers = {}; mod.default({ on: (n, fn) => { handlers[n] = fn; } });
const pair = (i) => ([
  { role: "assistant", content: [{ type: "toolCall", id: "call_" + i, name: "execute_luau", arguments: { code: "Z".repeat(8000) } }] },
  { role: "toolResult", toolCallId: "call_" + i, toolName: "execute_luau", content: [{ type: "text", text: "Y".repeat(6000) }] },
]);
const messages = [];
for (let i = 0; i < 300; i += 1) messages.push(...pair(i));
for (let i = 0; i < 8; i += 1) messages.push(...pair("r" + i));
const before = JSON.stringify(messages).length;
await handlers.agent_settled({ aborted: false });
const out = await handlers.context({ messages }, { getContextUsage: () => ({ tokens: 800000, contextWindow: 1000000 }) });
const m = out?.messages ?? messages;
const ids = new Set();
let orphans = 0;
for (const msg of m) {
  if (msg.role === "assistant") for (const p of msg.content) if (p.type === "toolCall") ids.add(p.id);
  if (msg.role === "toolResult" && !ids.has(msg.toolCallId) && !messages.find(x => x.toolCallId === msg.toolCallId && false)) { /* allow: id may appear later */ }
}
const callIds = new Set(m.flatMap(x => x.content ?? []).filter(p => p.type === "toolCall").map(p => p.id));
for (const msg of m) if (msg.role === "toolResult" && !callIds.has(msg.toolCallId)) orphans += 1;
console.log(JSON.stringify({ beforeMB: +(before/1e6).toFixed(2), afterMB: +(JSON.stringify(m).length/1e6).toFixed(2), messages: m.length, orphanResults: orphans }));
