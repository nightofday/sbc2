begin;

create extension if not exists pgtap with schema extensions;

select plan(14);

-- Running the presentation seed twice proves that it is safe to rerun while
-- preparing or recovering a demonstration environment. Supabase mounts only
-- supabase/tests in the pg_prove container, so the mirrored fixture must stay
-- inside that directory. Database CI verifies it matches supabase/demo_seed.sql.
\ir fixtures/demo_seed.psql
\ir fixtures/demo_seed.psql

select is(
  (
    select count(*)
    from public.suppliers
    where supplier_code in (
      'DEMO-PACKAGING',
      'DEMO-BEVERAGE',
      'DEMO-GROCERY'
    )
  ),
  3::bigint,
  'the demo seed creates exactly three presentation suppliers'
);

select is(
  (
    select count(*)
    from public.inventory_items
    where sku like 'INV-DEMO-%'
  ),
  5::bigint,
  'the demo seed creates five countable packaging items'
);

select is(
  (
    select count(*)
    from public.supplier_items si
    join public.suppliers s on s.id = si.supplier_id
    where s.supplier_code in ('DEMO-PACKAGING', 'DEMO-BEVERAGE')
  ),
  7::bigint,
  'the demo seed creates the expected supplier item mappings'
);

select is(
  (
    select si.base_quantity_per_purchase_unit
    from public.supplier_items si
    join public.suppliers s on s.id = si.supplier_id
    join public.inventory_items ii on ii.id = si.inventory_item_id
    join public.units_of_measure u on u.id = si.purchase_uom_id
    where s.supplier_code = 'DEMO-PACKAGING'
      and ii.sku = 'INV-DEMO-CUP16'
      and u.code = 'box'
  ),
  50::numeric,
  'one box of cold cups converts to fifty pieces'
);

select is(
  (
    select si.base_quantity_per_purchase_unit
    from public.supplier_items si
    join public.suppliers s on s.id = si.supplier_id
    join public.inventory_items ii on ii.id = si.inventory_item_id
    join public.units_of_measure u on u.id = si.purchase_uom_id
    where s.supplier_code = 'DEMO-BEVERAGE'
      and ii.sku = 'INV-001'
      and u.code = 'box'
  ),
  24::numeric,
  'one box of bottled water converts to twenty-four pieces'
);

select is(
  (
    select count(*)
    from public.menu_variants
    where sku in ('PRD-003-L', 'PRD-004-L')
  ),
  2::bigint,
  'the demo seed creates the two large coffee variants'
);

select is(
  (
    select count(*)
    from public.menu_variants
    where sku in ('PRD-003-L', 'PRD-004-L')
      and track_finished_inventory = false
      and finished_inventory_item_id is null
  ),
  2::bigint,
  'prepared coffee variants remain outside finished-good inventory tracking'
);

select is(
  (
    select count(*)
    from public.modifier_groups
    where name in ('Bowl Add-ons', 'Coffee Sweetness')
  ),
  2::bigint,
  'the demo seed creates the presentation modifier groups'
);

select is(
  (
    select count(*)
    from public.modifiers m
    join public.modifier_groups mg on mg.id = m.modifier_group_id
    where mg.name in ('Bowl Add-ons', 'Coffee Sweetness')
  ),
  6::bigint,
  'the demo seed creates the six presentation modifiers'
);

select is(
  (
    select count(*)
    from public.menu_item_modifier_groups mimg
    join public.modifier_groups mg on mg.id = mimg.modifier_group_id
    join public.menu_items mi on mi.id = mimg.menu_item_id
    where mg.name in ('Bowl Add-ons', 'Coffee Sweetness')
      and mi.name in ('Chicken Bowl', 'Beef Bowl', 'Iced Coffee', 'Hot Coffee')
  ),
  4::bigint,
  'the modifier groups are attached to the four expected menu items'
);

select is(
  (
    select count(*)
    from public.variant_recipe_components vrc
    join public.menu_variants mv on mv.id = vrc.menu_variant_id
    where mv.sku in (
      'PRD-001', 'PRD-002', 'PRD-003',
      'PRD-004', 'PRD-003-L', 'PRD-004-L'
    )
  ),
  0::bigint,
  'presentation menu variants do not reintroduce recipe deductions'
);

select is(
  (
    select count(*)
    from public.modifier_recipe_components mrc
    join public.modifiers m on m.id = mrc.modifier_id
    join public.modifier_groups mg on mg.id = m.modifier_group_id
    where mg.name in ('Bowl Add-ons', 'Coffee Sweetness')
  ),
  0::bigint,
  'presentation modifiers do not deduct recipe ingredients'
);

select is(
  (
    select count(*)
    from public.stock_movements sm
    join public.inventory_items ii on ii.id = sm.inventory_item_id
    where ii.sku like 'INV-DEMO-%'
  ),
  0::bigint,
  'the demo seed does not fabricate inventory movements'
);

select is(
  (
    select count(*)
    from public.inventory_lots il
    join public.inventory_items ii on ii.id = il.inventory_item_id
    where ii.sku like 'INV-DEMO-%'
  ),
  0::bigint,
  'the demo seed does not fabricate inventory lots'
);

select * from finish();

rollback;
