# Scoring Methodology Spec

**Version:** 1.0 (draft for build) · June 2026
**Status:** Defines the v1 transparent score. This is the product's moat — it must be defensible, sourced, dose-aware, and never fear-based.
**Owner principle:** every number we show is computed in code from data (never by an LLM), and every point of the score can be explained with a source.

---

## 1. Goals & non-goals

**Goals**
- A single, legible 0–100 score the user can grasp instantly, that **expands into its exact components**.
- Defensible against the dietitian critiques aimed at Yuka/Bobby Approved: no hazard-vs-risk confusion, no cherry-picked studies, no automatic "organic" bonus, no single additive capping the score.
- Dose-aware (amount matters, not mere presence) and **confidence-graded** (we say when data is thin).

**Non-goals**
- Not a medical or diagnostic score. Not a calorie/weight judgment. Not a moral verdict on the person.

---

## 2. Score at a glance

- **Range:** 0–100. **Higher = lower-processed / better nutritional profile.**
- **Bands** (map to `DESIGN_SYSTEM.md` score colors, deliberately non-alarmist):
  - 75–100 → "Lower-processed" (`score.high`)
  - 45–74 → "Moderately processed" (`score.mid`)
  - 0–44 → "Higher-processed" (`score.low`)
  - insufficient data → "Not enough data" (`score.unknown`), no numeric score shown
- The headline is always paired with the **word label + icon** (three redundant signals for accessibility).

---

## 3. Inputs (all from data, never the LLM)

| Input | Source | Notes |
|---|---|---|
| Processing level (NOVA 1–4) | Open Food Facts `nova_group` | If missing, derive from ingredient analysis or mark low confidence |
| Nutrient profile | Nutri-Score components from OFF; macros/micros from USDA FDC | sugar, sat fat, salt, energy vs. fiber, protein, fruit/veg/legume |
| Additives | OFF `additives_tags` + our curated risk table (see §5) | risk tier + count, dose-aware where data exists |
| Serving size | OFF / USDA | anchors dose reasoning |
| Allergens | OFF `allergens_tags` | feeds restrictions, not the score |
| Data completeness | computed | drives confidence (§7) |

> We read OFF's precomputed `nova_group` and `nutriscore` rather than reimplementing them; we compute **our own composite** on top. Do not copy AGPL OFF server code — use the API values.

---

## 4. The composite formula (v1)

The score is a weighted blend of three sub-scores, each 0–100. Weights are explicit and shown to the user.

```
Score = 0.50 * Processing
      + 0.35 * Nutrition
      + 0.15 * Additives
```

### 4.1 Processing sub-score (weight 0.50)
Maps NOVA group to a base, because "how processed" is our core promise:

| NOVA | Meaning | Processing sub-score |
|---|---|---|
| 1 | Unprocessed / minimally processed | 100 |
| 2 | Processed culinary ingredients | 80 |
| 3 | Processed foods | 55 |
| 4 | Ultra-processed | 20 |

If `nova_group` is absent, infer from ingredient markers (e.g. presence of cosmetic additives, protein isolates, hydrogenated oils) and **cap confidence at "Limited"**.

### 4.2 Nutrition sub-score (weight 0.35)
Derive from the Nutri-Score nutrient model (current 2023/2025 rules), normalized to 0–100 (A→~90, B→~70, C→~50, D→~30, E→~12). Where USDA macros are richer than OFF, prefer USDA. This rewards genuinely better nutrient profiles and prevents "sugary cereal beats cheese" anomalies from dominating, because processing is also weighted.

### 4.3 Additives sub-score (weight 0.15) — dose-aware, NOT fear-based
- Start at 100; subtract per additive by **risk tier**, with diminishing penalties (no single additive tanks the score):

| Tier | Definition (our curated table) | Penalty (first) | Each additional |
|---|---|---|---|
| Low concern | Common, broadly recognized safe (e.g. many colors from fruit, ascorbic acid) | 0 | 0 |
| Moderate | Some regulatory/intake caution; ADI exists | −6 | −3 |
| Higher concern | Restricted in some regions / under active review | −15 | −8 |

- **Dose awareness:** where the product lists quantity or the additive is below its regulatory ADI for a normal serving, reduce the penalty by half and note it.
- **Floor:** additives sub-score never below 30 (one additive ≠ "poison"). This is the explicit anti-Yuka decision.
- The curated risk table is maintained in data (versioned), each entry citing a **named regulatory source** (EFSA/FDA/IARC), never a single blog or cherry-picked study.

---

## 5. Additive risk table (governance)

- Stored as versioned data (`additives_risk.json`), not hardcoded.
- Each entry: `e_number`, `name`, `tier`, `reason` (plain language), `sources[]` (regulatory), `adi` (if known), `last_reviewed`.
- Tiering rule: classify by **risk** (real-world exposure vs. ADI), not **hazard** (theoretical). This is the core methodological stance that survives dietitian scrutiny.
- Changes are logged; the score version increments when the table changes (§8).

---

## 6. Worked example (must match the "why this score" UI)

Product: a packaged flavored yogurt.
- NOVA 4 → Processing = 20 → ×0.50 = 10.0
- Nutri-Score C → Nutrition ≈ 50 → ×0.35 = 17.5
- 2 additives: 1 moderate (−6), 1 low (0) → Additives = 94, but floor/dose noted → ×0.15 = 14.1
- **Score = 41.6 → 42 → "Higher-processed"**
- "Why" screen shows: Processing 20/100 (NOVA 4, 50% weight), Nutrition 50/100 (Nutri-Score C, 35% weight), Additives 94/100 (1 moderate additive, 15% weight), each with its source and confidence.

---

## 7. Confidence

- Compute `confidence` = High / Limited based on data completeness (NOVA present? nutrient table complete? additives parsed? serving known?).
- "Limited" shows a chip and softens claims ("based on partial data"). Never fabricate a precise score from thin data — show "Not enough data" if below threshold (e.g. no NOVA AND no nutrient table).

---

## 8. Versioning & transparency surface

- `score_version` stored on every computed result so historical scores are reproducible and re-explainable.
- Public **Methodology page** in-app (and ideally on the website) explains the formula and weights in plain language — this transparency is the marketing, not just compliance.
- When weights or the additive table change, increment `score_version` and note it in `MEMORY.md` / changelog.

---

## 9. What we deliberately do NOT do
- No automatic "organic" bonus (the critique that flags an app as non-evidence-based).
- No single additive capping the total (Yuka's 49-cap).
- No "toxic/poison/clean" language anywhere near the score.
- No hazard-based scaremongering; risk- and dose-based only.
- No LLM involvement in computing the number.

---

## 10. Open decisions to validate
- Exact weight tuning (0.50/0.35/0.15) — pressure-test against ~50 common products with a dietitian review.
- Nutri-Score→0–100 mapping curve.
- Additive penalty magnitudes — calibrate so results feel fair to the Skeptical Optimizer persona.
- Whether to expose a user-adjustable weighting ("I care more about additives") in a later version.
