-- Phase 4: post one physical inventory count containing many items.

alter table public.stock_count_items
  add column if not exists adjustment_expiration_date date,
  add column if not exists unit_cost_base numeric(14,6) not null default 0
    check (unit_cost_base >= 0);

create index if not exists idx_stock_count_items_inventory_item
  on public.stock_count_items(inventory_item_id, stock_count_id);

create or replace view public.v_stock_count_summary
with (security_invoker = true)
as
select
  sc.id,
  sc.count_number,
  sc.status,
  sc.counted_at,
  sc.posted_at,
  sc.notes,
  sc.counted_by,
  coalesce(p.display_name, concat_ws(' ', p.first_name, p.last_name))
    as counted_by_name,
  count(sci.id)::integer as item_count,
  count(sci.id) filter (where sci.variance_quantity <> 0)::integer
    as variance_item_count
from public.stock_counts sc
left join public.profiles p on p.id = sc.counted_by
left join public.stock_count_items sci on sci.stock_count_id = sc.id
group by sc.id, p.display_name, p.first_name, p.last_name;

grant select on public.v_stock_count_summary to authenticated;
revoke all on public.v_stock_count_summary from anon;

create or replace function public.create_and_post_stock_count(
  p_items jsonb,
  p_notes text default null,
  p_counted_at timestamptz default now()
)
returns public.stock_counts
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count public.stock_counts%rowtype;
  v_item public.inventory_items%rowtype;
  v_line jsonb;
  v_lot public.inventory_lots%rowtype;
  v_inventory_item_id uuid;
  v_counted_quantity numeric(14,4);
  v_system_quantity numeric(14,4);
  v_variance numeric(14,4);
  v_remaining numeric(14,4);
  v_take numeric(14,4);
  v_expiration_date date;
  v_unit_cost_base numeric(14,6);
  v_line_notes text;
  v_new_lot_id uuid;
  v_reason text;
begin
  if not public.has_permission('inventory.adjust') then
    raise exception 'Permission denied';
  end if;

  if jsonb_typeof(coalesce(p_items, '[]'::jsonb)) <> 'array'
     or jsonb_array_length(coalesce(p_items, '[]'::jsonb)) = 0 then
    raise exception 'At least one counted item is required';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(p_items) line
    group by line ->> 'inventory_item_id'
    having count(*) > 1
  ) then
    raise exception 'Each inventory item may appear only once per count';
  end if;

  insert into public.stock_counts(
    status, counted_at, counted_by, notes
  )
  values (
    'DRAFT', coalesce(p_counted_at, now()), auth.uid(),
    nullif(btrim(coalesce(p_notes, '')), '')
  )
  returning * into v_count;

  for v_line in
    select value
    from jsonb_array_elements(p_items)
    order by value ->> 'inventory_item_id'
  loop
    v_inventory_item_id :=
      nullif(v_line ->> 'inventory_item_id', '')::uuid;
    v_counted_quantity :=
      nullif(v_line ->> 'counted_quantity', '')::numeric;
    v_expiration_date :=
      nullif(v_line ->> 'adjustment_expiration_date', '')::date;
    v_unit_cost_base := coalesce(
      nullif(v_line ->> 'unit_cost_base', '')::numeric,
      0
    );
    v_line_notes := nullif(btrim(coalesce(v_line ->> 'notes', '')), '');

    if v_inventory_item_id is null or v_counted_quantity is null then
      raise exception 'Inventory item and counted quantity are required';
    end if;

    if v_counted_quantity < 0 or v_unit_cost_base < 0 then
      raise exception 'Counted quantity and unit cost cannot be negative';
    end if;

    select * into v_item
    from public.inventory_items
    where id = v_inventory_item_id
      and is_active = true
      and track_inventory = true
    for update;

    if not found then
      raise exception 'Tracked inventory item is unavailable';
    end if;

    perform 1
    from public.inventory_lots
    where inventory_item_id = v_inventory_item_id
      and remaining_quantity > 0
      and status = 'AVAILABLE'
    for update;

    select coalesce(sum(remaining_quantity), 0)::numeric(14,4)
    into v_system_quantity
    from public.inventory_lots
    where inventory_item_id = v_inventory_item_id
      and remaining_quantity > 0
      and status = 'AVAILABLE';

    v_variance := v_counted_quantity - v_system_quantity;

    if v_variance > 0 and v_item.track_expiry
       and v_expiration_date is null then
      raise exception 'Expiration date is required for positive variance on item %',
        v_item.name;
    end if;

    insert into public.stock_count_items(
      stock_count_id, inventory_item_id, system_quantity,
      counted_quantity, variance_quantity, notes,
      adjustment_expiration_date, unit_cost_base
    )
    values (
      v_count.id, v_inventory_item_id, v_system_quantity,
      v_counted_quantity, v_variance, v_line_notes,
      v_expiration_date, v_unit_cost_base
    );

    v_reason := 'Physical count IC-' || v_count.count_number::text;
    if v_line_notes is not null then
      v_reason := v_reason || ': ' || v_line_notes;
    end if;

    if v_variance > 0 then
      insert into public.inventory_lots(
        inventory_item_id, lot_code, received_at, expiration_date,
        received_quantity, remaining_quantity, unit_cost_base
      )
      values (
        v_inventory_item_id,
        'COUNT-' || v_count.count_number::text || '-' ||
          substr(v_inventory_item_id::text, 1, 8),
        coalesce(p_counted_at, now()), v_expiration_date,
        v_variance, v_variance, v_unit_cost_base
      )
      returning id into v_new_lot_id;

      insert into public.stock_movements(
        inventory_item_id, inventory_lot_id, movement_type,
        quantity_delta, unit_cost_base, reference_type, reference_id,
        reason, recorded_by
      )
      values (
        v_inventory_item_id, v_new_lot_id, 'STOCK_COUNT_ADJUSTMENT',
        v_variance, v_unit_cost_base, 'STOCK_COUNT', v_count.id,
        v_reason, auth.uid()
      );
    elsif v_variance < 0 then
      v_remaining := abs(v_variance);

      for v_lot in
        select *
        from public.inventory_lots
        where inventory_item_id = v_inventory_item_id
          and remaining_quantity > 0
          and status = 'AVAILABLE'
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

        insert into public.stock_movements(
          inventory_item_id, inventory_lot_id, movement_type,
          quantity_delta, unit_cost_base, reference_type, reference_id,
          reason, recorded_by
        )
        values (
          v_inventory_item_id, v_lot.id, 'STOCK_COUNT_ADJUSTMENT',
          -v_take, v_lot.unit_cost_base, 'STOCK_COUNT', v_count.id,
          v_reason, auth.uid()
        );

        v_remaining := v_remaining - v_take;
      end loop;

      if v_remaining > 0 then
        raise exception 'Insufficient on-hand stock for item %', v_item.name;
      end if;
    end if;
  end loop;

  update public.stock_counts
  set status = 'POSTED', posted_by = auth.uid(), posted_at = now()
  where id = v_count.id
  returning * into v_count;

  insert into public.audit_logs(
    actor_user_id, action_code, entity_type, entity_id, new_data
  )
  values (
    auth.uid(), 'STOCK_COUNT_POSTED', 'stock_count', v_count.id::text,
    jsonb_build_object(
      'count_number', v_count.count_number,
      'item_count', jsonb_array_length(p_items),
      'notes', v_count.notes
    )
  );

  return v_count;
end;
$$;

revoke all on function public.create_and_post_stock_count(
  jsonb,text,timestamptz
) from public, anon;
grant execute on function public.create_and_post_stock_count(
  jsonb,text,timestamptz
) to authenticated;

create or replace view public.v_inventory_movement_history
with (security_invoker = true)
as
select
  sm.id,
  sm.inventory_item_id,
  sm.inventory_lot_id,
  sm.movement_type,
  sm.quantity_delta,
  sm.unit_cost_base,
  sm.reference_type,
  sm.reference_id,
  sm.order_id,
  sm.order_item_id,
  sm.stock_out_item_id,
  sm.reason,
  sm.recorded_by,
  sm.created_at,
  case
    when sm.reference_type = 'STOCK_OUT' then
      'SO-' || so.stock_out_number::text
    when sm.reference_type = 'GOODS_RECEIPT' then
      'GR-' || gr.receipt_number::text
    when sm.reference_type = 'ORDER' then
      'ORD-' || o.order_number::text
    when sm.reference_type = 'STOCK_COUNT' then
      'IC-' || sc.count_number::text
    else null
  end as source_document_number,
  case
    when sm.reference_type = 'STOCK_OUT' then so.reference_number
    when sm.reference_type = 'GOODS_RECEIPT' then gr.supplier_invoice_number
    else null
  end as external_reference_number
from public.stock_movements sm
left join public.stock_out_transactions so
  on sm.reference_type = 'STOCK_OUT' and so.id = sm.reference_id
left join public.goods_receipts gr
  on sm.reference_type = 'GOODS_RECEIPT' and gr.id = sm.reference_id
left join public.orders o
  on sm.reference_type = 'ORDER' and o.id = sm.reference_id
left join public.stock_counts sc
  on sm.reference_type = 'STOCK_COUNT' and sc.id = sm.reference_id;

grant select on public.v_inventory_movement_history to authenticated;
revoke all on public.v_inventory_movement_history from anon;
