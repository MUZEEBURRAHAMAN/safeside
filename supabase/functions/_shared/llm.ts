/**
 * Provider-agnostic LLM client (OpenAI-compatible Chat Completions).
 *
 * The AI ingredient feature RE-WRITES vetted KB facts in plain language — it
 * never generates facts (docs/AI_INGREDIENT_EXPLANATION.md §2). This module is
 * only the transport; the bounded prompt and every guardrail live in
 * `kb/kb.ts` so they are unit-tested without a network.
 *
 * Config via env only (never bundled):
 *   LLM_BASE_URL  default "https://api.groq.com/openai/v1"
 *   LLM_API_KEY   required to enable rewrites; absent → caller returns raw KB
 *   LLM_MODEL     default "llama-3.3-70b-versatile"
 *
 * `LlmClient` is an interface so tests inject a fake and assert guardrails.
 */

export interface LlmMessage {
  // "assistant" supports multi-turn chat history (grounded /chat endpoint);
  // the ingredient rewrite only ever uses system + user.
  role: "system" | "user" | "assistant";
  content: string;
}

/** Per-call options. All optional so existing callers are unaffected. */
export interface LlmCompleteOptions {
  /** Hard cap on completion tokens (cost control; see BACKEND_SPEC §5). */
  maxTokens?: number;
}

export interface LlmClient {
  /** Return the assistant message content (expected to be a JSON object). */
  complete(
    messages: LlmMessage[],
    options?: LlmCompleteOptions,
  ): Promise<string>;
}

export const DEFAULT_LLM_BASE_URL = "https://api.groq.com/openai/v1";
export const DEFAULT_LLM_MODEL = "llama-3.3-70b-versatile";

export interface LlmEnv {
  LLM_BASE_URL?: string;
  LLM_API_KEY?: string;
  LLM_MODEL?: string;
}

/**
 * Build a real client from env, or `null` when no API key is set. A null
 * client is the graceful-degradation signal: the caller returns raw KB fields
 * verbatim (still sourced, still no fabrication) instead of failing.
 */
export function createLlmClient(
  env: LlmEnv,
  fetchImpl: typeof fetch = fetch,
): LlmClient | null {
  const apiKey = env.LLM_API_KEY?.trim();
  if (!apiKey) return null;

  const baseUrl = (env.LLM_BASE_URL?.trim() || DEFAULT_LLM_BASE_URL).replace(
    /\/+$/,
    "",
  );
  const model = env.LLM_MODEL?.trim() || DEFAULT_LLM_MODEL;

  return {
    async complete(
      messages: LlmMessage[],
      options?: LlmCompleteOptions,
    ): Promise<string> {
      const res = await fetchImpl(`${baseUrl}/chat/completions`, {
        method: "POST",
        headers: {
          "Authorization": `Bearer ${apiKey}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          model,
          messages,
          temperature: 0.2,
          response_format: { type: "json_object" },
          ...(options?.maxTokens ? { max_tokens: options.maxTokens } : {}),
        }),
      });
      if (!res.ok) {
        const detail = await res.text().catch(() => "");
        throw new Error(`LLM request failed: HTTP ${res.status} ${detail}`);
      }
      const body = await res.json() as {
        choices?: { message?: { content?: string } }[];
      };
      const content = body.choices?.[0]?.message?.content;
      if (typeof content !== "string" || content.trim() === "") {
        throw new Error("LLM returned an empty completion");
      }
      return content;
    },
  };
}
