/**
 * GET /product/:id/ingredients — pure handler logic (the AI feature).
 *
 * Implements docs/AI_INGREDIENT_EXPLANATION.md: retrieval, not generation.
 *   1. Collect the product's ingredient tokens + additive tags.
 *   2. Resolve each against the Ingredient KB (by id, then by synonym).
 *   3. KB hit  → serve the cached rewrite, or produce one (bounded LLM prompt,
 *      guarded), then cache it by (ingredient_id, kb_version, locale).
 *   4. KB MISS → the "no vetted info" limited state. NEVER call the LLM on an
 *      unknown ingredient; never free-style facts.
 *
 * All guardrails (risk-consistency, no-fabrication, banned words, graceful
 * degradation when the LLM key is missing) live in _shared/kb/kb.ts and run
 * offline in the test suite. This file is I/O wiring + ordering only.
 *
 * Deployed function name `ingredients`; documented client path
 * GET /product/:id/ingredients (see supabase/README.md). Returns
 * { ingredients: Ingredient[] } — each element decodes into Models.swift
 * `Ingredient`.
 */

import type { LlmClient } from "../_shared/llm.ts";
import {
  buildKbIndex,
  DEFAULT_LOCALE,
  explainIngredient,
  type IngredientOut,
  type KbEntry,
  toIngredientId,
  unknownIngredient,
} from "../_shared/kb/kb.ts";

export const CORS_HEADERS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, OPTIONS",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
  });
}

/** Bound per-request work (and AI cost) to a sane number of ingredients. */
export const MAX_INGREDIENTS = 40;

export interface ProductIngredientsRow {
  additivesTags: string[];
  ingredientsText: string | null;
}

export interface Deps {
  getProduct(id: string): Promise<ProductIngredientsRow | null>;
  getKb(): Promise<KbEntry[]>;
  getCached(
    ingredientId: string,
    kbVersion: string,
    locale: string,
  ): Promise<IngredientOut | null>;
  saveCached(
    ingredientId: string,
    kbVersion: string,
    locale: string,
    explanation: IngredientOut,
  ): Promise<void>;
  /** null when LLM_API_KEY is unset → raw KB fields are served verbatim. */
  llm: LlmClient | null;
  now(): number;
}

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/**
 * Product id from the path. Supports both the deployed shape
 * (/ingredients/:id) and the documented client path
 * (/product/:id/ingredients), plus an ?id= / ?product_id= query fallback.
 */
export function extractProductId(url: string): string | null {
  const u = new URL(url);
  const q = u.searchParams.get("id") ?? u.searchParams.get("product_id");
  if (q) return q;

  const segments = u.pathname.split("/").filter((s) => s !== "");
  const ingIdx = segments.lastIndexOf("ingredients");
  if (ingIdx > 0 && ingIdx === segments.length - 1) {
    return segments[ingIdx - 1]; // /product/:id/ingredients
  }
  const last = segments[segments.length - 1];
  if (!last || last === "ingredients") return null;
  return last; // /ingredients/:id
}

/** Split a comma/semicolon ingredients list into clean display tokens. */
export function parseIngredientTokens(text: string | null): string[] {
  if (!text) return [];
  const out: string[] = [];
  const seen = new Set<string>();
  for (const part of text.split(/[,;]+/)) {
    const token = part
      .replace(/\([^)]*\)/g, " ")
      .replace(/\d+([.,]\d+)?\s*%/g, " ")
      .replace(/\s+/g, " ")
      .trim()
      .replace(/^[^a-z0-9]+|[^a-z0-9]+$/gi, "")
      .trim();
    if (token.length < 2 || !/[a-z]/i.test(token)) continue;
    const key = token.toLowerCase();
    if (seen.has(key)) continue;
    seen.add(key);
    out.push(token);
  }
  return out;
}

interface Candidate {
  display: string; // what the user sees as the ingredient name
  entry: KbEntry | null; // resolved KB entry, or null (unknown)
}

/**
 * Build the ordered, de-duplicated candidate list: ingredient tokens first
 * (label order preserved), then any additive tags not already covered.
 */
export function buildCandidates(
  row: ProductIngredientsRow,
  kb: KbEntry[],
): Candidate[] {
  const { byId, byName } = buildKbIndex(kb);
  const candidates: Candidate[] = [];
  const emitted = new Set<string>(); // KB id (resolved) or display key (unknown)

  const push = (display: string, entry: KbEntry | null) => {
    const key = entry ? entry.id.toLowerCase() : `?${display.toLowerCase()}`;
    if (emitted.has(key)) return;
    emitted.add(key);
    candidates.push({ display, entry });
  };

  for (const token of parseIngredientTokens(row.ingredientsText)) {
    const entry = byId.get(toIngredientId(token)) ??
      byName.get(token.toLowerCase()) ?? null;
    push(entry ? (entry.names[0] ?? token) : token, entry);
  }

  for (const tag of row.additivesTags) {
    const entry = byId.get(tag.toLowerCase()) ?? null;
    const display = entry
      ? (entry.names[0] ?? tag)
      : tag.replace(/^en:/i, "").toUpperCase();
    push(display, entry);
  }

  return candidates.slice(0, MAX_INGREDIENTS);
}

export async function handleIngredients(
  req: Request,
  deps: Deps,
): Promise<Response> {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: CORS_HEADERS });
  }
  if (req.method !== "GET") {
    return json({ error: "method_not_allowed" }, 405);
  }
  if (!req.headers.get("Authorization")) {
    return json({ error: "unauthorized" }, 401);
  }

  const productId = extractProductId(req.url);
  if (!productId || !UUID_RE.test(productId)) {
    return json(
      { error: "invalid_product_id", detail: "Product id must be a UUID." },
      400,
    );
  }

  const row = await deps.getProduct(productId);
  if (row === null) {
    return json({ error: "not_found" }, 404);
  }

  const kb = await deps.getKb();
  const candidates = buildCandidates(row, kb);

  const ingredients: IngredientOut[] = [];
  for (const { display, entry } of candidates) {
    if (entry === null) {
      // KB MISS — never call the LLM, never fabricate.
      ingredients.push(unknownIngredient(display));
      continue;
    }

    const cached = await deps.getCached(
      entry.id,
      entry.kb_version,
      DEFAULT_LOCALE,
    );
    if (cached) {
      ingredients.push(cached);
      continue;
    }

    const explanation = await explainIngredient(entry, deps.llm);
    await deps.saveCached(
      entry.id,
      entry.kb_version,
      DEFAULT_LOCALE,
      explanation,
    );
    ingredients.push(explanation);
  }

  return json({ ingredients });
}
