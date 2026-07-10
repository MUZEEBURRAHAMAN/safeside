-- =============================================================================
-- Chunk 7 — analytics hardening + sentiment-gate feedback
--
-- Additive-only migration (never rewrites the existing `events` policies from
-- 20260707000000_initial_schema.sql). Two concerns:
--   1. Harden `events`: index the funnel query path (name, ts) and cap the
--      event-name length so a client bug can't write unbounded strings.
--   2. Add `app_feedback`: the sentiment gate's *free text* lives here, OUTSIDE
--      the analytics table, so PII (a typed message) can never land in
--      `events.props`. Same owner-only, append-only RLS shape as `events`.
--
-- The `events` table already carries an owner-only INSERT policy
-- (`with check (auth.uid() = user_id)`), so the iOS client inserts its own
-- rows directly via PostgREST — there is NO analytics edge function.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1. events hardening (additive)
-- ---------------------------------------------------------------------------
-- Funnel reads filter/aggregate by event name over a time window; index that
-- path directly (the existing events_user_id_ts_idx covers per-user reads).
create index if not exists events_name_ts_idx on events (name, ts desc);

-- A stable event name is short snake_case; 64 chars is generous headroom.
-- Guards against a malformed/oversized name from a client bug.
alter table events add constraint events_name_len check (char_length(name) <= 64);

-- ---------------------------------------------------------------------------
-- 2. app_feedback — sentiment-gate free text (PII stays OUT of events)
-- ---------------------------------------------------------------------------
create type feedback_sentiment_type as enum ('not_great', 'okay', 'good', 'great');

create table app_feedback (
  id        uuid primary key default gen_random_uuid(),
  user_id   uuid references auth.users (id) on delete set null,  -- kept anon after deletion
  sentiment feedback_sentiment_type not null,
  message   text,                                                 -- optional free text; owner-only
  ts        timestamptz not null default now()
);

create index app_feedback_ts_idx on app_feedback (ts desc);

alter table app_feedback enable row level security;

-- Owner-only insert + read; no update/delete (append-only, mirrors `events`).
create policy "users can submit own feedback"
  on app_feedback for insert
  to authenticated
  with check (auth.uid() = user_id);

create policy "users can read own feedback"
  on app_feedback for select
  to authenticated
  using (auth.uid() = user_id);
