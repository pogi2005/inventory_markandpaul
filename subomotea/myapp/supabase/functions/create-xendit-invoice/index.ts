import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function defaultKeyFrom(name: string): string | undefined {
  try {
    const keys = JSON.parse(Deno.env.get(name) ?? "{}");
    return typeof keys.default === "string" ? keys.default : undefined;
  } catch {
    return undefined;
  }
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (request.method !== "POST") return jsonResponse({ error: "Method not allowed" }, 405);

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ||
    defaultKeyFrom("SUPABASE_PUBLISHABLE_KEYS");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ||
    defaultKeyFrom("SUPABASE_SECRET_KEYS");
  const xenditSecret = Deno.env.get("XENDIT_SECRET_KEY");
  const authorization = request.headers.get("Authorization");
  const missing = [
    ...(!supabaseUrl ? ["SUPABASE_URL"] : []),
    ...(!anonKey ? ["SUPABASE_ANON_KEY or SUPABASE_PUBLISHABLE_KEYS"] : []),
    ...(!serviceRoleKey ? ["SUPABASE_SERVICE_ROLE_KEY or SUPABASE_SECRET_KEYS"] : []),
    ...(!xenditSecret ? ["XENDIT_SECRET_KEY"] : []),
  ];
  if (missing.length > 0) {
    console.error("Payment service configuration is missing values", missing);
    return jsonResponse({ error: "Payment service is not configured" }, 500);
  }
  if (!authorization) return jsonResponse({ error: "Sign-in required" }, 401);

  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authorization } },
  });
  const { data: userData, error: authError } = await userClient.auth.getUser();
  if (authError || !userData.user) return jsonResponse({ error: "Sign-in required" }, 401);

  let body: { items?: unknown };
  try {
    body = await request.json();
  } catch {
    return jsonResponse({ error: "Invalid request body" }, 400);
  }
  if (!Array.isArray(body.items) || body.items.length === 0 || body.items.length > 50) {
    return jsonResponse({ error: "Select between 1 and 50 items" }, 400);
  }

  const itemCounts = new Map<string, number>();
  for (const item of body.items) {
    if (!item || typeof item.product_id !== "string" ||
        !Number.isSafeInteger(item.quantity) || item.quantity < 1 || item.quantity > 10000) {
      return jsonResponse({ error: "Invalid product or quantity" }, 400);
    }
    itemCounts.set(item.product_id, (itemCounts.get(item.product_id) ?? 0) + item.quantity);
  }
  const items = [...itemCounts.entries()].map(([product_id, quantity]) => ({ product_id, quantity }));

  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const paymentId = `xnd_${crypto.randomUUID()}`;
  const mode = xenditSecret.startsWith("xnd_development_") ? "test" : "live";
  const { data: reservation, error: reserveError } = await admin.rpc("reserve_xendit_payment", {
    p_owner_id: userData.user.id,
    p_payment_id: paymentId,
    p_items: items,
    p_mode: mode,
  });
  if (reserveError) return jsonResponse({ error: reserveError.message }, 409);

  const reservedItems = reservation.items as Array<{
    product_id: string;
    product_name: string;
    unit_price: number;
    quantity: number;
  }>;
  const invoiceResponse = await fetch("https://api.xendit.co/v2/invoices", {
    method: "POST",
    headers: {
      Authorization: `Basic ${btoa(`${xenditSecret}:`)}`,
      "Content-Type": "application/json",
      "Idempotency-key": paymentId,
    },
    body: JSON.stringify({
      external_id: paymentId,
      amount: Number(reservation.amount),
      currency: "PHP",
      description: "Simple Inventory purchase",
      invoice_duration: 3600,
      items: reservedItems.map((item) => ({
        name: item.product_name,
        quantity: item.quantity,
        price: Number(item.unit_price),
      })),
    }),
  });

  const invoice = await invoiceResponse.json().catch(() => ({}));
  if (!invoiceResponse.ok || typeof invoice.invoice_url !== "string") {
    await admin.rpc("finish_xendit_payment", {
      p_payment_id: paymentId,
      p_invoice_id: null,
      p_status: "FAILED",
      p_paid_amount: 0,
      p_currency: "PHP",
    });
    console.error("Xendit invoice creation failed", invoice);
    return jsonResponse({ error: "Xendit could not create the invoice" }, 502);
  }

  const { error: saveInvoiceError } = await admin
    .from("payment_logs")
    .update({ xendit_invoice_id: invoice.id, invoice_url: invoice.invoice_url })
    .eq("owner_id", userData.user.id)
    .eq("id", paymentId)
    .eq("status", "pending");
  if (saveInvoiceError) console.error("Could not save Xendit invoice details", saveInvoiceError);

  return jsonResponse({
    payment_id: paymentId,
    invoice_url: invoice.invoice_url,
    amount: reservation.amount,
  });
});
