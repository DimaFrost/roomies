// Creates a pre-confirmed "device account" so the app works without an email
// signup flow: the app generates credentials on first launch, calls this
// function, then signs in with them. Deploy with verify_jwt disabled.
import { createClient } from "npm:@supabase/supabase-js@2";

const DEVICE_EMAIL_RE = /^device-[a-z0-9-]{8,64}@device\.roomies\.app$/;

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return new Response("method not allowed", { status: 405 });
  }

  let email: unknown, password: unknown;
  try {
    ({ email, password } = await req.json());
  } catch {
    return new Response(JSON.stringify({ error: "invalid json" }), { status: 400 });
  }

  if (typeof email !== "string" || !DEVICE_EMAIL_RE.test(email)) {
    return new Response(JSON.stringify({ error: "invalid device email" }), { status: 400 });
  }
  if (typeof password !== "string" || password.length < 32 || password.length > 128) {
    return new Response(JSON.stringify({ error: "invalid password" }), { status: 400 });
  }

  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
  );

  const { error } = await admin.auth.admin.createUser({
    email,
    password,
    email_confirm: true,
  });

  if (error && !error.message.includes("already been registered")) {
    return new Response(JSON.stringify({ error: error.message }), { status: 400 });
  }

  return new Response(JSON.stringify({ ok: true }), {
    headers: { "content-type": "application/json" },
  });
});
