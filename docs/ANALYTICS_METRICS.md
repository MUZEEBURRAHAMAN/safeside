# Analytics & Metrics Plan

**Version:** 1.0 (draft for build) · June 2026
**Principle:** measure the loop, not vanity. The thesis is scan→pantry→plan→shop→scan; instrument it so you can see where users drop. Privacy-respecting; no selling data.

---

## 1. North-star & guardrail metrics
- **North star:** weekly active users who complete the loop (scan → add to a plan) — proves the connected value, not just scanning.
- **Guardrails (don't win one by hurting these):** crash-free rate, refund/cancel rate, support-ticket rate, 1-star review rate.

## 2. Funnel (activation)
1. Install → onboarding complete
2. → first scan
3. → first "why this score" expand (trust signal)
4. → first pantry item saved (auto)
5. → first plan slot filled (loop closed)
6. → first shopping list generated
7. → trial start → paid conversion

Track conversion at each step; the biggest drop is the priority to fix.

## 3. Retention
- D1 / D7 / D30 retention; W1–W4 weekly retention.
- Loop retention: % of returning users who scan AND plan in the same week.
- Benchmark reality: nutrition apps fall to ~30% after month one — watch the 2-week cliff.

## 4. Core event taxonomy (store in `events`)
| Event | Key props |
|---|---|
| onboarding_completed | skipped_steps[], goal, diet_pattern |
| scan_started / scan_succeeded / scan_failed | source, latency_ms, found:bool |
| score_viewed | score, band, confidence |
| why_score_expanded | product_id |
| ocr_fallback_used | success:bool |
| pantry_item_added | status |
| swap_shown / swap_accepted | from_score, to_score |
| plan_slot_filled | source: manual\|ai\|swap |
| ai_plan_requested / ai_plan_applied | latency_ms, edits_after |
| shopping_list_generated | items, need_count |
| paywall_viewed / trial_started / subscription_active / subscription_cancelled | plan, price |
| data_reported | product_id, reason |
| chat_opened | product_id |
| feedback_sentiment | sentiment (not_great\|okay\|good\|great) |
| app_review_requested | — |
| score_hidden_toggled / calories_toggled | value |

Rules: event names snake_case, stable; no PII in props; user_id is the Supabase id (pseudonymous).

**Client implementation note (Chunk 7):** these canonical names are authoritative and are what `AnalyticsLogger.EventName` emits. The Chunk 7 plan used shorthand that maps onto them: `result_viewed`→`score_viewed`, `why_expanded`→`why_score_expanded`, `swap_viewed`→`swap_shown`, `swap_saved`→`swap_accepted`, `report_submitted`→`data_reported`. `chat_opened`, `feedback_sentiment`, and `app_review_requested` are new events appended here in Chunk 7. Free text (the sentiment gate's message) NEVER goes in `events.props` — it lands in the separate owner-only `app_feedback` table (migration `20260710120000`); the `AnalyticsValue` type makes non-scalar props structurally impossible. Events are inserted directly via PostgREST under the existing owner-only `events` INSERT RLS policy — there is no analytics edge function.

## 5. Trust & safety metrics (category-specific)
- "Why this score" expand rate (do users engage with transparency?).
- Score-hidden / calories-on rates (are ED-safe options used? informs defaults).
- Data-report rate per 100 scans (database quality signal).
- Cancel reason distribution (billing? value? trust?).

## 6. Tooling
- Lightweight first: log to `events` table + a privacy-friendly product-analytics tool (e.g. PostHog self-host or similar). RevenueCat for subscription metrics. Sentry for crashes (a guardrail metric source).
- Avoid heavy SDKs that bloat the bundle or raise privacy flags (a positioning asset for us).

## 7. Review cadence
- Weekly: funnel + crash-free + reviews.
- Monthly: retention cohorts + cancel reasons → feed `MEMORY.md` decisions.

## 8. Privacy
- Disclose analytics in the Privacy Policy and App Store privacy labels.
- No third-party ad/tracking SDKs. Allow opt-out where feasible. Data minimization by default.
