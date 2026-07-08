-- =============================================================================
-- Ingredient Knowledge Base + explanations cache
-- Implements docs/AI_INGREDIENT_EXPLANATION.md §3 (the curated, versioned KB is
-- the single source of truth) and §6 (aggressive per-ingredient caching).
--
-- Governance (§2, §5): the LLM never invents facts — it only rewrites vetted
-- fields we retrieve here. No KB entry → no explanation. The `risk_tier` stored
-- here MUST equal the scoring table's tier (supabase/functions/_shared/scoring/
-- additives_risk.json) — one source of truth; the LLM can never change it.
--
-- Both tables are a GLOBAL cache, mirroring products / score_results:
-- readable by any signed-in (incl. anonymous) session, writable ONLY through
-- Edge Functions using the service_role key (which bypasses RLS). No
-- insert/update/delete policies are granted to `authenticated` on purpose.
-- =============================================================================

-- risk tiers mirror the scoring engine's AdditiveTier (low | moderate | higher).
create type ingredient_risk_tier_type as enum ('low', 'moderate', 'higher');

-- ---------------------------------------------------------------------------
-- ingredient_kb (the curated asset — seeded from ingredient_kb_seed.json)
-- ---------------------------------------------------------------------------
create table ingredient_kb (
  id               text primary key,                       -- OFF tag convention, e.g. 'en:e330', 'en:sugar'
  names            text[] not null default '{}',           -- synonyms for name matching, e.g. ['Monosodium glutamate','MSG','E621']
  what             text,                                   -- null → UI shows "limited"; never fabricated
  why_used         text,
  safety           text,                                   -- dose- and risk-aware; sourced
  risk_tier        ingredient_risk_tier_type not null,     -- MUST equal the scoring tier for additives
  who_should_avoid text[] not null default '{}',
  misconceptions   text[] not null default '{}',
  found_in         text[] not null default '{}',
  sources          jsonb not null default '[]',            -- [{ name, url }] — every claim cites a named regulator
  confidence       data_confidence_type not null default 'high',
  last_reviewed    text,                                   -- e.g. '2026-07'
  kb_version       text not null,                          -- bump on any content change (§3)
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);

-- Match by synonym (ingredients endpoint resolves label tokens → KB entries).
create index ingredient_kb_names_idx on ingredient_kb using gin (names);
create index ingredient_kb_kb_version_idx on ingredient_kb (kb_version);

create trigger ingredient_kb_set_updated_at
  before update on ingredient_kb
  for each row
  execute function set_updated_at();

-- ---------------------------------------------------------------------------
-- ingredient_explanations (LLM-rewritten explanations, cached aggressively)
--
-- Keyed (ingredient_id, kb_version, locale): a rewrite is stable for a given
-- KB version + locale, so most scans cost ~$0 in AI (cache hits). Bumping
-- kb_version naturally invalidates stale rewrites without a delete. The
-- personalization note is NOT cached here (it is a light per-request layer),
-- so the base explanation stays globally cacheable.
-- ---------------------------------------------------------------------------
create table ingredient_explanations (
  ingredient_id text not null references ingredient_kb (id) on delete cascade,
  kb_version    text not null,
  locale        text not null default 'en',
  explanation   jsonb not null,                            -- the rewritten Ingredient JSON (Models.swift shape)
  created_at    timestamptz not null default now(),
  primary key (ingredient_id, kb_version, locale)
);

-- ---------------------------------------------------------------------------
-- Row-Level Security — global read, backend-only write (see header).
-- ---------------------------------------------------------------------------
alter table ingredient_kb           enable row level security;
alter table ingredient_explanations enable row level security;

create policy "ingredient kb is readable by signed-in users"
  on ingredient_kb for select
  to authenticated
  using (true);

create policy "ingredient explanations are readable by signed-in users"
  on ingredient_explanations for select
  to authenticated
  using (true);
