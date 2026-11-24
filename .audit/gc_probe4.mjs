const mod = await import("file:///C:/Users/tnguy/.pi/agent/extensions/context-gc.ts");
let handler; mod.default({ on: (_n, fn) => { handler = fn; } });
// 2000 old messages of 3000 chars + a recent tail, mimicking this session's shape
const old = Array.from({ length: 2000 }, (_, i) => ({ role: "assistant", content: [{ type: "text", text: "X".repeat(3000) }] }));
const toolOld = Array.from({ length: 500 }, (_, i) => ({ role: "toolResult", toolName: "bash", toolCallId: "t" + i, content: [{ type: "text", text: "Y".repeat(4000) }] }));
const tail = Array.from({ length: 8 }, (_, i) => ({ role: "toolResult", toolName: "bash", toolCallId: "r" + i, content: [{ type: "text", text: "recent" }] }));
const user = { role: "user", content: [{ type: "text", text: "owner words" }] };
const messages = [...old, user, ...toolOld, ...tail];
const chars = JSON.stringify(messages).length;
let compacts = 0;
const ctx = { getContextUsage: () => ({ tokens: 900000 }), compact: () => { compacts += 1; } };
const out = await handler({ messages }, ctx);
const m = out?.messages ?? messages;
const remainChars = JSON.stringify(m).length;
const userIntact = m[2000] === user;
console.log(JSON.stringify({ beforeMB: +(chars/1e6).toFixed(2), afterMB: +(remainChars/1e6).toFixed(2), pctCut: Math.round((1-remainChars/chars)*100), userIntact, compacts }));
