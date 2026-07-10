-- ---------------------------------------------------------------------------
-- product_reports — user-filed "Report an issue" submissions (Chunk 1).
--
-- Written ONLY by the product-report Edge Function using the service-role key
-- (which bypasses RLS). The insert-only policy below is defense-in-depth: it
-- mirrors the events-table pattern (initial schema §events) so that even a
-- leaked anon key can only insert a row it owns and can never read others'.
-- No select/update/delete is granted to clients.
-- ---------------------------------------------------------------------------

create type report_reason_type as enum (
  'score_off',
  'wrong_info',
  'missing_ingredient',
  'other'
);

create table product_reports (
  id          uuid primary key default gen_random_uuid(),
  product_id  uuid not null references products (id) on delete cascade,
  reporter_id uuid references auth.users (id) on delete set null,  -- anon JWT user; kept after deletion
  reason      report_reason_type not null,
  detail      text check (char_length(detail) <= 1000),
  created_at  timestamptz not null default now()
);

create index product_reports_product_id_idx
  on product_reports (product_id, created_at desc);

alter table product_reports enable row level security;

-- Insert-only for the authenticated (incl. anonymous) role; a row must be
-- owned by the caller. No read/update/delete policies on purpose.
create policy "users can file reports"
  on product_reports for insert
  to authenticated
  with check (auth.uid() = reporter_id);
