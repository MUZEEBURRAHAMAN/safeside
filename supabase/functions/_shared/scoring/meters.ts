/**
 * Nutrient highlights — the "Watch-outs" / "Benefits" bar-meters.
 *
 * Pure function, no I/O, no LLM (CLAUDE.md #5). This is the single place the
 * meter math lives: every meter value, unit, tier word, meter fraction, and
 * both pre-read counts are computed HERE from the already-stored per-100 g
 * `products.nutrients` (OFF/USDA macros) and returned ready-to-render. The
 * SwiftUI client only maps an enum tier → colour and renders the strings.
 *
 * Thresholds (cited, not invented — teardown AVOID #2 "every number sourced"):
 *  - Watch-outs (saturated fat / sugars / salt) use the UK FSA front-of-pack
 *    traffic-light 100 g thresholds (low ≤ / high >): sat fat 1.5 / 5.0,
 *    sugars 5.0 / 22.5, salt 0.3 / 1.5 g per 100 g. Reported to the user via
 *    Open Food Facts' nutrient levels, which apply the same FSA thresholds.
 *  - Benefits (fibre / protein) use the EU "source of" / "high in" nutrition-
 *    claim thresholds (fibre 3 / 6 g per 100 g), surfaced via the Nutri-Score
 *    nutrient model on Open Food Facts. Protein tiers subdivide the same way.
 *
 * ED-safe (CLAUDE.md #2): energy/calories are NEVER emitted here — the Result
 * screen must not surface calorie numbers. Tier words are neutral (no
 * "bad/toxic/junk"): watch-outs low/moderate/high, benefits low/some/good source.
 */

import type { AdditiveTier, ScoreSource } from "./engine.ts";

export type MeterKind = "watchOut" | "benefit";

export interface MeterRow {
  label: string; // "Saturated fat" | "Sugars" | "Salt" | "Fiber" | "Protein"
  value: number; // rounded ONCE to 1 dp, backend-owned
  unit: string; // "g"
  tier: string; // watch-outs: "low"|"moderate"|"high"; benefits: "low"|"some"|"good source"
  meterFraction: number; // 0..1, value / maxScale, clamped — backend-owned
  kind: MeterKind;
  sources: ScoreSource[];
}

export interface NutrientHighlights {
  watchOuts: MeterRow[];
  benefits: MeterRow[];
  toKnowAboutCount: number;
  beneficialCount: number;
}

/** salt (g) = sodium (g) × 2.5 — mirrors _shared/usda.ts SALT_PER_SODIUM. */
const SALT_PER_SODIUM = 2.5;

const FSA_SOURCES: ScoreSource[] = [
  {
    name: "FSA nutrient thresholds (via Open Food Facts)",
    url: "https://world.openfoodfacts.org/nutriscore",
  },
];

const NUTRISCORE_SOURCES: ScoreSource[] = [
  {
    name: "Nutri-Score nutrient model (via Open Food Facts)",
    url: "https://world.openfoodfacts.org/nutriscore",
  },
];

interface Tier {
  /** Inclusive upper bound (on the DISPLAY value); last tier uses Infinity. */
  upTo: number;
  word: string;
}

interface NutrientSpec {
  /** OFF/USDA per-100 g key(s), tried in order (first finite number wins). */
  keys: string[];
  label: string;
  kind: MeterKind;
  unit: string;
  /** "Full bar" reference — the value at which meterFraction reaches 1. */
  maxScale: number;
  tiers: Tier[];
  sources: ScoreSource[];
  /** Optional transform on the raw value before rounding (e.g. sodium→salt). */
  transform?(raw: number, key: string): number;
}

// Watch-outs first, then benefits — this is the render order.
const NUTRIENT_SPECS: NutrientSpec[] = [
  {
    keys: ["saturated-fat_100g"],
    label: "Saturated fat",
    kind: "watchOut",
    unit: "g",
    maxScale: 5.0, // FSA "high" boundary → a high value fills the bar
    tiers: [{ upTo: 1.5, word: "low" }, { upTo: 5.0, word: "moderate" }, {
      upTo: Infinity,
      word: "high",
    }],
    sources: FSA_SOURCES,
  },
  {
    keys: ["sugars_100g"],
    label: "Sugars",
    kind: "watchOut",
    unit: "g",
    maxScale: 22.5, // FSA "high" boundary
    tiers: [{ upTo: 5.0, word: "low" }, { upTo: 22.5, word: "moderate" }, {
      upTo: Infinity,
      word: "high",
    }],
    sources: FSA_SOURCES,
  },
  {
    // Prefer the label's salt figure; fall back to sodium × 2.5.
    keys: ["salt_100g", "sodium_100g"],
    label: "Salt",
    kind: "watchOut",
    unit: "g",
    maxScale: 1.5, // FSA "high" boundary
    tiers: [{ upTo: 0.3, word: "low" }, { upTo: 1.5, word: "moderate" }, {
      upTo: Infinity,
      word: "high",
    }],
    sources: FSA_SOURCES,
    transform: (raw, key) => (key === "sodium_100g" ? raw * SALT_PER_SODIUM : raw),
  },
  {
    keys: ["fiber_100g"],
    label: "Fiber",
    kind: "benefit",
    unit: "g",
    maxScale: 6.0, // EU "high in fibre" boundary → a rich source fills the bar
    tiers: [{ upTo: 1.5, word: "low" }, { upTo: 3.0, word: "some" }, {
      upTo: Infinity,
      word: "good source",
    }],
    sources: NUTRISCORE_SOURCES,
  },
  {
    keys: ["proteins_100g"],
    label: "Protein",
    kind: "benefit",
    unit: "g",
    maxScale: 12.0,
    tiers: [{ upTo: 3.2, word: "low" }, { upTo: 8.0, word: "some" }, {
      upTo: Infinity,
      word: "good source",
    }],
    sources: NUTRISCORE_SOURCES,
  },
];

/** HALF-UP rounding to 1 dp, applied exactly once (mirrors engine.roundHalfUp). */
function roundHalfUp1dp(x: number): number {
  return Math.floor(x * 10 + 0.5) / 10;
}

function clamp01(x: number): number {
  return Math.max(0, Math.min(1, x));
}

function isFiniteNumber(v: unknown): v is number {
  return typeof v === "number" && Number.isFinite(v);
}

/** First tier whose (inclusive) upper bound covers the display value. */
function tierWord(displayValue: number, tiers: Tier[]): string {
  for (const t of tiers) {
    if (displayValue <= t.upTo) return t.word;
  }
  return tiers[tiers.length - 1].word;
}

function buildRow(spec: NutrientSpec, nutrients: Record<string, unknown>): MeterRow | null {
  for (const key of spec.keys) {
    const raw = nutrients[key];
    if (!isFiniteNumber(raw)) continue;
    const transformed = spec.transform ? spec.transform(raw, key) : raw;
    const value = roundHalfUp1dp(transformed);
    return {
      label: spec.label,
      value,
      unit: spec.unit,
      tier: tierWord(value, spec.tiers), // classify on the DISPLAY value
      meterFraction: Math.round(clamp01(value / spec.maxScale) * 1000) / 1000,
      kind: spec.kind,
      sources: spec.sources,
    };
  }
  return null; // no finite source key → skip (never a phantom 0 g row)
}

/**
 * Build the Watch-outs / Benefits meter rows + the pre-read counts from the
 * stored per-100 g nutrients and the product's additive tiers. Deterministic.
 */
export function buildNutrientHighlights(
  nutrients: Record<string, unknown>,
  additiveTiers: AdditiveTier[],
): NutrientHighlights {
  const watchOuts: MeterRow[] = [];
  const benefits: MeterRow[] = [];

  for (const spec of NUTRIENT_SPECS) {
    const row = buildRow(spec, nutrients);
    if (!row) continue;
    (row.kind === "watchOut" ? watchOuts : benefits).push(row);
  }

  const beneficialCount =
    benefits.filter((r) => r.tier === "good source" || r.tier === "high").length;
  const toKnowAboutCount =
    additiveTiers.filter((t) => t === "moderate" || t === "higher").length;

  return { watchOuts, benefits, toKnowAboutCount, beneficialCount };
}
