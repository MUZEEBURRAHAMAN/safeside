/**
 * Deterministic scoring engine — implements docs/SCORING_METHODOLOGY.md v1.
 *
 * Pure function, no I/O, no LLM. Every number shown to the user is computed
 * here from data; the LLM only ever explains, never calculates.
 *
 * Composite = 0.50 * Processing + 0.35 * Nutrition + 0.15 * Additives
 *
 * Language rule (ED-safe): all `detail` strings are neutral and descriptive.
 * Never "bad", "toxic", "dangerous", "junk" — say "higher-processed",
 * "moderate-concern additive", etc.
 */

import weights from "./weights.json" with { type: "json" };

// Bumped 1.0.0 → 1.1.0 when additives_risk.json grew to v1.1 (more reviewed
// E-numbers). The cache treats older-version scores as stale and re-scores on
// next fetch, so products with newly-reviewed additives pick up the change.
export const SCORE_VERSION = "1.1.0";

export type AdditiveTier = "low" | "moderate" | "higher";

export interface ScoreInput {
  novaGroup: number | null;
  nutriscoreGrade: string | null;
  additiveTiers: AdditiveTier[];
}

export interface ScoreSource {
  name: string;
  url: string | null;
}

export interface ScoreFactor {
  name: string; // exactly "Processing" | "Nutrition" | "Additives"
  subScore: number; // 0–100
  weight: number; // weight actually used in the composite (renormalized if data is partial)
  detail: string; // plain-language, neutral
  sources: ScoreSource[];
}

export type ScoreBand = "high" | "mid" | "low" | "unknown";
export type Confidence = "high" | "limited";

export interface ScoreOutput {
  score: number | null; // null when band is "unknown"
  band: ScoreBand;
  confidence: Confidence;
  scoreVersion: string;
  factors: ScoreFactor[];
}

/**
 * HALF-UP rounding, made explicit.
 *
 * The final score must round 96.5 → 97 (half-up), matching the calibration
 * spreadsheet. JS `Math.round` is half-up for positive numbers (it rounds
 * half toward +Infinity), so it would be correct for our always-≥0 scores —
 * but we use `Math.floor(x + 0.5)` to make the intent unmistakable and
 * independent of sign, and to guard against anyone swapping in a
 * banker's-rounding helper later.
 */
export function roundHalfUp(x: number): number {
  return Math.floor(x + 0.5);
}

const NOVA_LABELS: Record<number, string> = {
  1: "unprocessed or minimally processed",
  2: "processed culinary ingredient",
  3: "processed food",
  4: "ultra-processed food",
};

const PROCESSING_SOURCES: ScoreSource[] = [
  {
    name: "NOVA classification (via Open Food Facts)",
    url: "https://world.openfoodfacts.org/nova",
  },
];

const NUTRITION_SOURCES: ScoreSource[] = [
  {
    name: "Nutri-Score nutrient model (via Open Food Facts)",
    url: "https://world.openfoodfacts.org/nutriscore",
  },
];

const ADDITIVES_SOURCES: ScoreSource[] = [
  {
    name: "Curated additive review table v1.0 (EFSA / FDA / JECFA reviews)",
    url: null,
  },
];

function bandFor(score: number): ScoreBand {
  if (score >= 75) return "high";
  if (score >= 45) return "mid";
  return "low";
}

/** Processing sub-score from NOVA group (1→100, 2→80, 3→55, 4→20). */
function processingSubScore(novaGroup: number): number {
  const mapped =
    weights.novaToProcessing[
      String(novaGroup) as keyof typeof weights.novaToProcessing
    ];
  if (mapped === undefined) {
    throw new Error(`Unsupported NOVA group: ${novaGroup}`);
  }
  return mapped;
}

/** Nutrition sub-score from Nutri-Score grade (a/b/c/d/e → 90/70/50/30/12). */
function nutritionSubScore(grade: string): number {
  const mapped =
    weights.nutriToNutrition[
      grade.toLowerCase() as keyof typeof weights.nutriToNutrition
    ];
  if (mapped === undefined) {
    throw new Error(`Unsupported Nutri-Score grade: ${grade}`);
  }
  return mapped;
}

/**
 * Additives sub-score. Start at 100; penalties are applied PER TIER with a
 * "first / each additional" structure inside that tier:
 *   moderate: −6 for the first, −3 for each additional moderate additive
 *   higher:   −15 for the first, −8 for each additional higher additive
 *   low:      0 (no penalty)
 * Floored at 30 — no single additive (or pile of them) tanks the score.
 * This is the explicit anti-fear-based design decision.
 */
export function additivesSubScore(tiers: AdditiveTier[]): number {
  const counts: Record<AdditiveTier, number> = { low: 0, moderate: 0, higher: 0 };
  for (const tier of tiers) counts[tier]++;

  let score = 100;
  for (const tier of ["low", "moderate", "higher"] as const) {
    const count = counts[tier];
    if (count === 0) continue;
    const penalty = weights.additivePenalties[tier];
    score -= penalty.first + penalty.additional * (count - 1);
  }
  return Math.max(score, weights.additiveFloor);
}

function additivesDetail(tiers: AdditiveTier[]): string {
  if (tiers.length === 0) {
    return "No additives listed for this product.";
  }
  const counts: Record<AdditiveTier, number> = { low: 0, moderate: 0, higher: 0 };
  for (const tier of tiers) counts[tier]++;

  const parts: string[] = [];
  if (counts.higher > 0) {
    parts.push(
      `${counts.higher} higher-concern additive${counts.higher > 1 ? "s" : ""}`,
    );
  }
  if (counts.moderate > 0) {
    parts.push(
      `${counts.moderate} moderate-concern additive${counts.moderate > 1 ? "s" : ""}`,
    );
  }
  if (counts.low > 0) {
    parts.push(
      `${counts.low} lower-concern additive${counts.low > 1 ? "s" : ""}`,
    );
  }
  const summary = `${tiers.length} additive${tiers.length > 1 ? "s" : ""} reviewed: ${parts.join(", ")}.`;
  return `${summary} Penalties are tiered and capped so no single additive dominates the score.`;
}

/**
 * Compute the composite score.
 *
 * Missing-data policy (documented here and surfaced in factor details):
 * - Both NOVA and Nutri-Score missing → band "unknown", score null, no
 *   factors. We never fabricate a precise number from thin data.
 * - Exactly one of the two missing → compute from what we have, and
 *   RENORMALIZE the remaining weights so they sum to 1. For example, with
 *   Nutri-Score missing, Processing 0.50 and Additives 0.15 renormalize to
 *   0.769 and 0.231. Confidence drops to "limited" and each factor's detail
 *   says so. Rationale: partial data should soften confidence, not silently
 *   deflate or inflate the score by leaving weight on a zeroed component.
 * - Otherwise confidence is "high".
 */
export function computeScore(input: ScoreInput): ScoreOutput {
  const hasNova = input.novaGroup !== null && input.novaGroup !== undefined;
  const hasNutri =
    input.nutriscoreGrade !== null &&
    input.nutriscoreGrade !== undefined &&
    input.nutriscoreGrade !== "";

  // Not enough data → no numeric score at all.
  if (!hasNova && !hasNutri) {
    return {
      score: null,
      band: "unknown",
      confidence: "limited",
      scoreVersion: SCORE_VERSION,
      factors: [],
    };
  }

  const confidence: Confidence = hasNova && hasNutri ? "high" : "limited";

  // Sub-scores for available components.
  const components: {
    name: string;
    subScore: number;
    baseWeight: number;
    detail: string;
    sources: ScoreSource[];
  }[] = [];

  if (hasNova) {
    const nova = input.novaGroup as number;
    const sub = processingSubScore(nova);
    components.push({
      name: "Processing",
      subScore: sub,
      baseWeight: weights.composite.processing,
      detail: `NOVA group ${nova} (${NOVA_LABELS[nova]}).`,
      sources: PROCESSING_SOURCES,
    });
  }

  if (hasNutri) {
    const grade = (input.nutriscoreGrade as string).toLowerCase();
    const sub = nutritionSubScore(grade);
    components.push({
      name: "Nutrition",
      subScore: sub,
      baseWeight: weights.composite.nutrition,
      detail: `Nutri-Score ${grade.toUpperCase()} maps to ${sub} out of 100 in our nutrient model.`,
      sources: NUTRITION_SOURCES,
    });
  }

  // Additives are always computable (an empty list scores 100).
  components.push({
    name: "Additives",
    subScore: additivesSubScore(input.additiveTiers),
    baseWeight: weights.composite.additives,
    detail: additivesDetail(input.additiveTiers),
    sources: ADDITIVES_SOURCES,
  });

  // Renormalize weights across available components (no-op when all present).
  const totalWeight = components.reduce((sum, c) => sum + c.baseWeight, 0);
  const missingNote = !hasNova
    ? "Processing data was unavailable, so remaining weights were rebalanced."
    : !hasNutri
      ? "Nutrition data was unavailable, so remaining weights were rebalanced."
      : null;

  let composite = 0;
  const factors: ScoreFactor[] = components.map((c) => {
    const effectiveWeight = c.baseWeight / totalWeight;
    composite += c.subScore * effectiveWeight;
    return {
      name: c.name,
      subScore: c.subScore,
      // Rounded for display; the composite above uses the exact value. The
      // rounding error (< 0.0005 per weight) cannot move a half-up-rounded
      // 0–100 score.
      weight: Math.round(effectiveWeight * 1000) / 1000,
      detail: missingNote ? `${c.detail} ${missingNote}` : c.detail,
      sources: c.sources,
    };
  });

  const score = roundHalfUp(composite);

  return {
    score,
    band: bandFor(score),
    confidence,
    scoreVersion: SCORE_VERSION,
    factors,
  };
}
