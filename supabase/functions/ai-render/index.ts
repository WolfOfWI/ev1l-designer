// Supabase Edge Function: ai-render
// Proxies Ev1l Designer's AI Render requests to Anthropic so the API key never reaches the browser.
//
// Deploy:
//   supabase functions new ai-render            (then replace index.ts with this file)
//   supabase secrets set ANTHROPIC_API_KEY=sk-ant-...
//   supabase secrets set ALLOWED_ORIGIN=https://your-app-domain.com
//   supabase functions deploy ai-render
// Then paste https://<project>.supabase.co/functions/v1/ai-render into AI Render -> "AI service".
//
// By default Supabase requires a valid JWT (logged-in user or anon key) to call the function.
// To require signed-in users, keep JWT verification on and store the user's access token in
// localStorage 'ev1l_ai_token' after login (the app sends it as a Bearer token).

const ANTHROPIC_URL = "https://api.anthropic.com/v1/messages";
const ALLOWED_MODELS = new Set(["claude-sonnet-4-20250514", "claude-haiku-4-5-20251001"]);
const MAX_TOKENS_CAP = 2000;
const MAX_BODY_BYTES = 8 * 1024 * 1024; // plan images are sent as base64

function cors(origin: string | null) {
  const allowed = Deno.env.get("ALLOWED_ORIGIN") ?? "*";
  return {
    "Access-Control-Allow-Origin": allowed === "*" ? "*" : (origin === allowed ? allowed : allowed),
    "Access-Control-Allow-Headers": "authorization, content-type, apikey, x-client-info",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
  };
}

Deno.serve(async (req) => {
  const headers = cors(req.headers.get("origin"));
  if (req.method === "OPTIONS") return new Response("ok", { headers });
  if (req.method !== "POST") return new Response("Method not allowed", { status: 405, headers });

  const key = Deno.env.get("ANTHROPIC_API_KEY");
  if (!key) return new Response(JSON.stringify({ error: { message: "Server is missing ANTHROPIC_API_KEY" } }), { status: 500, headers: { ...headers, "Content-Type": "application/json" } });

  const raw = await req.text();
  if (raw.length > MAX_BODY_BYTES) return new Response(JSON.stringify({ error: { message: "Request too large" } }), { status: 413, headers: { ...headers, "Content-Type": "application/json" } });

  let body: any;
  try { body = JSON.parse(raw); } catch { return new Response(JSON.stringify({ error: { message: "Invalid JSON" } }), { status: 400, headers: { ...headers, "Content-Type": "application/json" } }); }

  // Only allow the shape the app sends -- prevents the endpoint being used as an open Anthropic relay.
  if (!ALLOWED_MODELS.has(body.model)) body.model = "claude-sonnet-4-20250514";
  body.max_tokens = Math.min(Number(body.max_tokens) || 1000, MAX_TOKENS_CAP);
  const clean = { model: body.model, max_tokens: body.max_tokens, system: body.system, messages: body.messages };

  const r = await fetch(ANTHROPIC_URL, {
    method: "POST",
    headers: { "content-type": "application/json", "x-api-key": key, "anthropic-version": "2023-06-01" },
    body: JSON.stringify(clean),
  });
  return new Response(await r.text(), { status: r.status, headers: { ...headers, "Content-Type": "application/json" } });
});
