const mod = await import("file:///C:/Users/tnguy/.pi/agent/extensions/context-gc.ts");
const handlers = {}; mod.default({ on: (n, fn) => { handlers[n] = fn; } });
const bigToolCall = (id) => ({ role: "assistant", content: [{ type: "toolCall", name: "mcp__Roblox_Studio__execute_luau", input: { code: "Z".repeat(8000) } }] });
const messages = [...Array.from({ length: 300 }, (_, i) => bigToolCall("t" + i)), ...Array.from({ length: 8 }, (_, i) => bigToolCall("r" + i))];
const chars = JSON.stringify(messages).length;
await handlers.agent_settled({ aborted: false });
const out = await handlers.context({ messages }, { getContextUsage: () => ({ tokens: 800000, contextWindow: 1000000 }) });
const after = JSON.stringify(out?.messages ?? messages).length;
console.log(JSON.stringify({ beforeMB: +(chars/1e6).toFixed(2), afterMB: +(after/1e6).toFixed(2), trackedCalls: (out?.messages ?? messages).filter(m => m.content?.some?.(p => p.type === "toolCall")).length }));
