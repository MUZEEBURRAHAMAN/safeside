/**
 * Open Food Facts client tests — mapping + fetch behavior with a canned
 * fixture. No real network: fetch is injected.
 */

import { assertEquals, assertStringIncludes } from "jsr:@std/assert@1";
import {
  fetchOffSearch,
  fetchProduct,
  mapOffFields,
  mapOffPayload,
  mapOffSearchPayload,
  OFF_USER_AGENT,
} from "./off.ts";

/** Realistic OFF v2 payload (Nutella-like hazelnut spread). */
const NUTELLA_FIXTURE = {
  code: "3017620422003",
  status: 1,
  status_verbose: "product found",
  product: {
    product_name: "Nutella",
    brands: "Ferrero",
    nova_group: 4,
    nutriscore_grade: "e",
    additives_tags: ["en:e322", "en:e471"],
    allergens_tags: ["en:milk", "en:nuts", "en:soybeans"],
    ingredients_text:
      "Sugar, palm oil, hazelnuts 13%, skimmed milk powder 8.7%, fat-reduced cocoa 7.4%, emulsifier: lecithins (soya), vanillin.",
    ingredients: [
      { id: "en:sugar", text: "Sugar", percent_estimate: 38 },
      { id: "en:palm-oil", text: "palm oil", percent_estimate: 22 },
    ],
    image_front_url:
      "https://images.openfoodfacts.org/images/products/301/762/042/2003/front_en.jpg",
    serving_size: "15 g",
    nutriments: {
      "energy-kcal_100g": 539,
      sugars_100g: 56.3,
      fat_100g: 30.9,
      "saturated-fat_100g": 10.6,
      proteins_100g: 6.3,
      salt_100g: 0.107,
    },
  },
};

const NOT_FOUND_FIXTURE = {
  code: "0000000000000",
  status: 0,
  status_verbose: "product not found",
};

Deno.test("mapOffPayload maps a full payload to the internal shape", () => {
  const mapped = mapOffPayload(NUTELLA_FIXTURE);
  if (mapped === null) throw new Error("expected a product");

  assertEquals(mapped.barcode, "3017620422003");
  assertEquals(mapped.name, "Nutella");
  assertEquals(mapped.brand, "Ferrero");
  assertEquals(mapped.novaGroup, 4);
  assertEquals(mapped.nutriscoreGrade, "e");
  assertEquals(mapped.additivesTags, ["en:e322", "en:e471"]);
  assertEquals(mapped.allergensTags, ["en:milk", "en:nuts", "en:soybeans"]);
  assertEquals(mapped.servingSize, "15 g");
  assertEquals(
    mapped.imageUrl,
    "https://images.openfoodfacts.org/images/products/301/762/042/2003/front_en.jpg",
  );
  assertEquals(mapped.nutriments["sugars_100g"], 56.3);
  // Raw payload preserved for raw_off / re-derivation.
  assertEquals(mapped.raw, NUTELLA_FIXTURE);
});

Deno.test("mapOffPayload handles missing fields gracefully", () => {
  const thin = {
    code: "1234567890123",
    status: 1,
    product: { product_name: "Mystery item" },
  };
  const mapped = mapOffPayload(thin);
  if (mapped === null) throw new Error("expected a product");

  assertEquals(mapped.name, "Mystery item");
  assertEquals(mapped.brand, null);
  assertEquals(mapped.novaGroup, null);
  assertEquals(mapped.nutriscoreGrade, null);
  assertEquals(mapped.additivesTags, []);
  assertEquals(mapped.allergensTags, []);
  assertEquals(mapped.ingredientsText, null);
  assertEquals(mapped.imageUrl, null);
  assertEquals(mapped.servingSize, null);
  assertEquals(mapped.nutriments, {});
});

Deno.test("mapOffPayload normalizes odd values", () => {
  const odd = {
    code: "1234567890123",
    status: 1,
    product: {
      product_name: "  Padded name  ",
      brands: "",
      nova_group: "3", // numeric string
      nutriscore_grade: "UNKNOWN", // OFF emits unknown/not-applicable
    },
  };
  const mapped = mapOffPayload(odd);
  if (mapped === null) throw new Error("expected a product");
  assertEquals(mapped.name, "Padded name");
  assertEquals(mapped.brand, null); // empty string → null
  assertEquals(mapped.novaGroup, 3);
  assertEquals(mapped.nutriscoreGrade, null); // "unknown" is not a grade
});

Deno.test("mapOffPayload returns null for status 0 (not found)", () => {
  assertEquals(mapOffPayload(NOT_FOUND_FIXTURE), null);
  assertEquals(mapOffPayload(null), null);
  assertEquals(mapOffPayload({}), null);
});

Deno.test("fetchProduct sends the required User-Agent and field filter", async () => {
  let capturedUrl = "";
  let capturedUserAgent: string | null = null;

  const fakeFetch = (
    input: URL | RequestInfo,
    init?: RequestInit,
  ): Promise<Response> => {
    capturedUrl = String(input);
    capturedUserAgent = new Headers(init?.headers).get("User-Agent");
    return Promise.resolve(
      new Response(JSON.stringify(NUTELLA_FIXTURE), {
        status: 200,
        headers: { "Content-Type": "application/json" },
      }),
    );
  };

  const product = await fetchProduct("3017620422003", fakeFetch);
  if (product === null) throw new Error("expected a product");

  assertEquals(product.name, "Nutella");
  assertEquals(capturedUserAgent, OFF_USER_AGENT);
  assertStringIncludes(
    capturedUrl,
    "https://world.openfoodfacts.org/api/v2/product/3017620422003.json",
  );
  assertStringIncludes(capturedUrl, "fields=");
  assertStringIncludes(capturedUrl, "nova_group");
  assertStringIncludes(capturedUrl, "nutriscore_grade");
  assertStringIncludes(capturedUrl, "additives_tags");
});

Deno.test("fetchProduct returns null on HTTP 404", async () => {
  const fakeFetch = (): Promise<Response> =>
    Promise.resolve(
      new Response(JSON.stringify(NOT_FOUND_FIXTURE), { status: 404 }),
    );
  assertEquals(await fetchProduct("0000000000000", fakeFetch), null);
});

Deno.test("fetchProduct returns null on status 0 with HTTP 200", async () => {
  const fakeFetch = (): Promise<Response> =>
    Promise.resolve(
      new Response(JSON.stringify(NOT_FOUND_FIXTURE), { status: 200 }),
    );
  assertEquals(await fetchProduct("0000000000000", fakeFetch), null);
});

Deno.test("fetchProduct throws on server errors (caller maps to 502)", async () => {
  const fakeFetch = (): Promise<Response> =>
    Promise.resolve(new Response("oops", { status: 500 }));
  let threw = false;
  try {
    await fetchProduct("3017620422003", fakeFetch);
  } catch {
    threw = true;
  }
  assertEquals(threw, true);
});

// ---------------------------------------------------------------------------
// Shared per-product mapper + search (Chunk 2)
// ---------------------------------------------------------------------------

Deno.test("mapOffFields maps a raw product + explicit code to the internal shape", () => {
  const mapped = mapOffFields(NUTELLA_FIXTURE.product, NUTELLA_FIXTURE.code);
  assertEquals(mapped.barcode, "3017620422003");
  assertEquals(mapped.name, "Nutella");
  assertEquals(mapped.brand, "Ferrero");
  assertEquals(mapped.novaGroup, 4);
  assertEquals(mapped.nutriscoreGrade, "e");
  assertEquals(mapped.additivesTags, ["en:e322", "en:e471"]);
  assertEquals(mapped.allergensTags, ["en:milk", "en:nuts", "en:soybeans"]);
  assertEquals(
    mapped.imageUrl,
    "https://images.openfoodfacts.org/images/products/301/762/042/2003/front_en.jpg",
  );
  assertEquals(mapped.nutriments["sugars_100g"], 56.3);
});

Deno.test("mapOffSearchPayload maps a products[] array to OffProducts", () => {
  const payload = {
    count: 2,
    products: [
      { code: "3017620422003", product_name: "Nutella", brands: "Ferrero" },
      { code: "0000000000001", product_name: "Store Oats" },
    ],
  };
  const mapped = mapOffSearchPayload(payload);
  assertEquals(mapped.length, 2);
  assertEquals(mapped[0].barcode, "3017620422003");
  assertEquals(mapped[0].name, "Nutella");
  assertEquals(mapped[1].barcode, "0000000000001");
  assertEquals(mapped[1].name, "Store Oats");
});

Deno.test("mapOffSearchPayload drops items with a missing/blank code", () => {
  const payload = {
    products: [
      { code: "3017620422003", product_name: "Nutella" },
      { code: "", product_name: "No barcode" },
      { product_name: "Missing code entirely" },
    ],
  };
  const mapped = mapOffSearchPayload(payload);
  assertEquals(mapped.length, 1);
  assertEquals(mapped[0].barcode, "3017620422003");
});

Deno.test("mapOffSearchPayload returns [] for empty/malformed bodies", () => {
  assertEquals(mapOffSearchPayload({ products: [] }), []);
  assertEquals(mapOffSearchPayload({}), []);
  assertEquals(mapOffSearchPayload(null), []);
  assertEquals(mapOffSearchPayload({ products: "nope" }), []);
});

Deno.test("fetchOffSearch builds the v2 search URL and returns mapped results", async () => {
  let capturedUrl = "";
  let capturedUserAgent: string | null = null;

  const fakeFetch = (
    input: URL | RequestInfo,
    init?: RequestInit,
  ): Promise<Response> => {
    capturedUrl = String(input);
    capturedUserAgent = new Headers(init?.headers).get("User-Agent");
    return Promise.resolve(
      new Response(
        JSON.stringify({
          count: 1,
          products: [
            { code: "3017620422003", product_name: "Nutella", brands: "Ferrero" },
          ],
        }),
        { status: 200, headers: { "Content-Type": "application/json" } },
      ),
    );
  };

  const results = await fetchOffSearch("nutella", fakeFetch);
  assertEquals(results.length, 1);
  assertEquals(results[0].name, "Nutella");
  assertEquals(capturedUserAgent, OFF_USER_AGENT);
  assertStringIncludes(
    capturedUrl,
    "https://world.openfoodfacts.org/api/v2/search",
  );
  assertStringIncludes(capturedUrl, "search_terms=nutella");
  assertStringIncludes(capturedUrl, "fields=");
  assertStringIncludes(capturedUrl, "code");
  assertStringIncludes(capturedUrl, "page_size=20");
  assertStringIncludes(capturedUrl, "sort_by=unique_scans_n");
});

Deno.test("fetchOffSearch percent-encodes the query", async () => {
  let capturedUrl = "";
  const fakeFetch = (input: URL | RequestInfo): Promise<Response> => {
    capturedUrl = String(input);
    return Promise.resolve(
      new Response(JSON.stringify({ products: [] }), { status: 200 }),
    );
  };
  await fetchOffSearch("dark chocolate 70%", fakeFetch);
  assertStringIncludes(capturedUrl, "search_terms=dark%20chocolate%2070%25");
});

Deno.test("fetchOffSearch throws on non-OK HTTP (caller maps to 502)", async () => {
  const fakeFetch = (): Promise<Response> =>
    Promise.resolve(new Response("oops", { status: 500 }));
  let threw = false;
  try {
    await fetchOffSearch("nutella", fakeFetch);
  } catch {
    threw = true;
  }
  assertEquals(threw, true);
});
