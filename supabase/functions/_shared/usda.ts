/**
 * USDA FoodData Central (FDC) client — nutrient enrichment.
 *
 * Role (BACKEND_SPEC §2 step 4, SCORING_METHODOLOGY §3): when Open Food Facts
 * has thin/missing nutrients, search FDC by product name/brand and MERGE the
 * result to fill gaps. OFF always takes precedence; USDA only fills what OFF
 * lacks. FDC data is public domain (CC0) — no attribution required.
 *
 * Honesty rules:
 * - USDA is a FUZZY NAME match, never a barcode match, so we mark provenance
 *   (fdcId + description) and never overstate the match.
 * - Never throws into the pipeline: no key, no match, or a transport error all
 *   return `null`. The scan still succeeds on OFF data alone.
 * - Never called on a cache hit — the product handler only reaches here on a
 *   cache miss / stale re-fetch (USDA free key is ~1,000 req/hr; cache hard).
 * - The score itself is unaffected (it derives from NOVA + Nutri-Score +
 *   additives); enrichment only improves the stored nutrient table.
 *
 * Pure mappers are exported separately so the whole thing is unit-testable
 * offline with an injected fetch — no network, no env, no DB.
 */

export const USDA_SEARCH_URL = "https://api.nal.usda.gov/fdc/v1/foods/search";

/**
 * FDC nutrientNumber → our OFF-style nutriment key (per 100 g). We reuse the
 * exact OFF keys so merging into `OffProduct.nutriments` is a plain gap-fill.
 * Sodium (mg) is handled specially → sodium_100g (g) + salt_100g (g).
 */
export const NUTRIENT_NUMBER_MAP: Record<string, string> = {
  "208": "energy-kcal_100g", // Energy (KCAL)
  "203": "proteins_100g", // Protein
  "204": "fat_100g", // Total lipid (fat)
  "606": "saturated-fat_100g", // Fatty acids, total saturated
  "205": "carbohydrates_100g", // Carbohydrate, by difference
  "269": "sugars_100g", // Total sugars
  "2000": "sugars_100g", // Total sugars (alternate number)
  "291": "fiber_100g", // Fiber, total dietary
};

const SODIUM_NUMBER = "307"; // Sodium, Na (mg per 100 g)
const SALT_PER_SODIUM = 2.5; // salt (g) = sodium (g) × 2.5

/** Key macros used to decide whether OFF nutrients are "thin" (§2). */
export const KEY_MACROS = [
  "energy-kcal_100g",
  "proteins_100g",
  "fat_100g",
  "carbohydrates_100g",
  "sugars_100g",
  "salt_100g",
] as const;

export interface UsdaMatch {
  fdcId: number | null;
  description: string;
  dataType: string | null;
  /** OFF-style per-100g nutriments — only the keys we could read. */
  nutrients: Record<string, number>;
}

interface FdcNutrient {
  nutrientNumber?: string;
  unitName?: string;
  value?: number;
}

interface FdcFood {
  fdcId?: number;
  description?: string;
  dataType?: string;
  foodNutrients?: FdcNutrient[];
}

function isFiniteNumber(v: unknown): v is number {
  return typeof v === "number" && Number.isFinite(v);
}

/** How many key macros are present (finite numbers) in an OFF nutriment map. */
export function presentMacroCount(nutriments: Record<string, unknown>): number {
  let n = 0;
  for (const key of KEY_MACROS) {
    if (isFiniteNumber(nutriments[key])) n++;
  }
  return n;
}

/**
 * OFF nutrients are "thin" when most key macros are missing. Threshold: fewer
 * than 4 of the 6 key macros present. (A sugars-only row is thin; a full
 * Nutri-Score-grade table is not.)
 */
export function isNutrientsThin(nutriments: Record<string, unknown>): boolean {
  return presentMacroCount(nutriments) < 4;
}

/**
 * Map one FDC search `food` to our OFF-style per-100g nutriment map.
 * Only includes keys we could read as finite numbers. Pure + testable.
 */
export function mapFdcFoodToNutrients(food: FdcFood): Record<string, number> {
  const out: Record<string, number> = {};
  const nutrients = Array.isArray(food.foodNutrients) ? food.foodNutrients : [];
  for (const n of nutrients) {
    const num = n.nutrientNumber;
    if (typeof num !== "string" || !isFiniteNumber(n.value)) continue;

    if (num === SODIUM_NUMBER) {
      // FDC sodium is mg per 100 g → grams.
      const sodiumG = n.value / 1000;
      if (!(("sodium_100g") in out)) out["sodium_100g"] = sodiumG;
      if (!(("salt_100g") in out)) {
        out["salt_100g"] = Math.round(sodiumG * SALT_PER_SODIUM * 1000) / 1000;
      }
      continue;
    }

    const key = NUTRIENT_NUMBER_MAP[num];
    if (key && !(key in out)) out[key] = n.value;
  }
  return out;
}

/**
 * Search FDC by name (+ optional brand) and return the best match's nutrients.
 * Returns null on: no/empty key, no results, no usable nutrients, or any error.
 *
 * `apiKey`/`fetchImpl` are injectable for offline tests. Env is only read when
 * `apiKey` is omitted entirely (so tests that pass a key never touch Deno.env).
 */
export async function searchUsdaNutrients(
  query: string,
  opts: {
    brand?: string | null;
    apiKey?: string;
    fetchImpl?: typeof fetch;
    pageSize?: number;
  } = {},
): Promise<UsdaMatch | null> {
  const trimmed = (query ?? "").trim();
  if (trimmed === "") return null;

  const apiKey = opts.apiKey ?? Deno.env.get("USDA_API_KEY") ?? "DEMO_KEY";
  if (!apiKey) return null; // explicit empty key disables enrichment

  const fetchImpl = opts.fetchImpl ?? fetch;
  const searchTerm = [opts.brand?.trim(), trimmed].filter(Boolean).join(" ");

  const url = new URL(USDA_SEARCH_URL);
  url.searchParams.set("api_key", apiKey);
  url.searchParams.set("query", searchTerm);
  url.searchParams.set("pageSize", String(opts.pageSize ?? 5));
  // Prefer curated reference data over crowd-entered branded rows for generics,
  // but include Branded so packaged products still match.
  url.searchParams.set(
    "dataType",
    "Foundation,SR Legacy,Branded",
  );

  let payload: unknown;
  try {
    const res = await fetchImpl(url.toString(), {
      headers: { Accept: "application/json" },
    });
    if (!res.ok) return null;
    payload = await res.json();
  } catch {
    return null; // never break the pipeline on a USDA transport error
  }

  const body = payload as { foods?: FdcFood[] } | null;
  const foods = Array.isArray(body?.foods) ? body!.foods! : [];
  if (foods.length === 0) return null;

  const food = foods[0]; // FDC ranks by relevance
  const nutrients = mapFdcFoodToNutrients(food);
  if (Object.keys(nutrients).length === 0) return null;

  return {
    fdcId: typeof food.fdcId === "number" ? food.fdcId : null,
    description: typeof food.description === "string" ? food.description : searchTerm,
    dataType: typeof food.dataType === "string" ? food.dataType : null,
    nutrients,
  };
}

/**
 * Merge USDA nutrients into OFF nutriments. OFF wins wherever it has a finite
 * number; USDA only fills gaps. Returns the merged map and the list of keys
 * USDA actually filled (empty → OFF already had everything USDA offered).
 */
export function mergeNutrients(
  off: Record<string, unknown>,
  usda: Record<string, number>,
): { merged: Record<string, unknown>; filled: string[] } {
  const merged: Record<string, unknown> = { ...off };
  const filled: string[] = [];
  for (const [key, value] of Object.entries(usda)) {
    if (!isFiniteNumber(merged[key])) {
      merged[key] = value;
      filled.push(key);
    }
  }
  return { merged, filled };
}
