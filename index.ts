// TUTOR DESK v7 — Paddle Billing checkout. Prices are resolved server-side only.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const origin = Deno.env.get("APP_ORIGIN") ?? "null";
const cors = {
  "Access-Control-Allow-Origin": origin,
  "Access-Control-Allow-Headers": "authorization, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Vary": "Origin",
  "Content-Type": "application/json",
};
const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: cors });
const isHttpsUrl = (value: string | undefined): value is string => {
  if (!value) return false;
  try { return new URL(value).protocol === "https:"; } catch { return false; }
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  if (req.headers.get("origin") && req.headers.get("origin") !== origin) return json({ error: "origin_not_allowed" }, 403);

  const authHeader = req.headers.get("Authorization");
  if (!authHeader?.startsWith("Bearer ")) return json({ error: "authentication_required" }, 401);
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  if (!supabaseUrl || !anonKey) return json({ error: "server_not_configured" }, 500);
  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: { user }, error: userError } = await userClient.auth.getUser();
  if (userError || !user) return json({ error: "invalid_session" }, 401);

  let body: { plan_id?: string };
  try { body = await req.json(); } catch { return json({ error: "invalid_json" }, 400); }
  const planId = body.plan_id;
  if (planId !== "pro_monthly" && planId !== "pro_yearly") return json({ error: "invalid_plan" }, 400);

  const apiKey = Deno.env.get("PADDLE_API_KEY");
  const env = Deno.env.get("PADDLE_ENVIRONMENT") ?? "sandbox";
  const priceId = planId === "pro_monthly"
    ? Deno.env.get("PADDLE_PRICE_ID_PRO_MONTHLY")
    : Deno.env.get("PADDLE_PRICE_ID_PRO_YEARLY");
  const checkoutBase = Deno.env.get("PADDLE_CHECKOUT_URL") ?? origin;
  if (!apiKey || !priceId || !isHttpsUrl(checkoutBase) || !["sandbox", "production"].includes(env)) {
    return json({ error: "billing_not_configured", message: "Paddle не настроен на сервере. Используется безопасный режим без списания средств." }, 503);
  }

  const apiBase = env === "production" ? "https://api.paddle.com" : "https://sandbox-api.paddle.com";
  try {
    const response = await fetch(`${apiBase}/transactions`, {
      method: "POST",
      headers: { "Authorization": `Bearer ${apiKey}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        items: [{ price_id: priceId, quantity: 1 }],
        collection_mode: "automatic",
        custom_data: { tutor_user_id: user.id, tutor_plan_id: planId },
        checkout: { url: checkoutBase },
      }),
    });
    const result = await response.json().catch(() => ({}));
    const checkoutUrl = result?.data?.checkout?.url;
    if (!response.ok || typeof checkoutUrl !== "string" || !isHttpsUrl(checkoutUrl)) {
      // Avoid returning provider response details to the browser.
      return json({ error: "checkout_unavailable", message: "Paddle не смог создать ссылку оплаты. Проверьте товар, цену и домен Checkout." }, 502);
    }
    return json({ url: checkoutUrl });
  } catch {
    return json({ error: "billing_provider_unreachable" }, 502);
  }
});
