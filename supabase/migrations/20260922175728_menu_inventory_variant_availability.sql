-- Link sellable variants to inventory and expose variant-level availability to POS.

update public.menu_variants mv
set
  track_finished_inventory = true,
  finished_inventory_item_id = ii.id
from public.menu_items mi,
     public.inventory_items ii
where mv.menu_item_id = mi.id
  and (
    (mv.sku = 'PRD-005' and ii.sku = 'INV-001')
    or
    (mv.sku = 'PRD-006' and ii.sku = 'INV-006')
  )
  and not exists (
    select 1
    from public.variant_recipe_components rc
    where rc.menu_variant_id = mv.id
  );

create or replace view public.v_pos_menu
with (security_invoker = true)
as
select
  mv.id as variant_id,
  mi.id as menu_item_id,
  mv.sku,
  mi.name as item_name,
  mv.name as variant_name,
  mc.name as category_name,
  mv.price,
  mv.sort_order as variant_sort_order,
  coalesce(mc.sort_order, 999) as category_sort_order,
  mv.is_default,
  case
    when mv.track_finished_inventory then 'FINISHED_GOOD'
    when exists (
      select 1
      from public.variant_recipe_components rc0
      where rc0.menu_variant_id = mv.id
    ) then 'RECIPE'
    else 'UNTRACKED'
  end as inventory_tracking_mode,
  case
    when mv.track_finished_inventory then
      floor(coalesce(finished_stock.current_quantity, 0))
    when exists (
      select 1
      from public.variant_recipe_components rc0
      where rc0.menu_variant_id = mv.id
    ) then
      coalesce(recipe_stock.available_quantity, 0)
    else null
  end::numeric(14,4) as available_quantity
from public.menu_variants mv
join public.menu_items mi on mi.id = mv.menu_item_id
left join public.menu_categories mc on mc.id = mi.category_id
left join public.v_inventory_stock finished_stock
  on finished_stock.inventory_item_id = mv.finished_inventory_item_id
left join lateral (
  select min(
    floor(
      coalesce(component_stock.current_quantity, 0)
      /
      nullif(
        rc.quantity_base_uom * (1 + rc.wastage_percent / 100.0),
        0
      )
    )
  )::numeric(14,4) as available_quantity
  from public.variant_recipe_components rc
  left join public.v_inventory_stock component_stock
    on component_stock.inventory_item_id = rc.inventory_item_id
  where rc.menu_variant_id = mv.id
) recipe_stock on true
where mv.is_active = true
  and mi.is_active = true;

grant select on public.v_pos_menu to authenticated;
revoke all on public.v_pos_menu from anon;

create or replace function public.guard_order_item_stock_availability()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_available numeric(14,4);
  v_mode text;
begin
  select pm.available_quantity, pm.inventory_tracking_mode
  into v_available, v_mode
  from public.v_pos_menu pm
  where pm.variant_id = new.menu_variant_id;

  if v_mode in ('FINISHED_GOOD','RECIPE')
     and coalesce(v_available,0) < new.quantity then
    raise exception 'Insufficient stock. Only % available for this variant',
      coalesce(v_available,0);
  end if;

  return new;
end;
$$;

drop trigger if exists trg_guard_order_item_stock_availability
on public.order_items;

create trigger trg_guard_order_item_stock_availability
before insert or update of menu_variant_id, quantity
on public.order_items
for each row execute function public.guard_order_item_stock_availability();

revoke all on function public.guard_order_item_stock_availability()
from public, anon, authenticated;
