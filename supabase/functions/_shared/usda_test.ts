/**
 * USDA FoodData Central client tests — mapping, matching, and merge logic.
 * Fully offline: fetch + apiKey are injected, so no network and no Deno.env.
 */

import { assertEquals } from "jsr:@std/assert@1";
import {
  isNutrientsThin,
  mapFdcFoodToNutrients,
  mergeNutrients,
  presentMacroCount,
  searchUsdaNutrients,
  USDA_SEARCH_URL,
} from "./usda.ts";

/** A realistic FDC /foods/search payload (peanut butter, per 100 g). */
const FDC_FIXTURE = {
  foods: [
    {
      fdcId: 172470,
      description: "Peanut butter, smooth style",
      dataType: "SR Legacy",
      foodNutrients: [
        { nutrientNumber: "208", nutrientName: "Energy", unitName: "KCAL", value: 588 },
        { nutrientNumber: "203", nutrientName: "Protein", unitName: "G", value: 25 },
        {
          nutrientNumber: "204",
          nutrientName: "Total lipid (fat)",
          unitName: "G",
          value: 50,
        },
        {
          nutrientNumber: "606",
          nutrientName: "Saturated fat",
          unitName: "G",
          value: 10,
        },
        { nutrientNumber: "205", nutrientName: "Carbohydrate", unitName: "G", value: 20 },
        { nutrientNumber: "269", nutrientName: "Sugars", unitName: "G", value: 9 },
        { nutrientNumber: "291", nutrientName: "Fiber", unitName: "G", value: 6 },
        { nutrientNumber: "307", nutrientName: "Sodium", unitName: "MG", value: 400 },
      ],
    },
  ],
};

// ---------------------------------------------------------------------------
// Mapping
// ---------------------------------------------------------------------------

Deno.test("mapFdcFoodToNutrients maps FDC numbers to OFF-style keys per 100 g", () => {
  const out = mapFdcFoodToNutrients(FDC_FIXTURE.foods[0]);
  assertEquals(out["energy-kcal_100g"], 588);
  assertEquals(out["proteins_100g"], 25);
  assertEquals(out["fat_100g"], 50);
  assertEquals(out["saturated-fat_100g"], 10);
  assertEquals(out["carbohydrates_100g"], 20);
  assertEquals(out["sugars_100g"], 9);
  assertEquals(out["fiber_100g"], 6);
  // Sodium: 400 mg → 0.4 g, salt = sodium × 2.5 = 1.0 g.
  assertEquals(out["sodium_100g"], 0.4);
  assertEquals(out["salt_100g"], 1);
});

Deno.test("mapFdcFoodToNutrients skips non-numeric values and unknown nutrients", () => {
  const out = mapFdcFoodToNutrients({
    foodNutrients: [
      { nutrientNumber: "203", unitName: "G", value: 12 },
      { nutrientNumber: "203", unitName: "G", value: 99 }, // duplicate → first wins
      { nutrientNumber: "204", unitName: "G" }, // no value → skipped
      { nutrientNumber: "999", unitName: "G", value: 5 }, // unknown → skipped
    ],
  });
  assertEquals(out["proteins_100g"], 12);
  assertEquals("fat_100g" in out, false);
  assertEquals(Object.keys(out).length, 1);
});

Deno.test("mapFdcFoodToNutrients returns empty for a food with no nutrients", () => {
  assertEquals(mapFdcFoodToNutrients({}), {});
  assertEquals(mapFdcFoodToNutrients({ foodNutrients: [] }), {});
});

// ---------------------------------------------------------------------------
// Thin-nutrient detection
// ---------------------------------------------------------------------------

Deno.test("isNutrientsThin: sugars-only OFF row is thin, a full table is not", () => {
  assertEquals(presentMacroCount({ sugars_100g: 56.3 }), 1);
  assertEquals(isNutrientsThin({ sugars_100g: 56.3 }), true);
  assertEquals(isNutrientsThin({}), true);

  const full = {
    "energy-kcal_100g": 539,
    sugars_100g: 56.3,
    fat_100g: 30.9,
    "saturated-fat_100g": 10.6,
    proteins_100g: 6.3,
    salt_100g: 0.107,
  };
  // 5 key macros present (carbohydrates_100g absent, saturated-fat not counted).
  assertEquals(presentMacroCount(full), 5);
  assertEquals(isNutrientsThin(full), false);
});

Deno.test("isNutrientsThin ignores non-finite values", () => {
  assertEquals(
    isNutrientsThin({ "energy-kcal_100g": null, proteins_100g: "x", fat_100g: NaN }),
    true,
  );
});

// ---------------------------------------------------------------------------
// Search: success, no-match, no-key, transport error
// ---------------------------------------------------------------------------

Deno.test("searchUsdaNutrients returns the mapped best match and sends the key", async () => {
  let capturedUrl = "";
  const fakeFetch = (input: URL | RequestInfo): Promise<Response> => {
    capturedUrl = String(input);
    return Promise.resolve(
      new Response(JSON.stringify(FDC_FIXTURE), {
        status: 200,
        headers: { "Content-Type": "application/json" },
      }),
    );
  };

  const match = await searchUsdaNutrients("Peanut butter", {
    brand: "Acme",
    apiKey: "TEST_KEY",
    fetchImpl: fakeFetch,
  });
  if (match === null) throw new Error("expected a match");

  assertEquals(match.fdcId, 172470);
  assertEquals(match.description, "Peanut butter, smooth style");
  assertEquals(match.dataType, "SR Legacy");
  assertEquals(match.nutrients["proteins_100g"], 25);

  // Query combined brand + name; key + endpoint present.
  if (!capturedUrl.startsWith(USDA_SEARCH_URL)) {
    throw new Error(`unexpected URL: ${capturedUrl}`);
  }
  const url = new URL(capturedUrl);
  assertEquals(url.searchParams.get("api_key"), "TEST_KEY");
  assertEquals(url.searchParams.get("query"), "Acme Peanut butter");
});

Deno.test("searchUsdaNutrients returns null when FDC has no results", async () => {
  const fakeFetch = (): Promise<Response> =>
    Promise.resolve(new Response(JSON.stringify({ foods: [] }), { status: 200 }));
  const match = await searchUsdaNutrients("Nonexistent product", {
    apiKey: "TEST_KEY",
    fetchImpl: fakeFetch,
  });
  assertEquals(match, null);
});

Deno.test("searchUsdaNutrients returns null when the match has no usable nutrients", async () => {
  const fakeFetch = (): Promise<Response> =>
    Promise.resolve(
      new Response(
        JSON.stringify({ foods: [{ fdcId: 1, description: "x", foodNutrients: [] }] }),
        { status: 200 },
      ),
    );
  assertEquals(
    await searchUsdaNutrients("x", { apiKey: "TEST_KEY", fetchImpl: fakeFetch }),
    null,
  );
});

Deno.test("searchUsdaNutrients returns null with no key (empty string disables)", async () => {
  let called = false;
  const fakeFetch = (): Promise<Response> => {
    called = true;
    return Promise.resolve(new Response("{}"));
  };
  const match = await searchUsdaNutrients("Peanut butter", {
    apiKey: "",
    fetchImpl: fakeFetch,
  });
  assertEquals(match, null);
  assertEquals(called, false, "must not hit the network without a key");
});

Deno.test("searchUsdaNutrients returns null on an empty query", async () => {
  let called = false;
  const fakeFetch = (): Promise<Response> => {
    called = true;
    return Promise.resolve(new Response("{}"));
  };
  assertEquals(
    await searchUsdaNutrients("   ", { apiKey: "TEST_KEY", fetchImpl: fakeFetch }),
    null,
  );
  assertEquals(called, false);
});

Deno.test("searchUsdaNutrients never throws — HTTP error and network error → null", async () => {
  const errFetch = (): Promise<Response> =>
    Promise.resolve(new Response("nope", { status: 500 }));
  assertEquals(
    await searchUsdaNutrients("x", { apiKey: "K", fetchImpl: errFetch }),
    null,
  );

  const throwFetch = (): Promise<Response> => Promise.reject(new Error("boom"));
  assertEquals(
    await searchUsdaNutrients("x", { apiKey: "K", fetchImpl: throwFetch }),
    null,
  );
});

// ---------------------------------------------------------------------------
// Merge: OFF precedence, USDA fills gaps
// ---------------------------------------------------------------------------

Deno.test("mergeNutrients: OFF wins where present, USDA fills gaps", () => {
  const off = { sugars_100g: 56.3, proteins_100g: 6.3 };
  const usda = {
    "energy-kcal_100g": 539,
    proteins_100g: 99, // OFF already has protein → must NOT overwrite
    fat_100g: 30.9,
    sugars_100g: 12, // OFF already has sugars → keep OFF
  };
  const { merged, filled } = mergeNutrients(off, usda);

  assertEquals(merged["proteins_100g"], 6.3, "OFF protein preserved");
  assertEquals(merged["sugars_100g"], 56.3, "OFF sugars preserved");
  assertEquals(merged["energy-kcal_100g"], 539, "USDA fills missing energy");
  assertEquals(merged["fat_100g"], 30.9, "USDA fills missing fat");
  assertEquals(filled.sort(), ["energy-kcal_100g", "fat_100g"]);
});

Deno.test("mergeNutrients treats non-finite OFF values as gaps to fill", () => {
  const off = { "energy-kcal_100g": null, fat_100g: NaN };
  const usda = { "energy-kcal_100g": 400, fat_100g: 10 };
  const { merged, filled } = mergeNutrients(off, usda);
  assertEquals(merged["energy-kcal_100g"], 400);
  assertEquals(merged["fat_100g"], 10);
  assertEquals(filled.sort(), ["energy-kcal_100g", "fat_100g"]);
});

Deno.test("mergeNutrients returns no filled keys when OFF already has everything", () => {
  const off = { "energy-kcal_100g": 500, proteins_100g: 10 };
  const usda = { "energy-kcal_100g": 999, proteins_100g: 999 };
  const { merged, filled } = mergeNutrients(off, usda);
  assertEquals(filled, []);
  assertEquals(merged["energy-kcal_100g"], 500);
});
