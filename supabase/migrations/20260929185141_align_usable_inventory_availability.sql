-- Distinguish total on-hand stock from stock that can still be sold or
-- released. Expired lots remain on hand until an authorized disposal records
-- their removal, but they must never contribute to POS availability.

create or replace view public.v_inventory_stock
with (security_invoker = true)
as
select
  ii.id as inventory_item_id,
  ii.sku,
  ii.name,
  ii.track_inventory,
  ii.track_expiry,
  ii.reorder_level,
  ii.reorder_target,
  u.code as base_uom_code,
  coalesce(movement_totals.current_quantity, 0)::numeric(14,4)
    as current_quantity,
  coalesce(lot_totals.usable_quantity, 0)::numeric(14,4)
    as usable_quantity,
  coalesce(lot_totals.expired_quantity, 0)::numeric(14,4)
    as expired_quantity
from public.inventory_items ii
join public.units_of_measure u on u.id = ii.base_uom_id
left join (
  select
    sm.inventory_item_id,
    sum(sm.quantity_delta)::numeric(14,4) as current_quantity
  from public.stock_movements sm
  group by sm.inventory_item_id
) movement_totals on movement_totals.inventory_item_id = ii.id
left join (
  select
    il.inventory_item_id,
    coalesce(
      sum(il.remaining_quantity) filter (
        where il.status = 'AVAILABLE'
          and il.remaining_quantity > 0
          and (
            il.expiration_date is null
            or il.expiration_date >= current_date
          )
      ),
      0
    )::numeric(14,4) as usable_quantity,
    coalesce(
      sum(il.remaining_quantity) filter (
        where il.status = 'AVAILABLE'
          and il.remaining_quantity > 0
          and il.expiration_date < current_date
      ),
      0
    )::numeric(14,4) as expired_quantity
  from public.inventory_lots il
  group by il.inventory_item_id
) lot_totals on lot_totals.inventory_item_id = ii.id
where ii.is_active = true;

create or replace view public.v_low_stock
with (security_invoker = true)
as
select *
from public.v_inventory_stock
where track_inventory = true
  and usable_quantity <= reorder_level;

create or replace view public.v_inventory_catalog
with (security_invoker = true)
as
select
  ii.id as inventory_item_id,
  ii.sku,
  ii.name,
  ii.category_id,
  ic.name as category_name,
  ii.base_uom_id,
  u.code as base_uom_code,
  ii.track_inventory,
  ii.track_expiry,
  ii.reorder_level,
  ii.reorder_target,
  coalesce(vs.current_quantity, 0)::numeric(14,4) as current_quantity,
  (
    select min(il.expiration_date)
    from public.inventory_lots il
    where il.inventory_item_id = ii.id
      and il.remaining_quantity > 0
      and il.status = 'AVAILABLE'
      and il.expiration_date >= current_date
  ) as next_expiration_date,
  coalesce(vs.usable_quantity, 0)::numeric(14,4) as usable_quantity,
  coalesce(vs.expired_quantity, 0)::numeric(14,4) as expired_quantity
from public.inventory_items ii
join public.units_of_measure u on u.id = ii.base_uom_id
left join public.inventory_categories ic on ic.id = ii.category_id
left join public.v_inventory_stock vs on vs.inventory_item_id = ii.id
where ii.is_active = true;

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
      floor(coalesce(finished_stock.usable_quantity, 0))
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
      coalesce(component_stock.usable_quantity, 0)
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

-- Checkout must use the same definition of usable stock as the catalog and
-- POS views. Expired lots are intentionally left for the disposal workflow.
create or replace function public.consume_inventory_fefo(
  p_inventory_item_id uuid,
  p_quantity numeric,
  p_order_id uuid,
  p_order_item_id uuid,
  p_recorded_by uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_item public.inventory_items%rowtype;
  v_lot public.inventory_lots%rowtype;
  v_remaining numeric(14,4);
  v_take numeric(14,4);
begin
  if p_quantity <= 0 then
    raise exception 'Consumption quantity must be greater than zero';
  end if;

  select * into v_item
  from public.inventory_items
  where id = p_inventory_item_id
  for update;

  if not found then
    raise exception 'Inventory item not found';
  end if;

  if not v_item.track_inventory then
    return;
  end if;

  v_remaining := p_quantity;

  for v_lot in
    select *
    from public.inventory_lots
    where inventory_item_id = p_inventory_item_id
      and remaining_quantity > 0
      and status = 'AVAILABLE'
      and (expiration_date is null or expiration_date >= current_date)
    order by expiration_date asc nulls last, received_at asc
    for update
  loop
    exit when v_remaining <= 0;

    v_take := least(v_remaining, v_lot.remaining_quantity);

    update public.inventory_lots
    set
      remaining_quantity = remaining_quantity - v_take,
      status = case
        when remaining_quantity - v_take <= 0 then 'DEPLETED'
        else status
      end
    where id = v_lot.id;

    insert into public.stock_movements (
      inventory_item_id,
      inventory_lot_id,
      movement_type,
      quantity_delta,
      unit_cost_base,
      reference_type,
      reference_id,
      order_id,
      order_item_id,
      recorded_by
    )
    values (
      p_inventory_item_id,
      v_lot.id,
      'SALE_CONSUMPTION',
      -v_take,
      v_lot.unit_cost_base,
      'ORDER',
      p_order_id,
      p_order_id,
      p_order_item_id,
      p_recorded_by
    );

    v_remaining := v_remaining - v_take;
  end loop;

  if v_remaining > 0 then
    if v_item.allow_negative_stock then
      insert into public.stock_movements (
        inventory_item_id,
        movement_type,
        quantity_delta,
        unit_cost_base,
        reference_type,
        reference_id,
        order_id,
        order_item_id,
        recorded_by,
        reason
      )
      values (
        p_inventory_item_id,
        'SALE_CONSUMPTION',
        -v_remaining,
        0,
        'ORDER',
        p_order_id,
        p_order_id,
        p_order_item_id,
        p_recorded_by,
        'Negative stock allowed: insufficient usable lot quantity'
      );
    else
      raise exception 'Insufficient usable stock for inventory item %',
        p_inventory_item_id;
    end if;
  end if;
end;
$$;

grant select on public.v_inventory_stock,
  public.v_low_stock,
  public.v_inventory_catalog,
  public.v_pos_menu
to authenticated;

revoke all on public.v_inventory_stock,
  public.v_low_stock,
  public.v_inventory_catalog,
  public.v_pos_menu
from anon;

revoke all on function public.consume_inventory_fefo(
  uuid, numeric, uuid, uuid, uuid
) from public, anon, authenticated;
