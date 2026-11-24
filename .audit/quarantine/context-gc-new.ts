import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

// Request-only projection: original session entries remain available. Never touch user or assistant
// messages, error results, or recent results. This is not a token-budget guarantee.
export default function contextGc(pi: ExtensionAPI) {
 pi.on("context", async (event, ctx) => {
  const messages = event.messages as any[];
  const results = messages.filter(m => m.role === "toolResult");
  const protectedResults = new Set(results.slice(-10));
  const usage = ctx.getContextUsage()?.tokens;
  const tight = typeof usage === "number" && usage >= 600000;
  const rewritten = messages.map(m => {
   if (m.role !== "toolResult" || m.isError || protectedResults.has(m) || !Array.isArray(m.content)) return m;
   let changed = false;
   const content = m.content.map((part: any) => {
    if (part.type === "image" && m.toolName === "mcp__Roblox_Studio__screen_capture") {
     changed = true;
     return { type: "text", text: "[Older Studio screenshot omitted from this request; original remains in session history.]" };
    }
    if (part.type === "text" && typeof part.text === "string" && part.text.length > (tight ? 8000 : 16000) && ["read", "mcp__Roblox_Studio__script_read"].includes(m.toolName)) {
     changed = true;
     return { type: "text", text: part.text.slice(0, 4000) + "\n[Middle omitted from request; reread the source for full context.]\n" + part.text.slice(-2000) };
    }
    return part;
   });
   return changed ? { ...m, content } : m;
  });
  return { messages: rewritten as typeof event.messages };
 });
}
