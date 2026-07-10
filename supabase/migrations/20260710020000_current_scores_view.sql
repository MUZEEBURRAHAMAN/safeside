-- =============================================================================
-- product_current_scores — one row per product = its most-recently-computed
-- score_results row (by computed_at). Chunk 4, Task 1.
--
-- Fixes the "highest-ever score" correctness bug: trending / swaps / search
-- previously reduced score_results in JS by ordering on `score` (trending) or
-- kept the newest-by-timestamp per product in application code. A product
-- scored high once and later downgraded could still surface its stale high
-- score. This view is the single source of truth for "the score a user would
-- see today".
--
-- Column note: the real timestamp column in score_results is `computed_at`
-- (see 20260707000000_initial_schema.sql:84). MASTER_PLAN's `scored_at` does
-- not exist — do NOT use it.
--
-- Security: security_invoker = true → the view runs with the CALLER's rights,
-- so it inherits score_results' existing global-read RLS (the "score results
-- are readable by signed-in users" policy). It grants NO new write surface;
-- score_results writes stay service-role only.
-- =============================================================================

create view product_current_scores
  with (security_invoker = true)
as
  select distinct on (product_id)
    id,
    product_id,
    score,
    band,
    confidence,
    breakdown,
    score_version,
    computed_at
  from score_results
  order by product_id, computed_at desc;

-- Anonymous Supabase sessions carry the `authenticated` role; `anon` is granted
-- too for completeness. Both are read-only — the underlying table's RLS still
-- applies because the view is security_invoker.
grant select on product_current_scores to authenticated, anon;

-- Deploy-gate cross-check (run manually against real history; NOT executed here):
--   -- The view's row for a product must equal its MAX(computed_at) row,
--   -- NOT its MAX(score) row.
--   select v.product_id, v.score, v.computed_at
--   from product_current_scores v
--   order by v.computed_at desc
--   limit 20;
--
--   -- For a product re-scored at least once (id = :pid):
--   select 'view'   as src, score, computed_at
--     from product_current_scores where product_id = :pid
--   union all
--   select 'newest' as src, score, computed_at
--     from score_results
--     where product_id = :pid
--     order by computed_at desc
--     limit 1;
--   -- Expected: the two `score`/`computed_at` pairs match, even when an older
--   -- row has a HIGHER score.
