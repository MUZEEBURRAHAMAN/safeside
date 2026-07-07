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
 * Map an OFF v2 response body to our internal shape.
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

  const p = body.product;

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
    barcode: asNonEmptyString(body.code) ?? "",
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
    raw: payload,
  };
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
