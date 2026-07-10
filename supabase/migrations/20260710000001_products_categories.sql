-- ---------------------------------------------------------------------------
-- Chunk 3 (Swaps engine): add OFF category tags to products.
--
-- Swaps groups "better options in the same category". `products` had no
-- category column and the OFF client never fetched `categories_tags`; this
-- adds the column (populated on the next scan/upsert via _shared/off.ts) and a
-- GIN index for the `&&` (array overlap) candidate query the swaps function
-- runs. Existing cached rows carry '{}' until re-fetched; the demo cohort seed
-- (20260710010000_swaps_demo_seed.sql) backfills a same-category set so swaps
-- returns real results at the deploy gate.
--
-- No RLS change: inherits the existing "products are readable by signed-in
-- users" global-read policy; writes still happen only through Edge Functions
-- using the service-role key.
-- ---------------------------------------------------------------------------

alter table products
  add column categories_tags text[] not null default '{}';

-- GIN index for the array-overlap (&&) same-category candidate lookup.
create index products_categories_gin_idx
  on products using gin (categories_tags);
