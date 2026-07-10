/**
 * POST /product/ocr — pure handler logic (BACKEND_SPEC §2 step 6).
 *
 * The iOS Vision layer does the actual OCR on-device; this endpoint receives
 * the RAW recognised label text and turns it into a PROVISIONAL product:
 *   - parse the ingredients list + detectable additives from the text,
 *   - build a product with source="ocr" and data_confidence="limited",
 *   - run the SAME deterministic engine. OCR gives us no NOVA group and no
 *     Nutri-Score, so computeScore takes the "not enough data" path → band
 *     "unknown", no numeric score. That is the honest result: label text alone
 *     is limited-confidence, so we never fabricate a precise score from it.
 *   - persist and return the Models.swift `Product` shape (score omitted, as on
 *     the barcode endpoint when band is "unknown").
 *
 * Detected additive tags are still stored so the AI ingredients endpoint can
 * explain them and so the product can be re-scored later if richer data lands.
 *
 * Function name cannot contain a slash, so it deploys as `product-ocr`; the
 * documented client path is POST /product/ocr (see supabase/README.md).
 */

import { computeScore, type ScoreOutput } from "../_shared/scoring/engine.ts";
import { mapAdditiveTiers, type ProductRow } from "../product/handler.ts";
import additivesRisk from "../_shared/scoring/additives_risk.json" with {
  type: "json",
};

export const CORS_HEADERS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
  });
}

export interface Deps {
  /** Insert a provisional OCR product; returns the stored row incl. id. */
  createProduct(row: Omit<ProductRow, "id">): Promise<ProductRow>;
  insertScoreResult(productId: string, result: ScoreOutput): Promise<void>;
  now(): number;
}

// ---------------------------------------------------------------------------
// Label parsing (pure, testable)
// ---------------------------------------------------------------------------

interface RiskName {
  name?: string;
}

/** name (lowercased, parenthetical stripped) → OFF additive tag, from the
 * curated risk table. Lets us catch additives written by name, not E-number. */
const ADDITIVE_NAME_TO_TAG: Map<string, string> = (() => {
  const map = new Map<string, string>();
  const table = additivesRisk as unknown as Record<string, RiskName>;
  for (const [tag, entry] of Object.entries(table)) {
    if (tag === "_meta" || !entry.name) continue;
    const cleaned = entry.name.replace(/\(.*?\)/g, "").trim().toLowerCase();
    if (cleaned) map.set(cleaned, tag);
    // also index text inside parentheses, e.g. "(MSG)" / "(carmine)"
    const paren = entry.name.match(/\(([^)]+)\)/);
    if (paren) {
      const alt = paren[1].trim().toLowerCase();
      if (alt) map.set(alt, tag);
    }
  }
  return map;
})();

const E_NUMBER_RE = /\be[\s-]?(\d{3,4}[a-z]?)\b/gi;
const SECTION_STOP_RE =
  /\b(nutrition|nutritional|allergy advice|allergen|storage|best before|manufactured|distributed|net weight|per\s*100)\b/i;
const CONTAINS_RE = /contains[:\s]+([^.\n]*)/i;

/** Slice out the ingredients region: after an "ingredients" header, up to the
 * first nutrition/allergen/storage marker. Falls back to the whole text. */
export function extractIngredientsRegion(text: string): string {
  const norm = text.replace(/\s+/g, " ").trim();
  const header = norm.match(/ingredients?\s*[:\-]?\s*/i);
  let region = header ? norm.slice(header.index! + header[0].length) : norm;
  const stop = region.match(SECTION_STOP_RE);
  if (stop && stop.index !== undefined) region = region.slice(0, stop.index);
  return region.trim();
}

function cleanToken(raw: string): string | null {
  const t = raw
    .replace(/\([^)]*\)/g, " ") // drop parentheticals (often % or E-numbers)
    .replace(/\d+([.,]\d+)?\s*%/g, " ") // drop percentages
    .replace(/[.;:*]+$/g, " ")
    .replace(/\s+/g, " ")
    .trim()
    .replace(/^[^a-z0-9]+|[^a-z0-9]+$/gi, "")
    .trim();
  if (!t) return null;
  // Drop pure numbers / single letters / obvious noise.
  if (t.length < 2) return null;
  if (!/[a-z]/i.test(t)) return null;
  // Drop a bare E-number that leaked in as its own token (e.g. the "E150d)"
  // fragment left when a comma-split breaks a "Colour (E150c, E150d)"
  // parenthetical). The additive tag is already captured by E_NUMBER_RE over
  // the whole region, so this fragment carries no ingredient meaning.
  if (/^e\s?\d{3,4}[a-z]?$/i.test(t)) return null;
  return t;
}

/** OFF/EU function-class words that are label noise once the specific additive
 * in their parenthetical is captured (en:eNNN or a name we resolve). */
const ADDITIVE_CLASS_WORDS = new Set([
  "colour",
  "color",
  "colours",
  "colors",
  "flavour",
  "flavor",
  "flavouring",
  "flavoring",
  "flavourings",
  "flavorings",
  "emulsifier",
  "emulsifiers",
  "stabiliser",
  "stabilizer",
  "stabilisers",
  "stabilizers",
  "preservative",
  "preservatives",
  "antioxidant",
  "antioxidants",
  "acidity regulator",
  "acidity regulators",
  "raising agent",
  "raising agents",
  "sweetener",
  "sweeteners",
  "thickener",
  "thickeners",
  "anti-caking agent",
  "firming agent",
  "humectant",
  "glazing agent",
]);

/** True when `part` is just an additive-class word whose parenthetical resolves
 * to an additive (E-number or a name in ADDITIVE_NAME_TO_TAG) — a redundant
 * orphan we should NOT emit as a display ingredient. The closing paren is
 * OPTIONAL so a comma-split fragment like "Colour (E150c" (from "Colour (E150c,
 * E150d)") is still recognised and dropped. */
function isAdditiveClassOrphan(part: string): boolean {
  const paren = part.match(/^([^()]+?)\s*\(([^)]*)\)?[.;:*\s]*$/);
  if (!paren) return false;
  const base = paren[1].trim().toLowerCase().replace(/[.;:*]+$/g, "").trim();
  if (!ADDITIVE_CLASS_WORDS.has(base)) return false;
  const inside = paren[2].toLowerCase();
  if (/\be[\s-]?\d{3,4}[a-z]?\b/.test(inside)) return true; // E-number inside
  for (const seg of inside.split(/[,;-]+/)) { // named additive inside
    if (ADDITIVE_NAME_TO_TAG.has(seg.trim())) return true;
  }
  return false;
}

export interface ParsedLabel {
  ingredients: string[]; // display tokens, de-duplicated, order preserved
  additivesTags: string[]; // en:eNNN, de-duplicated
  allergens: string[]; // from a "contains:" statement, if present
}

export function parseLabel(text: string): ParsedLabel {
  const region = extractIngredientsRegion(text);

  // Additive tags: E-numbers anywhere in the region + additive names.
  const tags = new Set<string>();
  for (const m of region.matchAll(E_NUMBER_RE)) {
    tags.add(`en:e${m[1].toLowerCase()}`);
  }

  // Ingredient tokens (split on commas/semicolons; brackets already handled).
  const ingredients: string[] = [];
  const seen = new Set<string>();
  for (const part of region.split(/[,;]+/)) {
    // Skip a redundant additive-class orphan ("Colour (E150d)") — its additive
    // tag is already captured by E_NUMBER_RE / the name pass over the region.
    if (isAdditiveClassOrphan(part)) continue;
    const token = cleanToken(part);
    if (!token) continue;
    const key = token.toLowerCase();
    if (seen.has(key)) continue;
    seen.add(key);
    ingredients.push(token);
    // additive detected by name?
    const byName = ADDITIVE_NAME_TO_TAG.get(key);
    if (byName) tags.add(byName);
  }

  // Allergens from an explicit "Contains ..." statement.
  const allergens: string[] = [];
  const contains = text.match(CONTAINS_RE);
  if (contains) {
    const seenA = new Set<string>();
    for (const part of contains[1].split(/[,;]+|\band\b/i)) {
      const a = part.replace(/[^a-z\s]/gi, " ").replace(/\s+/g, " ").trim();
      if (a.length >= 2 && !seenA.has(a.toLowerCase())) {
        seenA.add(a.toLowerCase());
        allergens.push(a);
      }
    }
  }

  return { ingredients, additivesTags: [...tags], allergens };
}

// ---------------------------------------------------------------------------
// Response shaping — must decode into Models.swift `Product`
// ---------------------------------------------------------------------------

interface ProductBody {
  id: string;
  barcode: string | null;
  name: string;
  brand: string | null;
  imageURL: string | null;
  score?: unknown; // omitted for OCR (band always "unknown")
  ingredients: unknown[];
  allergens: string[];
  dataConfidence: string;
}

function buildBody(product: ProductRow): ProductBody {
  return {
    id: product.id,
    barcode: product.barcode,
    name: product.name,
    brand: product.brand,
    imageURL: product.images?.front ?? null,
    ingredients: [],
    allergens: product.allergens_tags,
    dataConfidence: product.data_confidence,
  };
}

// ---------------------------------------------------------------------------
// Handler
// ---------------------------------------------------------------------------

export async function handleOcr(req: Request, deps: Deps): Promise<Response> {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: CORS_HEADERS });
  }
  if (req.method !== "POST") {
    return json({ error: "method_not_allowed" }, 405);
  }
  if (!req.headers.get("Authorization")) {
    return json({ error: "unauthorized" }, 401);
  }

  let payload: { text?: unknown; name?: unknown };
  try {
    payload = await req.json();
  } catch {
    return json({ error: "invalid_json" }, 400);
  }

  const text = typeof payload.text === "string" ? payload.text : "";
  if (text.trim().length < 3) {
    return json(
      { error: "empty_text", detail: "Send the recognised label text." },
      400,
    );
  }

  const parsed = parseLabel(text);
  const providedName = typeof payload.name === "string" ? payload.name.trim() : "";
  const name = providedName || "Scanned product";

  // OCR gives no NOVA / Nutri-Score → engine returns the "unknown" state.
  const { tiers } = mapAdditiveTiers(parsed.additivesTags);
  const scoreOutput = computeScore({
    novaGroup: null,
    nutriscoreGrade: null,
    additiveTiers: tiers,
  });

  const nowIso = new Date(deps.now()).toISOString();
  const productRow = await deps.createProduct({
    barcode: null,
    name,
    brand: null,
    source: "ocr",
    nova_group: null,
    nutriscore_grade: null,
    nutrients: {},
    serving_size: null,
    additives_tags: parsed.additivesTags,
    allergens_tags: parsed.allergens,
    // OCR products have no OFF category; swaps can't group them (honest empty).
    categories_tags: [],
    ingredients_text: parsed.ingredients.join(", ") || null,
    images: null,
    data_confidence: "limited",
    raw_off: { source: "ocr", text, parsed },
    fetched_at: nowIso,
  });
  await deps.insertScoreResult(productRow.id, scoreOutput);

  return json(buildBody(productRow));
}
