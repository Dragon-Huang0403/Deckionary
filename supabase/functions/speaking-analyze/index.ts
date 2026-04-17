import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const OPENAI_API_KEY = Deno.env.get("OPENAI_API_KEY");

const SYSTEM_PROMPT = `You are an English speaking coach. Analyze the user's spoken or written English response to a given topic.

Your task:
1. Identify 5-7 misused words, unnatural phrases, or grammatical errors (fewer if the response is short or mostly correct).
2. For each issue, provide the original phrase, a more natural alternative, and a brief explanation.
3. Rewrite the entire response in natural, fluent English while preserving the speaker's intended meaning.
4. Provide a brief overall note (1-2 sentences) about the speaker's general level and one key area to improve.

Respond ONLY with valid JSON in this exact format (no markdown, no code fences):
{
  "transcript": "<the user's original text>",
  "corrections": [
    {
      "original": "<misused word or phrase>",
      "natural": "<natural alternative>",
      "explanation": "<brief explanation>"
    }
  ],
  "natural_version": "<full rewritten response>",
  "overall_note": "<brief overall assessment>"
}

If the user's response is already very natural with few issues, still provide at least 1-2 suggestions for improvement and note that the response was good overall.`;

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

async function analyzeWithAudio(
  audioBytes: Uint8Array,
  topic: string
): Promise<Record<string, unknown>> {
  const base64Audio = btoa(
    Array.from(audioBytes)
      .map((b) => String.fromCharCode(b))
      .join("")
  );

  const response = await fetch("https://api.openai.com/v1/chat/completions", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${OPENAI_API_KEY}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model: "gpt-4o-audio-preview",
      messages: [
        { role: "system", content: SYSTEM_PROMPT },
        {
          role: "user",
          content: [
            {
              type: "input_audio",
              input_audio: { data: base64Audio, format: "m4a" },
            },
            {
              type: "text",
              text: `The topic was: "${topic}". Please analyze the spoken response above.`,
            },
          ],
        },
      ],
      modalities: ["text"],
      temperature: 0.3,
    }),
  });

  if (!response.ok) {
    const errorBody = await response.text();
    throw new Error(`OpenAI API error (${response.status}): ${errorBody}`);
  }

  const data = await response.json();
  const content = data.choices?.[0]?.message?.content;
  if (!content) {
    throw new Error("No content in OpenAI response");
  }

  return parseJsonContent(content);
}

function parseJsonContent(content: string): Record<string, unknown> {
  // Strip markdown code fences that GPT-4o occasionally wraps around JSON
  const cleaned = content
    .trim()
    .replace(/^```json?\n?/, "")
    .replace(/\n?```$/, "");
  return JSON.parse(cleaned);
}

async function analyzeWithText(
  text: string,
  topic: string
): Promise<Record<string, unknown>> {
  const response = await fetch("https://api.openai.com/v1/chat/completions", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${OPENAI_API_KEY}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model: "gpt-4o",
      messages: [
        { role: "system", content: SYSTEM_PROMPT },
        {
          role: "user",
          content: `The topic was: "${topic}".\n\nMy response:\n${text}`,
        },
      ],
      response_format: { type: "json_object" },
      temperature: 0.3,
    }),
  });

  if (!response.ok) {
    const errorBody = await response.text();
    throw new Error(`OpenAI API error (${response.status}): ${errorBody}`);
  }

  const data = await response.json();
  const content = data.choices?.[0]?.message?.content;
  if (!content) {
    throw new Error("No content in OpenAI response");
  }

  return parseJsonContent(content);
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
    let result: Record<string, unknown>;

    if (contentType.includes("multipart/form-data")) {
      // Audio input via multipart form
      const formData = await req.formData();
      const audioFile = formData.get("audio");
      const topic = formData.get("topic");

      if (!audioFile || !(audioFile instanceof File)) {
        return new Response(
          JSON.stringify({ error: "Missing 'audio' file in form data" }),
          {
            status: 400,
            headers: { ...corsHeaders(), "Content-Type": "application/json" },
          }
        );
      }

      if (!topic || typeof topic !== "string") {
        return new Response(
          JSON.stringify({ error: "Missing 'topic' in form data" }),
          {
            status: 400,
            headers: { ...corsHeaders(), "Content-Type": "application/json" },
          }
        );
      }

      const audioBytes = new Uint8Array(await audioFile.arrayBuffer());
      result = await analyzeWithAudio(audioBytes, topic);
    } else if (contentType.includes("application/json")) {
      // Text input via JSON
      const body = await req.json();
      const { text, topic } = body;

      if (!text || typeof text !== "string") {
        return new Response(
          JSON.stringify({ error: "Missing 'text' in request body" }),
          {
            status: 400,
            headers: { ...corsHeaders(), "Content-Type": "application/json" },
          }
        );
      }

      if (!topic || typeof topic !== "string") {
        return new Response(
          JSON.stringify({ error: "Missing 'topic' in request body" }),
          {
            status: 400,
            headers: { ...corsHeaders(), "Content-Type": "application/json" },
          }
        );
      }

      result = await analyzeWithText(text, topic);
    } else {
      return new Response(
        JSON.stringify({
          error:
            "Unsupported content type. Use multipart/form-data or application/json",
        }),
        {
          status: 400,
          headers: { ...corsHeaders(), "Content-Type": "application/json" },
        }
      );
    }

    return new Response(JSON.stringify(result), {
      status: 200,
      headers: { ...corsHeaders(), "Content-Type": "application/json" },
    });
  } catch (err) {
    const message = err instanceof Error ? err.message : "Internal server error";
    console.error("speaking-analyze error:", err);
    return new Response(JSON.stringify({ error: message }), {
      status: 500,
      headers: { ...corsHeaders(), "Content-Type": "application/json" },
    });
  }
});
