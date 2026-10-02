-- Exact-lot inventory disposal for expiry, damage, and waste handling.

create or replace view public.v_inventory_lots
with (security_invoker = true)
as
select
  il.id as lot_id,
  il.inventory_item_id,
  ii.name as item_name,
  il.lot_code,
  il.received_at,
  il.expiration_date,
  il.received_quantity,
  il.remaining_quantity,
  il.unit_cost_base,
  il.status,
  u.code as uom_code
from public.inventory_lots il
join public.inventory_items ii on ii.id = il.inventory_item_id
join public.units_of_measure u on u.id = ii.base_uom_id
where il.remaining_quantity > 0
  and il.status = 'AVAILABLE';

grant select on public.v_inventory_lots to authenticated;
revoke all on public.v_inventory_lots from anon;

create or replace function public.dispose_inventory_lot(
  p_inventory_lot_id uuid,
  p_movement_type text,
  p_quantity numeric,
  p_reason text default null
)
returns public.inventory_lots
language plpgsql
security definer
set search_path = public
as $$
declare
  v_lot public.inventory_lots%rowtype;
  v_type text;
begin
  if not public.has_permission('inventory.adjust') then
    raise exception 'Permission denied';
  end if;

  v_type := upper(btrim(coalesce(p_movement_type,'')));

  if v_type not in ('WASTE','DAMAGED','EXPIRED') then
    raise exception 'Lot disposal type must be WASTE, DAMAGED, or EXPIRED';
  end if;

  if p_quantity is null or p_quantity <= 0 then
    raise exception 'Quantity must be greater than zero';
  end if;

  select *
  into v_lot
  from public.inventory_lots
  where id = p_inventory_lot_id
  for update;

  if not found or v_lot.status <> 'AVAILABLE' or v_lot.remaining_quantity <= 0 then
    raise exception 'Inventory lot is unavailable';
  end if;

  if p_quantity > v_lot.remaining_quantity then
    raise exception 'Quantity exceeds remaining lot stock';
  end if;

  update public.inventory_lots
  set
    remaining_quantity = remaining_quantity - p_quantity,
    status = case
      when remaining_quantity - p_quantity <= 0 then 'DEPLETED'
      else status
    end
  where id = p_inventory_lot_id
  returning * into v_lot;

  insert into public.stock_movements(
    inventory_item_id,
    inventory_lot_id,
    movement_type,
    quantity_delta,
    unit_cost_base,
    reference_type,
    reference_id,
    reason,
    recorded_by
  )
  values (
    v_lot.inventory_item_id,
    v_lot.id,
    v_type,
    -p_quantity,
    v_lot.unit_cost_base,
    'LOT_DISPOSAL',
    v_lot.id,
    coalesce(
      nullif(btrim(coalesce(p_reason,'')), ''),
      initcap(replace(lower(v_type),'_',' '))
    ),
    auth.uid()
  );

  return v_lot;
end;
$$;

revoke all on function public.dispose_inventory_lot(uuid,text,numeric,text)
from public, anon;
grant execute on function public.dispose_inventory_lot(uuid,text,numeric,text)
to authenticated;
