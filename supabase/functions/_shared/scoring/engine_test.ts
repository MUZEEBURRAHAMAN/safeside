/**
 * Scoring engine tests.
 *
 * The critical suite: every one of the 50 calibration products
 * (docs/Scoring_Calibration.xlsx → calibration.json) must reproduce its
 * expected sub-scores, final score, and band exactly. Plus edge cases the
 * calibration set does not cover (missing data, floor, per-tier penalties).
 *
 * No network, no DB — pure function tests.
 */

import {
  assertEquals,
  assertAlmostEquals,
} from "jsr:@std/assert@1";
import {
  type AdditiveTier,
  additivesSubScore,
  computeScore,
  roundHalfUp,
  SCORE_VERSION,
} from "./engine.ts";
import calibration from "./calibration.json" with { type: "json" };

interface CalibrationRow {
  id: number;
  product: string;
  input: {
    nova: number | null;
    nutriscore: string | null;
    additiveTiers: string[];
  };
  expected: {
    processing: number;
    nutrition: number;
    additives: number;
    score: number;
    band: string;
  };
}

function factor(output: ReturnType<typeof computeScore>, name: string) {
  const f = output.factors.find((f) => f.name === name);
  if (!f) throw new Error(`Missing factor: ${name}`);
  return f;
}

Deno.test("calibration: all 50 products match expected sub-scores, score, and band", () => {
  const rows = calibration as CalibrationRow[];
  assertEquals(rows.length, 50, "calibration set must have 50 rows");

  for (const row of rows) {
    const output = computeScore({
      novaGroup: row.input.nova,
      nutriscoreGrade: row.input.nutriscore,
      additiveTiers: row.input.additiveTiers as AdditiveTier[],
    });

    const label = `#${row.id} ${row.product}`;
    assertEquals(
      factor(output, "Processing").subScore,
      row.expected.processing,
      `${label}: processing sub-score`,
    );
    assertEquals(
      factor(output, "Nutrition").subScore,
      row.expected.nutrition,
      `${label}: nutrition sub-score`,
    );
    assertEquals(
      factor(output, "Additives").subScore,
      row.expected.additives,
      `${label}: additives sub-score`,
    );
    assertEquals(output.score, row.expected.score, `${label}: final score`);
    assertEquals(output.band, row.expected.band, `${label}: band`);
    assertEquals(
      output.confidence,
      "high",
      `${label}: full data → high confidence`,
    );
    assertEquals(output.scoreVersion, SCORE_VERSION, `${label}: version`);
  }
});

Deno.test("rounding is half-up (96.5 → 97)", () => {
  assertEquals(roundHalfUp(96.5), 97);
  assertEquals(roundHalfUp(96.4999), 96);
  assertEquals(roundHalfUp(41.6), 42); // the worked example in the methodology
  assertEquals(roundHalfUp(0.5), 1);
  assertEquals(roundHalfUp(0), 0);
});

Deno.test("weights on factors are 0.50 / 0.35 / 0.15 with full data", () => {
  const output = computeScore({
    novaGroup: 4,
    nutriscoreGrade: "c",
    additiveTiers: ["moderate", "low"],
  });
  assertEquals(factor(output, "Processing").weight, 0.5);
  assertEquals(factor(output, "Nutrition").weight, 0.35);
  assertEquals(factor(output, "Additives").weight, 0.15);
  // Methodology §6 worked example: 20/50/94 → 41.6 → 42 → low band.
  assertEquals(output.score, 42);
  assertEquals(output.band, "low");
});

Deno.test("empty additive list scores 100", () => {
  assertEquals(additivesSubScore([]), 100);
});

Deno.test("low-tier additives carry no penalty", () => {
  assertEquals(additivesSubScore(["low", "low", "low", "low"]), 100);
});

Deno.test("per-tier penalties: first vs additional within each tier", () => {
  // 1 moderate → −6
  assertEquals(additivesSubScore(["moderate"]), 94);
  // 2 moderate → −6 −3
  assertEquals(additivesSubScore(["moderate", "moderate"]), 91);
  // 1 higher → −15
  assertEquals(additivesSubScore(["higher"]), 85);
  // 2 higher → −15 −8 = 77 (each tier tracks its own first/additional)
  assertEquals(additivesSubScore(["higher", "higher"]), 77);
  // mixed: 1 higher (−15) + 2 moderate (−6 −3) + lows (0) → 76
  assertEquals(
    additivesSubScore(["higher", "moderate", "low", "moderate", "low"]),
    76,
  );
});

Deno.test("additives sub-score never drops below the floor of 30", () => {
  // 10 higher: 100 − (15 + 8×9) = 13 → floored at 30
  const many: AdditiveTier[] = Array(10).fill("higher");
  assertEquals(additivesSubScore(many), 30);
  // Piling on moderates too cannot pierce the floor
  assertEquals(additivesSubScore([...many, "moderate", "moderate"]), 30);
});

Deno.test("both NOVA and Nutri-Score missing → unknown band, null score, no factors", () => {
  const output = computeScore({
    novaGroup: null,
    nutriscoreGrade: null,
    additiveTiers: ["higher"],
  });
  assertEquals(output.score, null);
  assertEquals(output.band, "unknown");
  assertEquals(output.confidence, "limited");
  assertEquals(output.factors.length, 0);
  assertEquals(output.scoreVersion, SCORE_VERSION);
});

Deno.test("missing Nutri-Score → limited confidence, weights renormalized", () => {
  const output = computeScore({
    novaGroup: 1,
    nutriscoreGrade: null,
    additiveTiers: [],
  });
  assertEquals(output.confidence, "limited");
  assertEquals(output.factors.length, 2); // Processing + Additives only
  // 100 × (0.50/0.65) + 100 × (0.15/0.65) = 100
  assertEquals(output.score, 100);
  assertEquals(output.band, "high");
  const processing = output.factors.find((f) => f.name === "Processing")!;
  const additives = output.factors.find((f) => f.name === "Additives")!;
  assertAlmostEquals(processing.weight, 0.5 / 0.65, 0.001);
  assertAlmostEquals(additives.weight, 0.15 / 0.65, 0.001);
  // The renormalization is disclosed in the factor detail.
  assertEquals(processing.detail.includes("rebalanced"), true);
});

Deno.test("missing NOVA → limited confidence, computed from Nutri-Score + additives", () => {
  const output = computeScore({
    novaGroup: null,
    nutriscoreGrade: "e",
    additiveTiers: ["moderate"],
  });
  assertEquals(output.confidence, "limited");
  assertEquals(output.factors.length, 2); // Nutrition + Additives only
  // 12 × (0.35/0.50) + 94 × (0.15/0.50) = 8.4 + 28.2 = 36.6 → 37
  assertEquals(output.score, 37);
  assertEquals(output.band, "low");
});

Deno.test("band boundaries: 75+ high, 45–74 mid, below 45 low", () => {
  // NOVA 2 + nutri b: 0.5×80 + 0.35×70 + 0.15×100 = 79.5 → 80 high
  assertEquals(
    computeScore({ novaGroup: 2, nutriscoreGrade: "b", additiveTiers: [] })
      .band,
    "high",
  );
  // NOVA 3 + nutri c: 0.5×55 + 0.35×50 + 0.15×100 = 60 mid
  assertEquals(
    computeScore({ novaGroup: 3, nutriscoreGrade: "c", additiveTiers: [] })
      .band,
    "mid",
  );
  // NOVA 4 + nutri e: 0.5×20 + 0.35×12 + 0.15×100 = 29.2 → 29 low
  assertEquals(
    computeScore({ novaGroup: 4, nutriscoreGrade: "e", additiveTiers: [] })
      .band,
    "low",
  );
});

Deno.test("user-facing detail strings stay neutral (ED-safe language)", () => {
  const output = computeScore({
    novaGroup: 4,
    nutriscoreGrade: "e",
    additiveTiers: ["higher", "moderate"],
  });
  const banned = /\b(toxic|poison|dangerous|bad|junk|unhealthy|harmful)\b/i;
  for (const f of output.factors) {
    assertEquals(
      banned.test(f.detail),
      false,
      `factor "${f.name}" detail must stay neutral: "${f.detail}"`,
    );
  }
});
