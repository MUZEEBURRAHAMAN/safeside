# AI Ingredient Explanation Spec

**Version:** 1.0 (draft for build) · June 2026
**Why this is critical:** this is the MVP's headline AI feature and its single biggest **credibility risk**. If the AI invents science or fear-mongers, we become the thing we're positioned against (ChemZero/Bobby Approved). The rule that makes or breaks the product: **the AI explains from a real, cited knowledge base — it never invents facts, safety claims, or studies.**
**Reads with:** `SCORING_METHODOLOGY.md` (the score is separate & deterministic), `BACKEND_SPEC.md`, `COPY_DECK.md` (voice).

---

## 1. What the feature does
For each ingredient in a scanned product, show: **what it is, why it's used, safety (dose- and risk-based), who should avoid it, common misconceptions, foods that contain it.** Plain language, calm, sourced. (Per the MVP scope in `MASTER_PLAN.md`.)

## 2. The core principle: retrieval, not generation
The LLM does **not** answer from its own memory. It **rewrites vetted facts** we retrieve for the specific ingredient. No knowledge-base entry → no confident claim (we say "limited info").

```
ingredient tag (from OFF)
   → look up in our Ingredient Knowledge Base (KB)
   → retrieve vetted facts + sources
   → LLM rewrites them in plain, calm language (no new facts)
   → cache the explanation
```

## 3. The Ingredient Knowledge Base (the asset to build)
A curated, versioned dataset — the source of truth. Sourced from **authoritative references only**, never blogs or single cherry-picked studies.

**Sources (in priority):**
- **Additives / E-numbers:** Open Food Facts additives taxonomy + regulatory bodies (EFSA, US FDA, JECFA/WHO, IARC classifications). Same table that feeds `SCORING_METHODOLOGY.md` §5.
- **Nutrients & common ingredients:** USDA FoodData Central; established nutrition references.
- **Safety/ADI:** regulatory ADI values where they exist.

**KB entry schema (`ingredient_kb`):**
```jsonc
{
  "id": "e621",
  "names": ["Monosodium glutamate","MSG","E621"],
  "what": "A flavour enhancer (the sodium salt of glutamic acid).",
  "why_used": "Adds savoury/umami taste.",
  "safety": "Considered safe at typical intakes by EFSA/FDA; an ADI exists.",
  "risk_tier": "moderate",          // matches scoring table
  "who_should_avoid": ["people advised to limit sodium"],
  "misconceptions": ["'MSG allergy' is not supported by controlled studies"],
  "found_in": ["savoury snacks","seasonings","soups"],
  "sources": [{"name":"EFSA re-evaluation 2017","url":"..."}],
  "confidence": "high",
  "last_reviewed": "2026-05",
  "kb_version": "1.0"
}
```
- Start with the **~200–300 most common additives + common ingredients** (covers the long tail of scans). Expand over time.
- Governance: every claim cites a named regulatory source; risk is **risk-based (real exposure vs ADI), not hazard-based**. Changes bump `kb_version`.

## 4. LLM role & prompt (strictly bounded)
- **Input to the LLM:** the retrieved KB entry (or entries) + the user's profile flags (allergies, conditions) for relevance — nothing else.
- **Output:** a plain-language rewrite of the retrieved fields + a personalized relevance note. It may reorder/simplify; it may **not** add facts, numbers, studies, or safety verdicts not in the KB.
- **System prompt essentials:**
  - "Explain ONLY from the provided facts. If a field is missing, say info is limited — do not fill gaps from your own knowledge."
  - "Never use 'toxic/poison/dangerous/clean/cheat'. Calm, neutral, non-shaming (see voice guide)."
  - "Risk- and dose-aware: presence ≠ harm. Don't imply danger the sources don't support."
  - "Personalize: if the user flags an allergy/condition the ingredient is relevant to, note it plainly; otherwise don't invent relevance."
- **Structured output:** return JSON fields (`what, whyUsed, safety, whoShouldAvoid, misconceptions, foundIn, sources[]`) so the UI renders consistently and sources are always attached.

## 5. Guardrails (ship-blocking)
- **No KB entry → no explanation.** Show "We don't have vetted info on this ingredient yet" + let user report. Never let the LLM free-style an unknown ingredient.
- **Sources always shown.** Every explanation surfaces its citations + a confidence chip (mirrors the scoring transparency).
- **Banned-word filter** on output; reject/rewrite if it slips.
- **No medical advice.** Personalization is informational ("contains milk, which you flagged"), never diagnosis/treatment. "Not medical advice" disclaimer.
- **Determinism where it matters:** the `risk_tier` shown must equal the scoring table's tier (one source of truth) — the LLM can't upgrade/downgrade risk.

## 6. Caching & cost
- Explanations are per-ingredient and stable → **cache aggressively** (`ingredient_explanations` keyed by ingredient id + kb_version + locale). Personalization note is a light, separate layer so the base explanation stays cacheable.
- Result: most scans cost ~$0 in AI (cache hits); LLM only runs for new ingredients or new locales.

## 7. Testing (mirror in TEST_PLAN)
- **No-hallucination test:** feed an ingredient with a deliberately sparse KB entry; assert the output adds no facts beyond the entry.
- **Banned-language test:** assert no fear words in a large sample.
- **Risk-consistency test:** displayed tier == scoring table tier, always.
- **Unknown-ingredient test:** returns the "limited info" state, never a fabricated explanation.
- **Golden set:** fixed ingredients → expected explanations; flag drift after prompt/model/KB changes.

## 8. Build order
1. Seed `ingredient_kb` with additives (reuse the scoring additives table) + top common ingredients.
2. Retrieval + caching in the `/product/:id/ingredients` endpoint.
3. LLM rewrite layer with the bounded prompt + structured output.
4. Guardrail tests before it ships.

## 9. Open decisions
- Exact KB size at launch (200 vs 500 entries) — start with additives + top ingredients by scan frequency.
- Whether to RAG over a larger reference corpus later vs. keep the curated KB (curated is safer for credibility; revisit at scale).
- Localization of explanations (cache per locale).
