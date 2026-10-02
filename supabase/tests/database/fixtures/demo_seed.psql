-- Street Bowl Cafe presentation master data.
--
-- Development/demo projects only. Run after all migrations and seed.sql.
-- This script is safe to rerun and intentionally creates no Auth users,
-- completed transactions, inventory lots, or stock movements. Transactional
-- records should be created through the application during the demonstration.

insert into public.suppliers(
  supplier_code,
  name,
  contact_person,
  address,
  payment_terms_days,
  notes,
  is_active
)
values
  (
    'DEMO-PACKAGING',
    'Davao Packaging Supply',
    'Demo Contact',
    'Davao City',
    7,
    'Presentation data only - replace after business validation.',
    true
  ),
  (
    'DEMO-BEVERAGE',
    'Beverage Distributor',
    'Demo Contact',
    'Davao City',
    7,
    'Presentation data only - replace after business validation.',
    true
  ),
  (
    'DEMO-GROCERY',
    'Local Grocery / Supermarket',
    'Store Counter',
    'Davao City',
    0,
    'Use for untracked ingredient and grocery expense demonstrations.',
    true
  )
on conflict (supplier_code) do update set
  name = excluded.name,
  contact_person = excluded.contact_person,
  address = excluded.address,
  payment_terms_days = excluded.payment_terms_days,
  notes = excluded.notes,
  is_active = true,
  archived_at = null;

with desired(
  sku,
  name,
  category_name,
  reorder_level,
  reorder_target
) as (
  values
    ('INV-DEMO-CUP16', '16 oz Cold Cups', 'Packaging', 100::numeric, 250::numeric),
    ('INV-DEMO-LID16', '16 oz Flat Lids', 'Packaging', 100::numeric, 250::numeric),
    ('INV-DEMO-BOWL', 'Kraft Meal Bowls', 'Packaging', 50::numeric, 150::numeric),
    ('INV-DEMO-BOWL-LID', 'Meal Bowl Lids', 'Packaging', 50::numeric, 150::numeric),
    ('INV-DEMO-BAG', 'Paper Takeout Bags', 'Packaging', 30::numeric, 100::numeric)
)
insert into public.inventory_items(
  sku,
  name,
  category_id,
  base_uom_id,
  track_inventory,
  track_expiry,
  allow_negative_stock,
  reorder_level,
  reorder_target,
  notes,
  is_active
)
select
  d.sku,
  d.name,
  ic.id,
  u.id,
  true,
  false,
  false,
  d.reorder_level,
  d.reorder_target,
  'Countable presentation supply; base quantity is recorded in pieces.',
  true
from desired d
join public.inventory_categories ic on ic.name = d.category_name
join public.units_of_measure u on u.code = 'pc'
on conflict (sku) do update set
  name = excluded.name,
  category_id = excluded.category_id,
  base_uom_id = excluded.base_uom_id,
  track_inventory = true,
  track_expiry = false,
  allow_negative_stock = false,
  reorder_level = excluded.reorder_level,
  reorder_target = excluded.reorder_target,
  notes = excluded.notes,
  is_active = true,
  archived_at = null;

with desired(
  supplier_code,
  inventory_sku,
  supplier_sku,
  purchase_uom_code,
  base_quantity,
  unit_cost,
  preferred
) as (
  values
    ('DEMO-PACKAGING', 'INV-DEMO-CUP16', 'CUP16-BOX50', 'box', 50::numeric, 210::numeric, true),
    ('DEMO-PACKAGING', 'INV-DEMO-LID16', 'LID16-BOX50', 'box', 50::numeric, 175::numeric, true),
    ('DEMO-PACKAGING', 'INV-DEMO-BOWL', 'BOWL-PACK25', 'pack', 25::numeric, 225::numeric, true),
    ('DEMO-PACKAGING', 'INV-DEMO-BOWL-LID', 'BOWL-LID-PACK25', 'pack', 25::numeric, 175::numeric, true),
    ('DEMO-PACKAGING', 'INV-DEMO-BAG', 'BAG-PACK50', 'pack', 50::numeric, 150::numeric, true),
    ('DEMO-BEVERAGE', 'INV-001', 'WATER-BOX24', 'box', 24::numeric, 360::numeric, true),
    ('DEMO-BEVERAGE', 'INV-002', 'COKE-BOX24', 'box', 24::numeric, 672::numeric, true)
)
insert into public.supplier_items(
  supplier_id,
  inventory_item_id,
  supplier_sku,
  purchase_uom_id,
  base_quantity_per_purchase_unit,
  last_unit_cost,
  is_preferred,
  is_active
)
select
  s.id,
  ii.id,
  d.supplier_sku,
  u.id,
  d.base_quantity,
  d.unit_cost,
  d.preferred,
  true
from desired d
join public.suppliers s on s.supplier_code = d.supplier_code
join public.inventory_items ii on ii.sku = d.inventory_sku
join public.units_of_measure u on u.code = d.purchase_uom_code
on conflict (supplier_id, inventory_item_id, purchase_uom_id) do update set
  supplier_sku = excluded.supplier_sku,
  base_quantity_per_purchase_unit = excluded.base_quantity_per_purchase_unit,
  last_unit_cost = excluded.last_unit_cost,
  is_preferred = excluded.is_preferred,
  is_active = true;

-- Add presentation-friendly size choices while keeping prepared drinks
-- untracked at ingredient level.
with desired(base_sku, sku, name, price, sort_order) as (
  values
    ('PRD-003', 'PRD-003-L', 'Large', 175::numeric, 20),
    ('PRD-004', 'PRD-004-L', 'Large', 145::numeric, 20)
)
insert into public.menu_variants(
  menu_item_id,
  sku,
  name,
  price,
  is_default,
  is_active,
  track_finished_inventory,
  finished_inventory_item_id,
  sort_order
)
select
  base.menu_item_id,
  d.sku,
  d.name,
  d.price,
  false,
  true,
  false,
  null,
  d.sort_order
from desired d
join public.menu_variants base on base.sku = d.base_sku
on conflict (sku) do update set
  name = excluded.name,
  price = excluded.price,
  is_active = true,
  track_finished_inventory = false,
  finished_inventory_item_id = null,
  sort_order = excluded.sort_order;

insert into public.modifier_groups(
  name,
  min_selections,
  max_selections,
  is_required,
  is_active,
  sort_order
)
values
  ('Bowl Add-ons', 0, 2, false, true, 10),
  ('Coffee Sweetness', 1, 1, true, true, 10)
on conflict (name) do update set
  min_selections = excluded.min_selections,
  max_selections = excluded.max_selections,
  is_required = excluded.is_required,
  is_active = true,
  sort_order = excluded.sort_order;

with desired(group_name, name, price_delta, sort_order) as (
  values
    ('Bowl Add-ons', 'Extra Egg', 25::numeric, 10),
    ('Bowl Add-ons', 'Extra Rice', 20::numeric, 20),
    ('Bowl Add-ons', 'Cheese', 20::numeric, 30),
    ('Coffee Sweetness', 'No Sugar', 0::numeric, 10),
    ('Coffee Sweetness', 'Less Sweet', 0::numeric, 20),
    ('Coffee Sweetness', 'Regular Sweetness', 0::numeric, 30)
)
insert into public.modifiers(
  modifier_group_id,
  name,
  price_delta,
  is_active,
  sort_order
)
select
  mg.id,
  d.name,
  d.price_delta,
  true,
  d.sort_order
from desired d
join public.modifier_groups mg on mg.name = d.group_name
on conflict (modifier_group_id, name) do update set
  price_delta = excluded.price_delta,
  is_active = true,
  sort_order = excluded.sort_order;

with desired(menu_sku, group_name, sort_order) as (
  values
    ('PRD-001', 'Bowl Add-ons', 10),
    ('PRD-002', 'Bowl Add-ons', 10),
    ('PRD-003', 'Coffee Sweetness', 10),
    ('PRD-004', 'Coffee Sweetness', 10)
)
insert into public.menu_item_modifier_groups(
  menu_item_id,
  modifier_group_id,
  sort_order
)
select
  mv.menu_item_id,
  mg.id,
  d.sort_order
from desired d
join public.menu_variants mv on mv.sku = d.menu_sku
join public.modifier_groups mg on mg.name = d.group_name
on conflict (menu_item_id, modifier_group_id) do update set
  sort_order = excluded.sort_order;
