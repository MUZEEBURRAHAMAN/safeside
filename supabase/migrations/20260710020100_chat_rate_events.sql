-- =============================================================================
-- chat_rate_events — per-user sliding-window ledger for POST /chat. Chunk 4,
-- Task 4.
--
-- One row per accepted /chat request, keyed by the caller's JWT `sub` (anon
-- uids included). The chat edge function reads the last-window rows to decide
-- whether the caller is over RATE_LIMIT_MAX per RATE_LIMIT_WINDOW_MS, and
-- inserts a row on each ACCEPTED request.
--
-- Backend-only: RLS is enabled with NO policies, so `authenticated` / `anon`
-- clients can neither read nor write it — exactly like `products` writes. All
-- access is via the service-role key from the edge function (service role
-- bypasses RLS). Never expose this table to the client.
-- =============================================================================

create table chat_rate_events (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null,
  created_at timestamptz not null default now()
);

-- Window lookups are (user_id, created_at desc) range scans.
create index chat_rate_events_user_ts_idx
  on chat_rate_events (user_id, created_at desc);

-- Deny-all to clients: RLS on, no policies granted → only the service role
-- (which bypasses RLS) can touch it.
alter table chat_rate_events enable row level security;
