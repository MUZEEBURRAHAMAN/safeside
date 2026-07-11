-- =============================================================================
-- Re-score cron — fire POST /rescore daily so cached products auto-re-score
-- after a SCORE_VERSION bump. Chunk 4, Task 5.
--
-- The /rescore edge function is gated by the `X-Rescore-Secret` header (==
-- the function's RESCORE_SECRET env secret). The cron passes that same secret,
-- read from a DB setting so the literal is NEVER committed to the repo.
--
-- SECRET WIRING (run once, OUT OF BAND — do NOT commit the literal):
--   NOTE: `alter database postgres set app.rescore_secret = …` is REJECTED on
--   managed Supabase (ERROR 42501 — even the dashboard `postgres` role cannot
--   set a custom `app.*` GUC). Use Supabase Vault instead:
--     select vault.create_secret('<the-secret>', 'rescore_secret');
--   The same value must be set as the function secret:
--     supabase secrets set RESCORE_SECRET='<the-secret>' --project-ref <ref>
--
-- If the vault secret is missing, the subquery returns NULL and the function
-- returns 401 — a safe no-op until the secret is wired.
-- =============================================================================

create extension if not exists pg_cron;
create extension if not exists pg_net;

-- Daily at 04:00 UTC: fire the rescore function. It batches (limit 200) and
-- re-runs the next day until the stale backlog is drained.
select cron.schedule(
  'rescore-on-version-bump',
  '0 4 * * *',
  $$
  select net.http_post(
    url := 'https://usmdthxnxzdywtjgbokl.functions.supabase.co/rescore',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'X-Rescore-Secret', (select decrypted_secret from vault.decrypted_secrets where name = 'rescore_secret')
    ),
    body := jsonb_build_object('limit', 200)
  );
  $$
);

-- To remove: select cron.unschedule('rescore-on-version-bump');
