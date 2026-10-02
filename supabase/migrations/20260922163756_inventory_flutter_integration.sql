-- Read model and atomic creation helper for the Flutter inventory module.

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
  coalesce(vs.current_quantity,0)::numeric(14,4) as current_quantity,
  (
    select min(il.expiration_date)
    from public.inventory_lots il
    where il.inventory_item_id = ii.id
      and il.remaining_quantity > 0
      and il.status = 'AVAILABLE'
      and il.expiration_date is not null
  ) as next_expiration_date
from public.inventory_items ii
join public.units_of_measure u on u.id = ii.base_uom_id
left join public.inventory_categories ic on ic.id = ii.category_id
left join public.v_inventory_stock vs on vs.inventory_item_id = ii.id
where ii.is_active = true;

grant select on public.v_inventory_catalog to authenticated;
revoke all on public.v_inventory_catalog from anon;

create or replace function public.create_inventory_item_with_initial_stock(
  p_name text,
  p_category_id uuid,
  p_base_uom_id uuid,
  p_sku text default null,
  p_track_expiry boolean default false,
  p_reorder_level numeric default 0,
  p_initial_quantity numeric default 0,
  p_expiration_date date default null,
  p_unit_cost_base numeric default 0
)
returns public.inventory_items
language plpgsql
security definer
set search_path = public
as $$
declare
  v_item public.inventory_items%rowtype;
begin
  if not public.has_permission('inventory.manage') then
    raise exception 'Permission denied';
  end if;

  if nullif(btrim(coalesce(p_name,'')), '') is null then
    raise exception 'Item name is required';
  end if;

  if p_reorder_level is null or p_reorder_level < 0 then
    raise exception 'Reorder level cannot be negative';
  end if;

  if p_initial_quantity is null or p_initial_quantity < 0 then
    raise exception 'Initial quantity cannot be negative';
  end if;

  if not exists (
    select 1 from public.units_of_measure
    where id = p_base_uom_id and is_active = true
  ) then
    raise exception 'Invalid unit of measure';
  end if;

  if p_category_id is not null and not exists (
    select 1 from public.inventory_categories
    where id = p_category_id and is_active = true
  ) then
    raise exception 'Invalid inventory category';
  end if;

  if coalesce(p_track_expiry,false)
     and p_initial_quantity > 0
     and p_expiration_date is null then
    raise exception 'Expiration date is required for initial stock';
  end if;

  insert into public.inventory_items(
    sku,
    name,
    category_id,
    base_uom_id,
    track_inventory,
    track_expiry,
    allow_negative_stock,
    reorder_level,
    is_active
  )
  values (
    nullif(btrim(coalesce(p_sku,'')), ''),
    btrim(p_name),
    p_category_id,
    p_base_uom_id,
    true,
    coalesce(p_track_expiry,false),
    false,
    p_reorder_level,
    true
  )
  returning * into v_item;

  if p_initial_quantity > 0 then
    if not public.has_permission('inventory.adjust') then
      raise exception 'Inventory adjustment permission is required for initial stock';
    end if;

    perform public.adjust_inventory_stock(
      v_item.id,
      'MANUAL_IN',
      p_initial_quantity,
      'Initial stock',
      p_expiration_date,
      greatest(coalesce(p_unit_cost_base,0),0)
    );
  end if;

  return v_item;
end;
$$;

revoke all on function public.create_inventory_item_with_initial_stock(
  text,uuid,uuid,text,boolean,numeric,numeric,date,numeric
) from public, anon;

grant execute on function public.create_inventory_item_with_initial_stock(
  text,uuid,uuid,text,boolean,numeric,numeric,date,numeric
) to authenticated;
