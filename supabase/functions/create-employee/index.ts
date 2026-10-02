import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Content-Type": "application/json",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: corsHeaders,
  });
}

function envKey(jsonName: string, legacyName: string) {
  const jsonValue = Deno.env.get(jsonName);
  if (jsonValue) {
    try {
      const parsed = JSON.parse(jsonValue);
      if (typeof parsed?.default === "string" && parsed.default.length > 0) {
        return parsed.default as string;
      }
    } catch {
      // Fall back to the legacy environment variable below.
    }
  }

  const legacy = Deno.env.get(legacyName);
  if (!legacy) {
    throw new Error(`Missing ${jsonName} / ${legacyName}`);
  }
  return legacy;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader?.startsWith("Bearer ")) {
      return json({ error: "Authentication required" }, 401);
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    if (!supabaseUrl) throw new Error("SUPABASE_URL is unavailable");

    const publishableKey = envKey(
      "SUPABASE_PUBLISHABLE_KEYS",
      "SUPABASE_ANON_KEY",
    );
    const secretKey = envKey(
      "SUPABASE_SECRET_KEYS",
      "SUPABASE_SERVICE_ROLE_KEY",
    );

    const userClient = createClient(supabaseUrl, publishableKey, {
      global: { headers: { Authorization: authHeader } },
      auth: { persistSession: false },
    });

    const token = authHeader.slice("Bearer ".length);
    const {
      data: { user: caller },
      error: callerError,
    } = await userClient.auth.getUser(token);

    if (callerError || !caller) {
      return json({ error: "Invalid session" }, 401);
    }

    const { data: callerProfile, error: profileError } = await userClient
      .from("profiles")
      .select("status, roles(code)")
      .eq("id", caller.id)
      .single();

    if (profileError || !callerProfile) {
      return json({ error: "Active administrator profile required" }, 403);
    }

    const roleRelation = callerProfile.roles as
      | { code?: string }
      | { code?: string }[]
      | null;

    const callerRole = Array.isArray(roleRelation)
      ? roleRelation[0]?.code
      : roleRelation?.code;

    if (callerProfile.status !== "ACTIVE" || callerRole !== "ADMIN") {
      return json({ error: "Administrator permission required" }, 403);
    }

    const body = await req.json();
    const email = String(body.email ?? "").trim().toLowerCase();
    const password = String(body.password ?? "");
    const displayName = String(body.display_name ?? "").trim();
    const roleCode = String(body.role_code ?? "CASHIER")
      .trim()
      .toUpperCase();

    if (!email || !email.includes("@")) {
      return json({ error: "A valid email is required" }, 400);
    }

    if (password.length < 8) {
      return json(
        { error: "Temporary password must contain at least 8 characters" },
        400,
      );
    }

    if (!displayName) {
      return json({ error: "Display name is required" }, 400);
    }

    if (!["ADMIN", "MANAGER", "CASHIER"].includes(roleCode)) {
      return json({ error: "Invalid role" }, 400);
    }

    const adminClient = createClient(supabaseUrl, secretKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const { data: role, error: roleError } = await adminClient
      .from("roles")
      .select("id")
      .eq("code", roleCode)
      .single();

    if (roleError || !role) {
      return json({ error: "Requested role is unavailable" }, 400);
    }

    const { data: created, error: createError } =
      await adminClient.auth.admin.createUser({
        email,
        password,
        email_confirm: true,
        user_metadata: { display_name: displayName },
      });

    if (createError || !created.user) {
      return json(
        { error: createError?.message ?? "Unable to create employee" },
        400,
      );
    }

    const { error: updateError } = await adminClient
      .from("profiles")
      .update({
        email,
        display_name: displayName,
        role_id: role.id,
        status: "ACTIVE",
      })
      .eq("id", created.user.id);

    if (updateError) {
      await adminClient.auth.admin.deleteUser(created.user.id);
      return json({ error: updateError.message }, 400);
    }

    return json({
      id: created.user.id,
      email: created.user.email,
      display_name: displayName,
      role_code: roleCode,
      status: "ACTIVE",
    }, 201);
  } catch (error) {
    return json({
      error: error instanceof Error ? error.message : "Unexpected error",
    }, 500);
  }
});
