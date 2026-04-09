// Molecule Checker — Gemini Vision analyze proxy
//
// Receives a base64-encoded photo of a ball-and-stick molecule model and
// forwards it to Gemini 2.0 Flash (Vision) with a domain-specific prompt.
// The Gemini API key is kept server-side as an Edge Function secret.
//
// Deploy:
//   supabase functions deploy analyze --no-verify-jwt=false
//   supabase secrets set GEMINI_API_KEY=<your-key>
//
// Invoke (from the browser):
//   const { data, error } = await supabase.functions.invoke('analyze', {
//     body: { image: <base64>, mimeType: 'image/jpeg' }
//   });

// deno-lint-ignore-file no-explicit-any

const GEMINI_MODEL = "gemini-2.5-flash";
const GEMINI_ENDPOINT =
  `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent`;

const CORS_HEADERS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const SYSTEM_PROMPT = `당신은 고등학교·대학 입문 수준의 화학 교육 전문가입니다.
볼-앤-스틱(Ball-and-Stick) 분자 모형 사진을 보고 아래 순서로 분석하세요.

1. 이미지에 볼-앤-스틱 분자 모형이 존재하는지 판단
2. CPK 색상 기준으로 각 원자 종류 식별
   - 검정/짙은 회색: C, 흰색: H, 빨강: O, 파랑: N,
     노랑: S, 주황: P, 연두: Cl, 갈색/어두운 빨강: Br
3. 각 원자의 결합 수 계산 후 원자가 규칙 위반 여부 판정
   (C:4, H:1, O:2, N:3, S:2 또는 6, P:3 또는 5, Cl/Br/F:1)
4. 분자 이름(IUPAC명 + 관용명) 식별
5. 주요 작용기 추출
6. 고리 구조에서 원자가 겹쳐 보이면 분자식과 고리 패턴(5각형/6각형)을
   함께 고려하고, 모호하면 confidence를 'medium'으로 설정

**반드시 JSON만 반환하세요.** 설명·Markdown 코드블록 금지.

응답 스키마:
{
  "is_valid": boolean | null,
  "molecule_name_kr": string,
  "molecule_name_en": string,
  "formula": string,
  "explanation": string,
  "functional_groups": string[],
  "confidence": "high" | "medium" | "low"
}

모형이 감지되지 않으면 is_valid: null, explanation에 "분자 모형이 보이지 않습니다" 반환.
원자가 규칙 위반이 있으면 is_valid: false + explanation에 구체적 원인.
구조는 유효하나 이름을 모르면 is_valid: true, molecule_name_kr: "미확인 분자 (구조 유효)".`;

interface AnalyzeRequest {
  image?: string;       // base64 without data: prefix
  mimeType?: string;    // e.g. "image/jpeg"
}

interface GeminiResponse {
  candidates?: Array<{
    content?: {
      parts?: Array<{ text?: string }>;
    };
  }>;
  promptFeedback?: any;
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
  });
}

function stripDataUrlPrefix(b64: string): string {
  const comma = b64.indexOf(",");
  if (b64.startsWith("data:") && comma !== -1) return b64.slice(comma + 1);
  return b64;
}

function parseGeminiJson(text: string): any {
  // Gemini sometimes wraps JSON in ```json ... ``` despite instructions.
  const fenced = text.match(/```(?:json)?\s*([\s\S]*?)```/);
  const raw = (fenced ? fenced[1] : text).trim();
  return JSON.parse(raw);
}

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS_HEADERS });
  }
  if (req.method !== "POST") {
    return json({ error: "method_not_allowed" }, 405);
  }

  const apiKey = Deno.env.get("GEMINI_API_KEY");
  if (!apiKey) {
    return json(
      { error: "config", message: "GEMINI_API_KEY secret is not set" },
      500,
    );
  }

  let body: AnalyzeRequest;
  try {
    body = await req.json();
  } catch {
    return json({ error: "invalid_json" }, 400);
  }

  const image = body.image ? stripDataUrlPrefix(body.image) : "";
  const mimeType = body.mimeType || "image/jpeg";
  if (!image) {
    return json({ error: "missing_image" }, 400);
  }
  // Rough base64 size guard: ~10MB binary ≈ 13.4MB base64.
  if (image.length > 14_000_000) {
    return json({ error: "image_too_large" }, 413);
  }

  const geminiPayload = {
    systemInstruction: { parts: [{ text: SYSTEM_PROMPT }] },
    contents: [
      {
        role: "user",
        parts: [
          { inlineData: { mimeType, data: image } },
          { text: "위 이미지를 분석해 스키마대로 JSON만 반환하세요." },
        ],
      },
    ],
    generationConfig: {
      temperature: 0.2,
      responseMimeType: "application/json",
    },
  };

  let geminiRes: Response;
  try {
    geminiRes = await fetch(`${GEMINI_ENDPOINT}?key=${apiKey}`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(geminiPayload),
    });
  } catch (err) {
    return json(
      { error: "upstream_unreachable", message: String(err) },
      502,
    );
  }

  if (!geminiRes.ok) {
    const errText = await geminiRes.text();
    return json(
      { error: "upstream_error", status: geminiRes.status, body: errText },
      502,
    );
  }

  const geminiJson = (await geminiRes.json()) as GeminiResponse;
  const text = geminiJson.candidates?.[0]?.content?.parts?.[0]?.text;
  if (!text) {
    return json(
      { error: "empty_response", raw: geminiJson },
      502,
    );
  }

  let parsed: any;
  try {
    parsed = parseGeminiJson(text);
  } catch (err) {
    return json(
      { error: "invalid_schema", raw: text, message: String(err) },
      502,
    );
  }

  // Schema sanity check — fill defaults rather than reject.
  const result = {
    is_valid: parsed.is_valid ?? null,
    molecule_name_kr: parsed.molecule_name_kr ?? "알 수 없음",
    molecule_name_en: parsed.molecule_name_en ?? "Unknown",
    formula: parsed.formula ?? "?",
    explanation: parsed.explanation ?? "",
    functional_groups: Array.isArray(parsed.functional_groups)
      ? parsed.functional_groups
      : [],
    confidence: parsed.confidence ?? "low",
  };

  return json(result, 200);
});
