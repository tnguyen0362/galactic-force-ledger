const mod = await import("file:///C:/Users/tnguy/.pi/agent/extensions/context-gc.ts");
let handler;
mod.default({ on: (_n, fn) => { handler = fn; } });
const tool = (id, toolName, text) => ({ role: "toolResult", toolName, toolCallId: id, content: [{ type: "text", text }] });
const asst = (text, thinking) => ({ role: "assistant", content: [{ type: "thinking", thinking }, { type: "text", text }, { type: "toolCall", name: "x", input: {} }] });
const user = { role: "user", content: [{ type: "text", text: "user words must survive ".repeat(200) }] };
const messages = [
  asst("A".repeat(9000), "T".repeat(5000)),
  tool("l1", "mcp__Roblox_Studio__execute_luau", "E".repeat(6000)),
  tool("l2", "read", "R".repeat(3000)),
  user,
  ...Array.from({ length: 8 }, (_, i) => tool("r" + i, "bash", "recent".repeat(50))),
];
const out = await handler({ messages }, { getContextUsage: () => ({ tokens: 700000 }) });
const m = out?.messages ?? messages;
const before = JSON.stringify(messages).length, after = JSON.stringify(m).length;
console.log(JSON.stringify({
  assistantTextLen: m[0].content[1].text.length,
  assistantThinkingLen: m[0].content[0].thinking.length,
  toolCallKept: m[0].content[2].type,
  executeLuauLen: m[1].content[0].text.length,
  readLen: m[2].content[0].text.length,
  userUntouched: m[3] === user,
  bytesBefore: before, bytesAfter: after, reductionPct: Math.round((1 - after / before) * 100),
}));
