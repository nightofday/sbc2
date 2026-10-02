-- OPS-02: accept sales made at a till while it was offline.
--
-- The app keeps a sale it could not send in a queue on the device, with the
-- request ID it would have used, and sends it when the connection returns.
-- Three things differ from a live sale:
--
--   * It happened earlier. The order, payment, invoice and stock movements
--     are recorded at the time of sale, so it lands on the right business
--     day and in the right shift report.
--   * It cannot be refused for lack of stock. The goods have left the
--     counter. The sale is recorded and the item goes negative, which shows
--     up for a manager to correct with a count.
--   * The till computed the total from the menu it had cached. If the menu
--     has changed since, the server total differs; the difference is written
--     to the audit log instead of being silently absorbed.
--
-- Everything else, including permissions, discounts and modifiers, goes
-- through the same place_order_v2 a live sale uses, and the same request ID
-- makes a repeated sync return the stored order.

create or replace function public.guard_order_item_stock_availability()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_available numeric(14,4);
  v_mode text;
begin
  -- A sale already made at an offline till cannot be refused afterwards.
  if coalesce(current_setting('app.offline_sync', true), '') = 'on' then
    return new;
  end if;

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

revoke all on function public.guard_order_item_stock_availability()
from public, anon, authenticated;

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
      and (expiration_date is null or expiration_date >= (select public.business_today()))
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
    if v_item.allow_negative_stock
       or coalesce(current_setting('app.offline_sync', true), '') = 'on' then
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
        case
          when coalesce(current_setting('app.offline_sync', true), '') = 'on'
            then 'Sold at an offline till beyond the recorded stock'
          else 'Negative stock allowed: insufficient usable lot quantity'
        end
      );
    else
      raise exception 'Insufficient usable stock for inventory item %',
        p_inventory_item_id;
    end if;
  end if;
end;
$$;

revoke all on function public.consume_inventory_fefo(uuid,numeric,uuid,uuid,uuid)
from public, anon, authenticated;

create function public.sync_offline_order(
  p_order_type text,
  p_items jsonb,
  p_payment jsonb,
  p_client_request_id uuid,
  p_sold_at timestamptz,
  p_client_total numeric default null,
  p_discount jsonb default null,
  p_table_number text default null,
  p_customer_name text default null,
  p_delivery_reference text default null,
  p_notes text default null
)
returns public.orders
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_order public.orders%rowtype;
  v_already_stored boolean;
begin
  if p_client_request_id is null then
    raise exception 'An offline sale needs its request ID';
  end if;

  if p_sold_at is null then
    raise exception 'An offline sale needs the time it was made';
  end if;

  if p_sold_at > now() + interval '5 minutes' then
    raise exception 'The sale time is in the future. Check the device clock.';
  end if;

  if p_sold_at < now() - interval '7 days' then
    raise exception
      'This sale is more than 7 days old and must be entered by a manager.';
  end if;

  select exists (
    select 1
    from public.orders o
    where o.client_request_id = p_client_request_id
  )
  into v_already_stored;

  -- Seen only inside this transaction, by the stock guard and by FEFO.
  perform set_config('app.offline_sync', 'on', true);

  v_order := public.place_order_v2(
    p_order_type := p_order_type,
    p_items := p_items,
    p_payment := p_payment,
    p_discount := p_discount,
    p_table_number := p_table_number,
    p_customer_name := p_customer_name,
    p_delivery_reference := p_delivery_reference,
    p_notes := p_notes,
    p_client_request_id := p_client_request_id
  );

  perform set_config('app.offline_sync', 'off', true);

  -- A repeated sync returns the order exactly as it was stored.
  if v_already_stored then
    return v_order;
  end if;

  update public.orders
  set created_at = p_sold_at,
      completed_at = p_sold_at
  where id = v_order.id
  returning * into v_order;

  update public.payments
  set processed_at = p_sold_at
  where order_id = v_order.id;

  update public.sales_invoices
  set issued_at = p_sold_at
  where order_id = v_order.id;

  update public.stock_movements
  set created_at = p_sold_at
  where order_id = v_order.id;

  update public.order_status_history
  set created_at = p_sold_at
  where order_id = v_order.id;

  insert into public.audit_logs(
    actor_user_id, action_code, entity_type, entity_id, new_data
  )
  values (
    auth.uid(), 'OFFLINE_SALE_SYNCED', 'order', v_order.id::text,
    jsonb_build_object(
      'order_number', v_order.order_number,
      'sold_at', p_sold_at,
      'synced_at', now(),
      'server_total', v_order.total_amount,
      'client_total', p_client_total
    )
  );

  if p_client_total is not null
     and round(p_client_total, 2) <> round(v_order.total_amount, 2) then
    insert into public.audit_logs(
      actor_user_id, action_code, entity_type, entity_id, new_data
    )
    values (
      auth.uid(), 'OFFLINE_SALE_TOTAL_DIFFERENCE', 'order', v_order.id::text,
      jsonb_build_object(
        'order_number', v_order.order_number,
        'charged_at_till', round(p_client_total, 2),
        'recorded_total', v_order.total_amount,
        'difference', round(p_client_total, 2) - v_order.total_amount
      )
    );
  end if;

  return v_order;
end;
$$;

revoke all on function public.sync_offline_order(
  text,jsonb,jsonb,uuid,timestamptz,numeric,jsonb,text,text,text,text
) from public, anon;
grant execute on function public.sync_offline_order(
  text,jsonb,jsonb,uuid,timestamptz,numeric,jsonb,text,text,text,text
) to authenticated;
