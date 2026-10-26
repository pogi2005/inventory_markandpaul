import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

function defaultSecretKey(): string | undefined {
  try {
    const keys = JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS") ?? "{}");
    return typeof keys.default === "string" ? keys.default : undefined;
  } catch {
    return undefined;
  }
}

Deno.serve(async (request) => {
  if (request.method !== "POST") return new Response("Method not allowed", { status: 405 });

  const callbackToken = Deno.env.get("XENDIT_WEBHOOK_TOKEN");
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || defaultSecretKey();
  if (!callbackToken || !supabaseUrl || !serviceRoleKey) {
    console.error("Xendit webhook is not configured");
    return new Response("Webhook not configured", { status: 500 });
  }
  if (request.headers.get("x-callback-token") !== callbackToken) {
    return new Response("Invalid callback token", { status: 401 });
  }

  let payload: Record<string, unknown>;
  try {
    payload = await request.json();
  } catch {
    return new Response("Invalid JSON", { status: 400 });
  }

  const externalId = payload.external_id;
  const status = payload.status;
  if (typeof externalId !== "string" || typeof status !== "string") {
    return new Response("Missing invoice fields", { status: 400 });
  }

  if (!["PAID", "SETTLED", "EXPIRED", "FAILED"].includes(status)) {
    return new Response("Event ignored", { status: 200 });
  }

  const paidAmount = Number(payload.paid_amount ?? payload.amount ?? 0);
  if (!Number.isFinite(paidAmount)) return new Response("Invalid paid amount", { status: 400 });

  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { error } = await admin.rpc("finish_xendit_payment", {
    p_payment_id: externalId,
    p_invoice_id: typeof payload.id === "string" ? payload.id : null,
    p_status: status,
    p_paid_amount: paidAmount,
    p_currency: typeof payload.currency === "string" ? payload.currency : "",
  });
  if (error) {
    console.error("Could not finalize Xendit payment", error);
    return new Response("Payment finalization failed", { status: 500 });
  }

  return new Response("OK", { status: 200 });
});
