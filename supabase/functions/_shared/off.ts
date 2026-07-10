/**
 * Open Food Facts v2 API client.
 *
 * Rules (BACKEND_SPEC §2):
 * - Always send a descriptive User-Agent (OFF requirement).
 * - Request only the fields we need.
 * - Never call this on a cache hit — the product endpoint enforces the
 *   30-day TTL before reaching for the network.
 * - OFF data is ODbL: attribute Open Food Facts and share-alike on data.
 */

const OFF_BASE_URL = "https://world.openfoodfacts.org/api/v2/product";

/** OFF v2 name-search endpoint (Chunk 2). Kept general so Chunk 3 (Swaps)
 * can reuse the same search/category plumbing. */
export const OFF_SEARCH_BASE_URL =
  "https://world.openfoodfacts.org/api/v2/search";

export const OFF_USER_AGENT = "FoodScannerApp/0.1 (dev; muzeeb@omnisai.io)";

/** The only fields we ask OFF for. */
export const OFF_FIELDS = [
  "product_name",
  "brands",
  "nova_group",
  "nutriscore_grade",
  "additives_tags",
  "allergens_tags",
  "ingredients_text",
  "ingredients",
  "image_front_url",
  "serving_size",
  "nutriments",
].join(",");

/** Our internal, normalized shape for an OFF product. */
export interface OffProduct {
  barcode: string;
  name: string;
  brand: string | null;
  novaGroup: number | null; // 1–4 or null
  nutriscoreGrade: string | null; // "a"–"e" or null
  additivesTags: string[]; // e.g. ["en:e330", "en:e250"]
  allergensTags: string[]; // e.g. ["en:milk"]
  ingredientsText: string | null;
  imageUrl: string | null;
  servingSize: string | null;
  nutriments: Record<string, unknown>;
  /** Original payload, stored as raw_off for score re-derivation. */
  raw: unknown;
}

const VALID_NUTRI_GRADES = new Set(["a", "b", "c", "d", "e"]);

function asNonEmptyString(value: unknown): string | null {
  return typeof value === "string" && value.trim() !== "" ? value.trim() : null;
}

/**
 * Map a single raw OFF product object + its explicit barcode to our internal
 * shape. The one place the OFF field mapping lives — shared by the by-barcode
 * `mapOffPayload` and the name-search `mapOffSearchPayload` so both stay in
 * lockstep. `raw` preserves the source object for re-derivation.
 * Exported separately so it is unit-testable without any network.
 */
export function mapOffFields(
  p: Record<string, unknown>,
  code: string,
): OffProduct {
  // nova_group: number 1–4, sometimes a numeric string, often absent.
  let novaGroup: number | null = null;
  const rawNova = p.nova_group;
  if (typeof rawNova === "number" && rawNova >= 1 && rawNova <= 4) {
    novaGroup = rawNova;
  } else if (typeof rawNova === "string") {
    const parsed = Number.parseInt(rawNova, 10);
    if (parsed >= 1 && parsed <= 4) novaGroup = parsed;
  }

  // nutriscore_grade: "a"–"e"; OFF also emits "unknown" / "not-applicable".
  let nutriscoreGrade: string | null = null;
  const rawGrade = asNonEmptyString(p.nutriscore_grade)?.toLowerCase() ?? null;
  if (rawGrade !== null && VALID_NUTRI_GRADES.has(rawGrade)) {
    nutriscoreGrade = rawGrade;
  }

  return {
    barcode: asNonEmptyString(code) ?? "",
    name: asNonEmptyString(p.product_name) ?? "Unknown product",
    brand: asNonEmptyString(p.brands),
    novaGroup,
    nutriscoreGrade,
    additivesTags: Array.isArray(p.additives_tags)
      ? p.additives_tags.filter((t): t is string => typeof t === "string")
      : [],
    allergensTags: Array.isArray(p.allergens_tags)
      ? p.allergens_tags.filter((t): t is string => typeof t === "string")
      : [],
    ingredientsText: asNonEmptyString(p.ingredients_text),
    imageUrl: asNonEmptyString(p.image_front_url),
    servingSize: asNonEmptyString(p.serving_size),
    nutriments:
      p.nutriments && typeof p.nutriments === "object"
        ? (p.nutriments as Record<string, unknown>)
        : {},
    raw: p,
  };
}

/**
 * Map an OFF v2 by-barcode response body to our internal shape.
 * Returns null when the product is not in OFF (status 0).
 * Exported separately so it is unit-testable without any network.
 */
export function mapOffPayload(payload: unknown): OffProduct | null {
  const body = payload as {
    status?: number;
    code?: string;
    product?: Record<string, unknown>;
  } | null;

  if (!body || body.status === 0 || !body.product) {
    return null;
  }

  const mapped = mapOffFields(body.product, asNonEmptyString(body.code) ?? "");
  // The by-barcode path preserves the FULL response envelope as raw_off
  // (status/code + product), matching the pre-refactor behavior.
  return { ...mapped, raw: payload };
}

/**
 * Map an OFF v2 SEARCH response body (`{ products: [...], count }`) to our
 * internal shape. Each item carries its own `code`. Items with a blank/missing
 * barcode are dropped (a nameless/codeless row is useless). Returns [] for an
 * empty or malformed body. Kept general (no Search-screen assumptions) so
 * Chunk 3 (Swaps) can reuse it.
 */
export function mapOffSearchPayload(payload: unknown): OffProduct[] {
  const products = (payload as { products?: unknown } | null)?.products;
  if (!Array.isArray(products)) return [];

  const out: OffProduct[] = [];
  for (const item of products) {
    if (!item || typeof item !== "object") continue;
    const p = item as Record<string, unknown>;
    const code = asNonEmptyString(p.code);
    if (code === null) continue; // no barcode → useless row
    out.push(mapOffFields(p, code));
  }
  return out;
}

/**
 * Fetch a product from OFF by barcode.
 * Returns null when the product is not found (OFF status 0 or HTTP 404).
 * Throws on other transport/HTTP failures so callers can surface a 502.
 * `fetchImpl` is injectable for tests.
 */
export async function fetchProduct(
  barcode: string,
  fetchImpl: typeof fetch = fetch,
): Promise<OffProduct | null> {
  const url = `${OFF_BASE_URL}/${encodeURIComponent(barcode)}.json?fields=${OFF_FIELDS}`;

  const res = await fetchImpl(url, {
    headers: {
      "User-Agent": OFF_USER_AGENT,
      Accept: "application/json",
    },
  });

  // OFF returns 404 (with a status:0 JSON body) for unknown barcodes.
  if (res.status === 404) {
    return null;
  }
  if (!res.ok) {
    throw new Error(`Open Food Facts request failed: HTTP ${res.status}`);
  }

  const payload = await res.json();
  return mapOffPayload(payload);
}

/**
 * Name-search OFF v2. Returns the mapped (barcode-carrying) products, sorted
 * by popularity server-side. Throws on non-OK HTTP so the handler can surface
 * a 502. `fetchImpl` is injectable for tests. Attaches NO scores — the search
 * handler joins our own cached scores separately (transparency: we never show
 * OFF's own Nutri-Score as ours).
 */
export async function fetchOffSearch(
  query: string,
  fetchImpl: typeof fetch = fetch,
): Promise<OffProduct[]> {
  // encodeURIComponent (not URLSearchParams, which would encode spaces as "+")
  // so the query is percent-encoded exactly (matches the plan + fetchProduct).
  const url = `${OFF_SEARCH_BASE_URL}?search_terms=${
    encodeURIComponent(query)
  }&fields=${OFF_FIELDS},code&page_size=20&sort_by=unique_scans_n`;

  const res = await fetchImpl(url, {
    headers: {
      "User-Agent": OFF_USER_AGENT,
      Accept: "application/json",
    },
  });

  if (!res.ok) {
    throw new Error(`Open Food Facts search failed: HTTP ${res.status}`);
  }

  return mapOffSearchPayload(await res.json());
}
