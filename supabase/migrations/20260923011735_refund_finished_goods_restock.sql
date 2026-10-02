-- Explicit refund restocking for returned finished goods.
-- Recipe-driven products are intentionally excluded because consumed ingredients
-- should not be recreated when prepared food/drinks are refunded.

create or replace view public.v_refund_restock_candidates
with (security_invoker = true)
as
select
  r.id as refund_id,
  r.refund_number,
  r.order_id,
  ri.id as refund_item_id,
  ri.order_item_id,
  ri.quantity as refunded_quantity,
  ri.restock_approved,
  ri.notes,
  oi.item_name_snapshot,
  oi.variant_name_snapshot,
  oi.menu_variant_id,
  mv.track_finished_inventory,
  mv.finished_inventory_item_id,
  ii.name as inventory_item_name,
  case
    when mv.track_finished_inventory = true
      and mv.finished_inventory_item_id is not null
      then true
    else false
  end as eligible_for_restock
from public.refund_items ri
join public.refunds r on r.id = ri.refund_id
join public.order_items oi on oi.id = ri.order_item_id
left join public.menu_variants mv on mv.id = oi.menu_variant_id
left join public.inventory_items ii on ii.id = mv.finished_inventory_item_id
where r.status = 'COMPLETED';

grant select on public.v_refund_restock_candidates to authenticated;
revoke all on public.v_refund_restock_candidates from anon;

create or replace function public.approve_refund_item_restock(
  p_refund_item_id uuid,
  p_notes text default null
)
returns public.refund_items
language plpgsql
security definer
set search_path = public
as $$
declare
  v_refund_item public.refund_items%rowtype;
  v_refund public.refunds%rowtype;
  v_order_item public.order_items%rowtype;
  v_variant public.menu_variants%rowtype;
  v_sale_movement public.stock_movements%rowtype;
  v_lot public.inventory_lots%rowtype;
  v_already_restored numeric(14,4);
  v_capacity numeric(14,4);
  v_take numeric(14,4);
  v_remaining numeric(14,4);
begin
  if not public.has_permission('inventory.adjust')
     or not public.has_permission('orders.refund') then
    raise exception 'Permission denied';
  end if;

  select *
  into v_refund_item
  from public.refund_items
  where id = p_refund_item_id
  for update;

  if not found then
    raise exception 'Refund item not found';
  end if;

  if v_refund_item.restock_approved then
    raise exception 'Refund item was already restocked';
  end if;

  select *
  into v_refund
  from public.refunds
  where id = v_refund_item.refund_id;

  if not found or v_refund.status <> 'COMPLETED' then
    raise exception 'Only completed refunds can be restocked';
  end if;

  select *
  into v_order_item
  from public.order_items
  where id = v_refund_item.order_item_id;

  if not found then
    raise exception 'Original order item not found';
  end if;

  select *
  into v_variant
  from public.menu_variants
  where id = v_order_item.menu_variant_id;

  if not found
     or not v_variant.track_finished_inventory
     or v_variant.finished_inventory_item_id is null then
    raise exception
      'Only finished-goods variants can be restocked automatically';
  end if;

  v_remaining := v_refund_item.quantity;

  for v_sale_movement in
    select sm.*
    from public.stock_movements sm
    where sm.order_item_id = v_order_item.id
      and sm.inventory_item_id = v_variant.finished_inventory_item_id
      and sm.movement_type = 'SALE_CONSUMPTION'
      and sm.quantity_delta < 0
      and sm.inventory_lot_id is not null
    order by sm.created_at, sm.id
  loop
    exit when v_remaining <= 0;

    select coalesce(sum(sm.quantity_delta),0)
    into v_already_restored
    from public.stock_movements sm
    where sm.order_item_id = v_order_item.id
      and sm.inventory_lot_id = v_sale_movement.inventory_lot_id
      and sm.movement_type = 'REFUND_RESTOCK'
      and sm.quantity_delta > 0;

    v_capacity :=
      abs(v_sale_movement.quantity_delta) - coalesce(v_already_restored,0);

    if v_capacity <= 0 then
      continue;
    end if;

    v_take := least(v_remaining, v_capacity);

    select *
    into v_lot
    from public.inventory_lots
    where id = v_sale_movement.inventory_lot_id
    for update;

    if not found then
      raise exception 'Original inventory lot no longer exists';
    end if;

    update public.inventory_lots
    set
      remaining_quantity = remaining_quantity + v_take,
      status = 'AVAILABLE'
    where id = v_lot.id;

    insert into public.stock_movements(
      inventory_item_id,
      inventory_lot_id,
      movement_type,
      quantity_delta,
      unit_cost_base,
      reference_type,
      reference_id,
      order_id,
      order_item_id,
      reason,
      recorded_by
    )
    values (
      v_variant.finished_inventory_item_id,
      v_lot.id,
      'REFUND_RESTOCK',
      v_take,
      v_sale_movement.unit_cost_base,
      'REFUND_ITEM',
      v_refund_item.id,
      v_refund.order_id,
      v_order_item.id,
      coalesce(
        nullif(btrim(coalesce(p_notes,'')), ''),
        'Approved refund restock'
      ),
      auth.uid()
    );

    v_remaining := v_remaining - v_take;
  end loop;

  if v_remaining > 0 then
    raise exception
      'Unable to restock the full refunded quantity from original inventory lots';
  end if;

  update public.refund_items
  set
    restock_approved = true,
    notes = concat_ws(
      E'\n',
      notes,
      nullif(btrim(coalesce(p_notes,'')), '')
    )
  where id = p_refund_item_id
  returning * into v_refund_item;

  insert into public.audit_logs(
    actor_user_id,
    action_code,
    entity_type,
    entity_id,
    new_data
  )
  values (
    auth.uid(),
    'REFUND_RESTOCK_APPROVED',
    'refund_item',
    p_refund_item_id::text,
    jsonb_build_object(
      'refund_id',v_refund_item.refund_id,
      'order_item_id',v_refund_item.order_item_id,
      'quantity',v_refund_item.quantity
    )
  );

  return v_refund_item;
end;
$$;

revoke all on function public.approve_refund_item_restock(uuid,text)
from public, anon;
grant execute on function public.approve_refund_item_restock(uuid,text)
to authenticated;
