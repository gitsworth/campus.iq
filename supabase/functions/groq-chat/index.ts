// CampusIQ Groq proxy.
// Deploy with JWT verification enabled. Keep GROQ_API_KEY in Supabase secrets,
// never in Flutter or source control.

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  try {
    // Supabase Edge Function gateway verifies the caller's JWT (verify_jwt=true).
    const authHeader = req.headers.get("Authorization");
    if (!authHeader?.startsWith("Bearer ")) {
      return json({ error: "Authentication required" }, 401);
    }

    const body = await req.json();
    const system = body?.system;
    const messages = body?.messages;

    if (typeof system !== "string" || system.trim().length === 0 ||
        system.length > 24_000 || !Array.isArray(messages) ||
        messages.length === 0 || messages.length > 10) {
      return json({ error: "Invalid chatbot request" }, 400);
    }

    const safeMessages: Array<{ role: "user" | "assistant"; content: string }> = [];
    for (const item of messages) {
      if (!item || !["user", "assistant"].includes(item.role) ||
          typeof item.content !== "string" || item.content.length > 4_000) {
        return json({ error: "Invalid conversation message" }, 400);
      }
      safeMessages.push({ role: item.role, content: item.content });
    }

    const key = Deno.env.get("GROQ_API_KEY");
    if (!key) return json({ error: "Chat service is not configured" }, 503);

    const model = Deno.env.get("GROQ_MODEL") ?? "openai/gpt-oss-120b";
    const res = await fetch("https://api.groq.com/openai/v1/chat/completions", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${key}`,
      },
      body: JSON.stringify({
        model,
        temperature: 0.1,
        reasoning_effort: "low",
        max_completion_tokens: 2000,
        messages: [
          { role: "system", content: system },
          ...safeMessages,
        ],
      }),
    });

    const data = await res.json().catch(() => ({}));
    if (!res.ok) {
      // Do not expose upstream response details or secrets to the client.
      console.error("Groq request failed", res.status, data?.error?.code ?? "");
      return json({ error: "The AI service could not answer right now. Please try again." }, 502);
    }

    const reply = data?.choices?.[0]?.message?.content;
    if (typeof reply !== "string" || reply.trim().length === 0) {
      return json({ error: "The AI service returned an empty answer." }, 502);
    }
    return json({ reply });
  } catch (e) {
    console.error("groq-chat error", e);
    return json({ error: "The chatbot is temporarily unavailable." }, 500);
  }
});
