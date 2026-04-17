import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const OPENAI_API_KEY = Deno.env.get("OPENAI_API_KEY");

function corsHeaders(): Record<string, string> {
  return {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers":
      "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
  };
}

async function verifyAuth(
  authHeader: string | null
): Promise<{ userId: string } | Response> {
  if (!authHeader) {
    return new Response(JSON.stringify({ error: "Missing authorization header" }), {
      status: 401,
      headers: { ...corsHeaders(), "Content-Type": "application/json" },
    });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
  const supabase = createClient(supabaseUrl, supabaseAnonKey, {
    global: { headers: { Authorization: authHeader } },
  });

  const {
    data: { user },
    error,
  } = await supabase.auth.getUser();

  if (error || !user) {
    return new Response(JSON.stringify({ error: "Invalid or expired token" }), {
      status: 401,
      headers: { ...corsHeaders(), "Content-Type": "application/json" },
    });
  }

  return { userId: user.id };
}

function getServiceRoleClient() {
  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  return createClient(supabaseUrl, serviceRoleKey);
}

async function hashText(text: string): Promise<string> {
  const encoder = new TextEncoder();
  const data = encoder.encode(text);
  const hashBuffer = await crypto.subtle.digest("SHA-256", data);
  const hashArray = Array.from(new Uint8Array(hashBuffer));
  return hashArray.map((b) => b.toString(16).padStart(2, "0")).join("");
}

async function getCachedAudio(
  textHash: string
): Promise<Uint8Array | null> {
  const supabase = getServiceRoleClient();

  const { data, error } = await supabase
    .from("speaking_audio_cache")
    .select("audio_data")
    .eq("text_hash", textHash)
    .single();

  if (error || !data) {
    return null;
  }

  // Supabase returns BYTEA as a hex-escaped string (e.g., "\\x4f47...")
  // Decode it back to bytes
  const hex = data.audio_data as string;
  if (hex.startsWith("\\x")) {
    const cleanHex = hex.slice(2);
    const bytes = new Uint8Array(cleanHex.length / 2);
    for (let i = 0; i < cleanHex.length; i += 2) {
      bytes[i / 2] = parseInt(cleanHex.substring(i, i + 2), 16);
    }
    return bytes;
  }

  // If it's already base64-encoded (depends on Supabase version/config)
  const binary = atob(data.audio_data as string);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes;
}

async function cacheAudio(
  textHash: string,
  audioBytes: Uint8Array
): Promise<void> {
  const supabase = getServiceRoleClient();

  // Convert bytes to hex string for BYTEA storage
  const hex =
    "\\x" +
    Array.from(audioBytes)
      .map((b) => b.toString(16).padStart(2, "0"))
      .join("");

  const { error } = await supabase.from("speaking_audio_cache").upsert({
    text_hash: textHash,
    audio_data: hex,
  });

  if (error) {
    console.error("Failed to cache audio:", error);
  }
}

async function generateTTS(text: string): Promise<Uint8Array> {
  const response = await fetch("https://api.openai.com/v1/audio/speech", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${OPENAI_API_KEY}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model: "tts-1",
      voice: "nova",
      input: text,
      response_format: "mp3",
    }),
  });

  if (!response.ok) {
    const errorBody = await response.text();
    throw new Error(`OpenAI TTS API error (${response.status}): ${errorBody}`);
  }

  const arrayBuffer = await response.arrayBuffer();
  return new Uint8Array(arrayBuffer);
}

Deno.serve(async (req: Request) => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders() });
  }

  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405,
      headers: { ...corsHeaders(), "Content-Type": "application/json" },
    });
  }

  try {
    // Verify authentication
    const authResult = await verifyAuth(req.headers.get("authorization"));
    if (authResult instanceof Response) {
      return authResult;
    }

    if (!OPENAI_API_KEY) {
      return new Response(
        JSON.stringify({ error: "OpenAI API key not configured" }),
        {
          status: 500,
          headers: { ...corsHeaders(), "Content-Type": "application/json" },
        }
      );
    }

    const contentType = req.headers.get("content-type") ?? "";
    if (!contentType.includes("application/json")) {
      return new Response(
        JSON.stringify({ error: "Content-Type must be application/json" }),
        {
          status: 400,
          headers: { ...corsHeaders(), "Content-Type": "application/json" },
        }
      );
    }

    const body = await req.json();
    const { text } = body;

    if (!text || typeof text !== "string") {
      return new Response(
        JSON.stringify({ error: "Missing 'text' in request body" }),
        {
          status: 400,
          headers: { ...corsHeaders(), "Content-Type": "application/json" },
        }
      );
    }

    // Check cache
    const textHash = await hashText(text);
    const cachedAudio = await getCachedAudio(textHash);

    if (cachedAudio) {
      return new Response(cachedAudio, {
        status: 200,
        headers: {
          ...corsHeaders(),
          "Content-Type": "audio/mpeg",
          "X-Cache": "hit",
        },
      });
    }

    // Generate TTS and cache
    const audioBytes = await generateTTS(text);
    await cacheAudio(textHash, audioBytes);

    return new Response(audioBytes, {
      status: 200,
      headers: {
        ...corsHeaders(),
        "Content-Type": "audio/mpeg",
        "X-Cache": "miss",
      },
    });
  } catch (err) {
    const message = err instanceof Error ? err.message : "Internal server error";
    console.error("speaking-tts error:", err);
    return new Response(JSON.stringify({ error: message }), {
      status: 500,
      headers: { ...corsHeaders(), "Content-Type": "application/json" },
    });
  }
});
