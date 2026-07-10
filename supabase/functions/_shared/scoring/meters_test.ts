/**
 * Nutrient-highlights builder tests — pure, offline, no I/O.
 *
 * meters.ts is the single place the meter "math" lives (CLAUDE.md #5). These
 * tests lock the FSA/Nutri-Score-aligned thresholds, the round-once rule, and
 * the "thin data never fabricates a meter" behaviour.
 */

import { assert, assertEquals } from "jsr:@std/assert@1";
import type { AdditiveTier } from "./engine.ts";
import { buildNutrientHighlights, type MeterRow } from "./meters.ts";

function rowByLabel(rows: MeterRow[], label: string): MeterRow {
  const r = rows.find((x) => x.label === label);
  assert(r, `expected a "${label}" row`);
  return r!;
}

Deno.test("thin data never fabricates a meter", () => {
  const h = buildNutrientHighlights({}, []);
  assertEquals(h.watchOuts, []);
  assertEquals(h.benefits, []);
  assertEquals(h.toKnowAboutCount, 0);
  assertEquals(h.beneficialCount, 0);
});

Deno.test("high fat/sugar/salt fixture → three watch-out rows, rounded once", () => {
  const h = buildNutrientHighlights(
    { "saturated-fat_100g": 26.7, sugars_100g: 40, salt_100g: 1.8 },
    [],
  );
  assertEquals(h.watchOuts.length, 3);
  assertEquals(h.benefits.length, 0);

  const satFat = rowByLabel(h.watchOuts, "Saturated fat");
  assertEquals(satFat.value, 26.7, "value rounded once, no float dust");
  assertEquals(satFat.unit, "g");
  assertEquals(satFat.tier, "high");
  assertEquals(satFat.kind, "watchOut");
  assert(satFat.meterFraction >= 0 && satFat.meterFraction <= 1);
  assert(satFat.sources.length > 0 && satFat.sources[0].name.length > 0);

  assertEquals(rowByLabel(h.watchOuts, "Sugars").tier, "high");
  assertEquals(rowByLabel(h.watchOuts, "Salt").tier, "high");
});

Deno.test("good fiber/protein fixture → benefit rows + beneficialCount", () => {
  const h = buildNutrientHighlights({ fiber_100g: 4.5, proteins_100g: 12 }, []);
  assertEquals(h.watchOuts.length, 0);
  assertEquals(h.benefits.length, 2);

  const fiber = rowByLabel(h.benefits, "Fiber");
  assertEquals(fiber.value, 4.5);
  assertEquals(fiber.unit, "g");
  assertEquals(fiber.tier, "good source");
  assertEquals(fiber.kind, "benefit");

  const protein = rowByLabel(h.benefits, "Protein");
  assertEquals(protein.tier, "good source");

  // beneficialCount = benefit rows at the positive ("good source") tier.
  assertEquals(h.beneficialCount, 2);
});

Deno.test("watch-out tiers flip exactly at the (rounded) threshold", () => {
  // Saturated fat FSA: low ≤1.5, moderate ≤5.0, else high.
  assertEquals(
    buildNutrientHighlights({ "saturated-fat_100g": 1.5 }, []).watchOuts[0].tier,
    "low",
  );
  assertEquals(
    buildNutrientHighlights({ "saturated-fat_100g": 1.6 }, []).watchOuts[0].tier,
    "moderate",
  );
  assertEquals(
    buildNutrientHighlights({ "saturated-fat_100g": 5.0 }, []).watchOuts[0].tier,
    "moderate",
  );
  assertEquals(
    buildNutrientHighlights({ "saturated-fat_100g": 5.1 }, []).watchOuts[0].tier,
    "high",
  );
  // A raw value that rounds down to the boundary keeps the lower tier
  // (classify on the display value, not the raw float).
  assertEquals(
    buildNutrientHighlights({ "saturated-fat_100g": 1.54 }, []).watchOuts[0].tier,
    "low",
  );

  // Salt FSA: low ≤0.3, moderate ≤1.5, else high.
  assertEquals(
    buildNutrientHighlights({ salt_100g: 0.3 }, []).watchOuts[0].tier,
    "low",
  );
  assertEquals(
    buildNutrientHighlights({ salt_100g: 1.6 }, []).watchOuts[0].tier,
    "high",
  );
});

Deno.test("benefit tiers flip at the (rounded) threshold", () => {
  // Fiber: low ≤1.5, some ≤3.0, else good source.
  assertEquals(buildNutrientHighlights({ fiber_100g: 1.5 }, []).benefits[0].tier, "low");
  assertEquals(buildNutrientHighlights({ fiber_100g: 3.0 }, []).benefits[0].tier, "some");
  assertEquals(
    buildNutrientHighlights({ fiber_100g: 3.1 }, []).benefits[0].tier,
    "good source",
  );
});

Deno.test("salt derived from sodium when salt_100g is absent", () => {
  // sodium 0.72 g → salt 0.72 × 2.5 = 1.8 g.
  const h = buildNutrientHighlights({ sodium_100g: 0.72 }, []);
  const salt = rowByLabel(h.watchOuts, "Salt");
  assertEquals(salt.value, 1.8);
  assertEquals(salt.unit, "g");
  assertEquals(salt.tier, "high");
});

Deno.test("salt_100g wins over sodium_100g when both present", () => {
  const h = buildNutrientHighlights({ salt_100g: 0.2, sodium_100g: 5 }, []);
  const salt = rowByLabel(h.watchOuts, "Salt");
  assertEquals(salt.value, 0.2);
  assertEquals(salt.tier, "low");
});

Deno.test("toKnowAboutCount counts moderate+higher additive tiers, independent of nutrients", () => {
  const tiers: AdditiveTier[] = ["low", "moderate", "higher", "low", "moderate"];
  const h = buildNutrientHighlights({}, tiers);
  assertEquals(h.toKnowAboutCount, 3);
  // No nutrients → still no meters.
  assertEquals(h.watchOuts, []);
  assertEquals(h.benefits, []);
});

Deno.test("energy/calories are never emitted as a meter (ED-safe)", () => {
  const h = buildNutrientHighlights(
    { "energy-kcal_100g": 539, energy_100g: 2255 },
    [],
  );
  assertEquals(h.watchOuts, []);
  assertEquals(h.benefits, []);
  assert(!h.watchOuts.some((r) => /energy|cal/i.test(r.label)));
});

Deno.test("missing / non-numeric keys are skipped, never emitted as 0 g", () => {
  const h = buildNutrientHighlights(
    { "saturated-fat_100g": "n/a", sugars_100g: null, salt_100g: 1.8, fiber_100g: 4.5 },
    [],
  );
  assertEquals(h.watchOuts.map((r) => r.label), ["Salt"]);
  assertEquals(h.benefits.map((r) => r.label), ["Fiber"]);
});
