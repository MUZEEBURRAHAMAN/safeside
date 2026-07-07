# AI Planner Spec

**Version:** 1.0 (draft for build) · June 2026
**Golden rule:** the LLM **selects and explains only**. It never computes nutrition and never invents a product. Every item it places already exists in our DB; every number shown is recomputed in code. (Evidence: LLM calorie estimates run 20–28% off — see Market Research.)

---

## 1. What the AI does
- **Fill the gaps:** complete empty meal slots around what the user already chose.
- **Improve this:** propose swaps on an existing plan as an accept/reject diff.
- It does **not** auto-apply changes — output is editable suggestions; the user's edits are source of truth.

---

## 2. Pipeline (LLM as planner, code as calculator)

```
1. Compute targets        (code) → Mifflin-St Jeor + activity, or qualitative goal
2. Retrieve candidates    (code) → pantry + product DB, filtered by hard constraints
3. LLM assembles          (LLM)  → picks items into slots, returns structured JSON (IDs only)
4. Verify & fix           (code) → recompute macros from DB; if off-target, re-prompt or OR-Tools/PuLP
5. Render                 (app)  → editable suggestions in the weekly grid
```

### Step 1 — Targets (code)
- Compute TDEE/macros via Mifflin-St Jeor when the user opted into numbers; otherwise use qualitative goals ("more protein", "less processed", "more variety"). Never surface a calorie number if `show_calories = false`.

### Step 2 — Retrieve candidates (code, the grounding step)
- Pull from the user's pantry first, then the broader scored product DB / recipes.
- **Hard filters applied here, never left to the prompt:** allergens, diet pattern, dislikes, and (if set) score threshold and protein-per-meal for GLP-1.
- Produce a candidate set of real items with `{id, name, meal_roles, macros, score, tags}`.

### Step 3 — LLM assembles (structured output)
- Use the Vercel AI SDK with a **Zod/JSON schema**; the model returns only references to candidate IDs + a short rationale. It cannot emit free-text foods or numbers.

```jsonc
// output schema (illustrative)
{
  "slots": [
    { "day": 0, "meal": "breakfast", "product_id": "uuid", "rationale": "high protein, in your pantry" }
  ],
  "notes": "string, optional, non-judgmental"
}
```

### Step 4 — Verify & fix (code)
- Recompute the assembled plan's nutrition from the DB.
- If targets/constraints are missed: (a) re-prompt with the specific gap, or (b) run an **OR-Tools / PuLP** solver over the candidate set to satisfy hard numeric constraints (the classic diet problem). Hybrid = LLM for variety/coherence, solver for hard numbers.
- Re-validate hard filters post-assembly (defense in depth) — drop any item that slipped through.

### Step 5 — Render
- Suggestions land in the grid as a diff (keep / swap / edit). Confirmation copy: "Suggested — you decide."

---

## 3. Prompt design

**System prompt (essentials):**
- Role: a calm, non-judgmental meal-planning assistant.
- You may ONLY choose from the provided candidate list (by id). Do not invent foods. Do not output calories or macros — only ids and a short rationale.
- Honor the user's goal framing; never use "good/bad/toxic/cheat" language; never shame.
- Prefer items already in the user's pantry; respect meal roles and variety; avoid repeating the same item across the week.

**User/context message:** profile goal + qualitative targets, meal structure, and the candidate set (compact). Existing slots when "improving".

---

## 4. Guardrails (ship-blocking)
- **Allergens/diet:** enforced in retrieval AND re-checked post-assembly. A forbidden item in output is a hard bug.
- **No hallucinated products:** any id not in the candidate set is rejected; regenerate.
- **No LLM numbers:** UI never displays a value the LLM produced; all from DB.
- **Tone:** filter output for banned words; reject/rewrite if present.
- **Cost/latency:** cap candidates (e.g. top N per meal role), set token budget, cache identical (profile+pantry+request) results.

---

## 5. Testing (mirror in TEST_PLAN.md)
- **Adversarial profiles:** vegan + nut allergy + low budget → assert zero violations across 100 generations.
- **Golden set:** fixed profiles → expected-shape plans; flag drift after prompt/model changes.
- **Determinism check:** numbers in UI always equal DB recompute (property test).
- **Fallback:** AI timeout/refusal → manual planner still works.

---

## 6. Privacy & safety
- Send the minimum context needed; no PII beyond dietary prefs. Don't send email/name.
- If a user sets extreme targets or signals distress, soften and avoid aggressive deficit planning; surface support resources (ED-safe stance).

## 7. Out of scope v1
- Photo→meal recognition, conversational chat planner, auto-grocery ordering. Add after the grounded fill/improve loop is solid.
