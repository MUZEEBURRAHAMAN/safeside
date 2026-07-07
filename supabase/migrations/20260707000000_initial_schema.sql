-- =============================================================================
-- Initial schema — from docs/DATA_MODEL.md (v1.0)
--
-- Tables: profiles, products, score_results, pantry_items, events.
-- NOTE: plans, plan_slots, recipes, and shopping_list_items are DEFERRED —
-- the meal planner is not in the MVP (see BACKEND_SPEC §1). Add them in a
-- later migration when the planner returns.
--
-- Convention: enumerated values are implemented as Postgres ENUM types
-- (consistent everywhere; CHECK constraints are used only for numeric ranges).
-- =============================================================================

create extension if not exists "pgcrypto";

-- ---------------------------------------------------------------------------
-- Enums
-- ---------------------------------------------------------------------------
create type goal_type as enum ('healthier', 'less_processed', 'lose', 'gain', 'condition', 'budget');
create type diet_pattern_type as enum ('omnivore', 'flexitarian', 'vegetarian', 'vegan', 'pescatarian', 'keto', 'mediterranean', 'none');
create type cook_time_type as enum ('quick', 'medium', 'enjoy');
create type budget_type as enum ('low', 'medium', 'none');
create type score_display_type as enum ('shown', 'hidden');
create type product_source_type as enum ('off', 'usda', 'ocr', 'user');
create type data_confidence_type as enum ('high', 'limited');
create type score_band_type as enum ('high', 'mid', 'low', 'unknown');
create type pantry_status_type as enum ('scanned', 'favorited', 'owned');

-- ---------------------------------------------------------------------------
-- profiles (1:1 with auth.users)
-- ---------------------------------------------------------------------------
create table profiles (
  user_id          uuid primary key references auth.users (id) on delete cascade,
  goal             goal_type,
  diet_pattern     diet_pattern_type,
  allergies        text[] not null default '{}',          -- normalized allergen tags
  dislikes         text[] not null default '{}',          -- ingredient tags
  meals_per_day    int check (meals_per_day between 1 and 10),
  snacks_per_day   int check (snacks_per_day between 0 and 10),
  household_size   int check (household_size between 1 and 20),
  cook_time        cook_time_type,
  budget           budget_type,
  health_flags     text[] not null default '{}',          -- diabetes, hypertension, pregnancy, glp1 …
  show_calories    boolean not null default false,        -- ED-safe: numbers are opt-in
  score_display    score_display_type not null default 'shown',
  computed_targets jsonb,                                 -- TDEE/macros, never forced on the user
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- products (global cache of external data + our derived fields)
-- ---------------------------------------------------------------------------
create table products (
  id               uuid primary key default gen_random_uuid(),
  barcode          text unique,                           -- nullable for OCR-only items
  name             text not null,
  brand            text,
  source           product_source_type not null,
  nova_group       int check (nova_group between 1 and 4),
  nutriscore_grade text check (nutriscore_grade in ('a', 'b', 'c', 'd', 'e')),
  nutrients        jsonb not null default '{}',           -- normalized per-100g + per-serving
  serving_size     text,
  additives_tags   text[] not null default '{}',          -- OFF-style tags, e.g. 'en:e330'
  allergens_tags   text[] not null default '{}',
  ingredients_text text,
  images           jsonb,                                 -- { front: url, ... }
  data_confidence  data_confidence_type not null default 'limited',
  raw_off          jsonb,                                 -- original payload for re-derivation on score_version bumps
  fetched_at       timestamptz not null default now(),    -- cache freshness (30-day TTL)
  updated_at       timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- score_results (current + history; 1 current row per product per score_version)
-- ---------------------------------------------------------------------------
create table score_results (
  id            uuid primary key default gen_random_uuid(),
  product_id    uuid not null references products (id) on delete cascade,
  score         int check (score between 0 and 100),      -- null when band = 'unknown' (not enough data)
  band          score_band_type not null,
  breakdown     jsonb not null default '{}',              -- factors: sub-score, weight, detail, sources
  confidence    data_confidence_type not null,
  score_version text not null,
  computed_at   timestamptz not null default now(),
  constraint score_required_unless_unknown check (band = 'unknown' or score is not null)
);

-- ---------------------------------------------------------------------------
-- pantry_items (the scanner→planner bridge)
-- ---------------------------------------------------------------------------
create table pantry_items (
  id               uuid primary key default gen_random_uuid(),
  user_id          uuid not null references auth.users (id) on delete cascade,
  product_id       uuid not null references products (id) on delete cascade,
  status           pantry_status_type not null default 'scanned',
  first_scanned_at timestamptz not null default now(),
  last_seen_at     timestamptz not null default now(),
  unique (user_id, product_id)
);

-- ---------------------------------------------------------------------------
-- events (analytics; see ANALYTICS_METRICS.md)
-- ---------------------------------------------------------------------------
create table events (
  id      uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users (id) on delete set null,  -- kept anonymized after account deletion
  name    text not null,
  props   jsonb not null default '{}',
  ts      timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- Indexes (DATA_MODEL §4)
-- products.barcode and pantry_items(user_id, product_id) are covered by their
-- UNIQUE constraints above.
-- ---------------------------------------------------------------------------
create index score_results_product_id_idx on score_results (product_id, computed_at desc);
create index events_user_id_ts_idx on events (user_id, ts);
create index pantry_items_user_id_idx on pantry_items (user_id, last_seen_at desc);

-- ---------------------------------------------------------------------------
-- updated_at trigger on products
-- ---------------------------------------------------------------------------
create or replace function set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger products_set_updated_at
  before update on products
  for each row
  execute function set_updated_at();

create trigger profiles_set_updated_at
  before update on profiles
  for each row
  execute function set_updated_at();

-- ---------------------------------------------------------------------------
-- Row-Level Security (DATA_MODEL §5)
--
-- products / score_results: shared global cache. Readable by any signed-in
-- session — anonymous Supabase sessions carry the 'authenticated' role, so
-- anon users can read scores. Writes happen ONLY through Edge Functions using
-- the service_role key, which bypasses RLS; no insert/update/delete policies
-- are granted to 'authenticated' on purpose.
--
-- profiles / pantry_items / events: owner-only via auth.uid().
-- ---------------------------------------------------------------------------
alter table profiles      enable row level security;
alter table products      enable row level security;
alter table score_results enable row level security;
alter table pantry_items  enable row level security;
alter table events        enable row level security;

-- products: global read, backend-only write
create policy "products are readable by signed-in users"
  on products for select
  to authenticated
  using (true);

-- score_results: global read, backend-only write
create policy "score results are readable by signed-in users"
  on score_results for select
  to authenticated
  using (true);

-- profiles: owner-only
create policy "users can read own profile"
  on profiles for select
  to authenticated
  using (auth.uid() = user_id);

create policy "users can create own profile"
  on profiles for insert
  to authenticated
  with check (auth.uid() = user_id);

create policy "users can update own profile"
  on profiles for update
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create policy "users can delete own profile"
  on profiles for delete
  to authenticated
  using (auth.uid() = user_id);

-- pantry_items: owner-only
create policy "users can read own pantry"
  on pantry_items for select
  to authenticated
  using (auth.uid() = user_id);

create policy "users can add to own pantry"
  on pantry_items for insert
  to authenticated
  with check (auth.uid() = user_id);

create policy "users can update own pantry"
  on pantry_items for update
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create policy "users can delete from own pantry"
  on pantry_items for delete
  to authenticated
  using (auth.uid() = user_id);

-- events: owner-only insert + read (no update/delete from clients)
create policy "users can log own events"
  on events for insert
  to authenticated
  with check (auth.uid() = user_id);

create policy "users can read own events"
  on events for select
  to authenticated
  using (auth.uid() = user_id);
