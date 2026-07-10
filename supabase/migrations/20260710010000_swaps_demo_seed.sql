-- ---------------------------------------------------------------------------
-- Chunk 3 (Swaps engine): demo same-category cohort seed.
--
-- Products only enter `products` on scan, and existing cached rows carry an
-- empty categories_tags (see 20260710000000_products_categories.sql). Swaps
-- needs several same-category products WITH current-version scores to return a
-- real ranked result. This seeds one OFF category ("en:chocolate-spreads")
-- spanning score bands: a low-score SUBJECT plus higher- and lower-scored
-- alternatives, so the deploy-gate smoke test returns >= 1 sourced better
-- option and can prove allergen filtering.
--
-- Idempotent (ON CONFLICT DO NOTHING). Scores are written at the CURRENT
-- score_version ('1.1.0') so the swaps function's current-score gate accepts
-- them; if the score engine version bumps, refresh this seed.
--
-- Fixed UUIDs so the smoke test can reference the subject directly:
--   SUBJECT (low, score 29): aaaaaaaa-0000-4000-8000-000000000001
-- ---------------------------------------------------------------------------

-- --- products -------------------------------------------------------------
insert into products (
  id, barcode, name, brand, source, nova_group, nutriscore_grade,
  nutrients, serving_size, additives_tags, allergens_tags, categories_tags,
  ingredients_text, images, data_confidence, raw_off, fetched_at
) values
  -- SUBJECT: low-scoring ultra-processed spread (colour additive, high sat fat + sugar)
  ('aaaaaaaa-0000-4000-8000-000000000001', '9990000000001',
   'Choco Hazelnut Spread', 'DemoBrand', 'off', 4, 'e',
   '{"saturated-fat_100g": 10.6, "sugars_100g": 56.3, "salt_100g": 0.107}'::jsonb,
   '15 g', '{"en:e150d","en:e330"}', '{"en:milk","en:nuts"}',
   '{"en:spreads","en:chocolate-spreads"}',
   'Sugar, palm oil, hazelnuts, skimmed milk powder, colour, emulsifier.',
   '{"front": "https://images.openfoodfacts.org/demo/subject.jpg"}'::jsonb,
   'high', '{"source": "swaps-demo-seed"}'::jsonb, now()),

  -- BETTER + allergen-safe (no milk): simple hazelnut butter, no additives
  ('aaaaaaaa-0000-4000-8000-000000000002', '9990000000002',
   'Simple Hazelnut Butter', 'DemoBrand', 'off', 2, 'b',
   '{"saturated-fat_100g": 3.0, "sugars_100g": 4.0, "salt_100g": 0.02}'::jsonb,
   '15 g', '{}', '{"en:nuts"}',
   '{"en:spreads","en:chocolate-spreads"}',
   'Hazelnuts, cocoa.',
   '{"front": "https://images.openfoodfacts.org/demo/alt-a.jpg"}'::jsonb,
   'high', '{"source": "swaps-demo-seed"}'::jsonb, now()),

  -- BETTER but has milk: filtered out for a milk-allergic profile
  ('aaaaaaaa-0000-4000-8000-000000000003', '9990000000003',
   'Dark Cocoa Spread', 'DemoBrand', 'off', 3, 'c',
   '{"saturated-fat_100g": 6.0, "sugars_100g": 30.0, "salt_100g": 0.05}'::jsonb,
   '15 g', '{"en:e330"}', '{"en:milk","en:soybeans"}',
   '{"en:spreads","en:chocolate-spreads"}',
   'Cocoa, sugar, skimmed milk powder, citric acid.',
   '{"front": "https://images.openfoodfacts.org/demo/alt-b.jpg"}'::jsonb,
   'high', '{"source": "swaps-demo-seed"}'::jsonb, now()),

  -- BETTER + allergen-safe (no milk): almond spread
  ('aaaaaaaa-0000-4000-8000-000000000004', '9990000000004',
   'Almond Choc Spread', 'DemoBrand', 'off', 3, 'b',
   '{"saturated-fat_100g": 4.5, "sugars_100g": 22.0, "salt_100g": 0.03}'::jsonb,
   '15 g', '{}', '{"en:nuts"}',
   '{"en:spreads","en:chocolate-spreads"}',
   'Almonds, cocoa, a little sugar.',
   '{"front": "https://images.openfoodfacts.org/demo/alt-c.jpg"}'::jsonb,
   'high', '{"source": "swaps-demo-seed"}'::jsonb, now()),

  -- NOT better (lower score): proves ranking excludes worse same-category items
  ('aaaaaaaa-0000-4000-8000-000000000005', '9990000000005',
   'Budget Choco Paste', 'DemoBrand', 'off', 4, 'e',
   '{"saturated-fat_100g": 12.0, "sugars_100g": 60.0, "salt_100g": 0.2}'::jsonb,
   '15 g', '{"en:e150d","en:e471"}', '{"en:milk"}',
   '{"en:spreads","en:chocolate-spreads"}',
   'Sugar, palm oil, cocoa, colour, emulsifier.',
   '{"front": "https://images.openfoodfacts.org/demo/alt-d.jpg"}'::jsonb,
   'high', '{"source": "swaps-demo-seed"}'::jsonb, now())
on conflict (id) do nothing;

-- --- score_results (current version 1.1.0) --------------------------------
insert into score_results (product_id, score, band, breakdown, confidence, score_version)
values
  ('aaaaaaaa-0000-4000-8000-000000000001', 29, 'low',
   '{"source": "swaps-demo-seed"}'::jsonb, 'high', '1.1.0'),
  ('aaaaaaaa-0000-4000-8000-000000000002', 78, 'high',
   '{"source": "swaps-demo-seed"}'::jsonb, 'high', '1.1.0'),
  ('aaaaaaaa-0000-4000-8000-000000000003', 62, 'mid',
   '{"source": "swaps-demo-seed"}'::jsonb, 'high', '1.1.0'),
  ('aaaaaaaa-0000-4000-8000-000000000004', 71, 'mid',
   '{"source": "swaps-demo-seed"}'::jsonb, 'high', '1.1.0'),
  ('aaaaaaaa-0000-4000-8000-000000000005', 20, 'low',
   '{"source": "swaps-demo-seed"}'::jsonb, 'high', '1.1.0')
on conflict do nothing;
