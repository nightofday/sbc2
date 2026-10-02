-- Reversals, a complete transaction trace, remembered package sizes and a
-- stock consistency check.
--
-- 1. A supplier payment entered by mistake can be reversed. The reversal is
--    a second, negative payment linked to the first, so every existing sum
--    (bill balance, bill status, reports) stays right without change and
--    nothing is deleted. (S-05)
-- 2. A stock write-off (waste, damaged, expired) can be reversed. The
--    quantity returns to its lot through a REVERSAL movement linked to the
--    write-off. The business report takes it off the losses on the day of
--    the reversal. (S-05)
--    A manual stock adjustment has no separate reversal: the correction
--    for a wrong adjustment is another adjustment, which is already
--    recorded with who and why.
-- 3. Voided sales, receipts, releases, counts and expenses used to vanish
--    from the transaction trace. They now stay, marked VOIDED, with the
--    reason. (TRACE-01)
-- 4. Receiving stock records the supplier's package size and latest cost
--    in supplier_items, which nothing wrote before, so the next receipt or
--    release does not have to ask again. (INV-01, F-14)
-- 5. check_stock_consistency() lists any lot whose balance disagrees with
--    its movements. (S-09)

-- 1. Supplier payment reversal -----------------------------------------------

alter table public.supplier_bill_payments
  drop constraint supplier_bill_payments_amount_check;

alter table public.supplier_bill_payments
  add column reverses_payment_id uuid
    references public.supplier_bill_payments(id);

-- A payment is positive; only a reversal is negative.
alter table public.supplier_bill_payments
  add constraint supplier_bill_payments_amount_check
    check (
      (reverses_payment_id is null and amount > 0)
      or (reverses_payment_id is not null and amount < 0)
    );

-- A payment can be reversed once.
create unique index uq_supplier_bill_payment_reversal
  on public.supplier_bill_payments (reverses_payment_id)
  where reverses_payment_id is not null;

create function public.void_supplier_bill_payment(
  p_payment_id uuid,
  p_reason text,
  p_client_request_id uuid default null
)
returns public.supplier_bill_payments
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_request_result uuid;
  v_payment public.supplier_bill_payments%rowtype;
  v_reversal public.supplier_bill_payments%rowtype;
  v_reason text := nullif(btrim(coalesce(p_reason, '')), '');
begin
  v_request_result := public.claim_client_request(
    p_client_request_id, 'VOID_SUPPLIER_BILL_PAYMENT'
  );
  if v_request_result is not null then
    select * into v_reversal
    from public.supplier_bill_payments
    where id = v_request_result;
    return v_reversal;
  end if;

  if not public.has_permission('finance.manage') then
    raise exception 'Permission denied';
  end if;

  if v_reason is null then
    raise exception 'A reason is required to reverse a supplier payment';
  end if;

  select * into v_payment
  from public.supplier_bill_payments
  where id = p_payment_id
  for update;

  if not found or v_payment.reverses_payment_id is not null then
    raise exception 'Only a payment can be reversed';
  end if;

  if exists (
    select 1
    from public.supplier_bill_payments r
    where r.reverses_payment_id = p_payment_id
  ) then
    raise exception 'This payment has already been reversed';
  end if;

  insert into public.supplier_bill_payments(
    supplier_bill_id, payment_method_id, amount, reference_number,
    recorded_by, notes, reverses_payment_id
  )
  values (
    v_payment.supplier_bill_id, v_payment.payment_method_id,
    -v_payment.amount, v_payment.reference_number,
    auth.uid(), v_reason, v_payment.id
  )
  returning * into v_reversal;

  perform public.sync_supplier_bill_status(v_payment.supplier_bill_id);

  insert into public.audit_logs(
    actor_user_id, action_code, entity_type, entity_id, new_data
  )
  values (
    auth.uid(), 'SUPPLIER_PAYMENT_REVERSED', 'supplier_bill_payment',
    v_payment.id::text,
    jsonb_build_object('amount', v_payment.amount, 'reason', v_reason)
  );

  perform public.record_client_request(
    p_client_request_id, 'VOID_SUPPLIER_BILL_PAYMENT', v_reversal.id
  );

  return v_reversal;
end;
$$;

revoke all on function public.void_supplier_bill_payment(uuid, text, uuid)
  from public, anon;
grant execute on function public.void_supplier_bill_payment(uuid, text, uuid)
  to authenticated;

create view public.v_supplier_bill_payments
with (security_invoker = true)
as
select
  sbp.id,
  sbp.supplier_bill_id,
  s.name as supplier_name,
  sb.supplier_invoice_number,
  sbp.paid_at,
  pm.name as payment_method,
  sbp.amount,
  sbp.reference_number,
  sbp.notes,
  coalesce(
    nullif(btrim(p.display_name), ''),
    nullif(btrim(concat_ws(' ', p.first_name, p.last_name)), ''),
    'Unknown Employee'
  ) as recorded_by_name,
  sbp.reverses_payment_id is not null as is_reversal,
  exists (
    select 1
    from public.supplier_bill_payments r
    where r.reverses_payment_id = sbp.id
  ) as is_reversed
from public.supplier_bill_payments sbp
join public.supplier_bills sb on sb.id = sbp.supplier_bill_id
join public.suppliers s on s.id = sb.supplier_id
join public.payment_methods pm on pm.id = sbp.payment_method_id
left join public.profiles p on p.id = sbp.recorded_by;

revoke all on public.v_supplier_bill_payments from public, anon;
grant select on public.v_supplier_bill_payments to authenticated;

-- 2. Stock write-off reversal --------------------------------------------------

create function public.void_lot_disposal(
  p_stock_movement_id uuid,
  p_reason text,
  p_client_request_id uuid default null
)
returns public.inventory_lots
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_request_result uuid;
  v_move public.stock_movements%rowtype;
  v_lot public.inventory_lots%rowtype;
  v_reason text := nullif(btrim(coalesce(p_reason, '')), '');
begin
  v_request_result := public.claim_client_request(
    p_client_request_id, 'VOID_LOT_DISPOSAL'
  );
  if v_request_result is not null then
    select * into v_lot from public.inventory_lots where id = v_request_result;
    return v_lot;
  end if;

  if not public.has_permission('inventory.adjust') then
    raise exception 'Permission denied';
  end if;

  if v_reason is null then
    raise exception 'A reason is required to reverse a stock write-off';
  end if;

  select * into v_move
  from public.stock_movements
  where id = p_stock_movement_id;

  if not found
     or v_move.reference_type <> 'LOT_DISPOSAL'
     or v_move.movement_type not in ('WASTE', 'DAMAGED', 'EXPIRED')
     or v_move.inventory_lot_id is null then
    raise exception 'Only a stock write-off can be reversed';
  end if;

  select * into v_lot
  from public.inventory_lots
  where id = v_move.inventory_lot_id
  for update;

  if exists (
    select 1
    from public.stock_movements r
    where r.movement_type = 'REVERSAL'
      and r.reference_type = 'LOT_DISPOSAL_VOID'
      and r.reference_id = p_stock_movement_id
  ) then
    raise exception 'This write-off has already been reversed';
  end if;

  update public.inventory_lots
  set remaining_quantity = remaining_quantity + abs(v_move.quantity_delta),
      status = case when status = 'DEPLETED' then 'AVAILABLE' else status end
  where id = v_lot.id
  returning * into v_lot;

  insert into public.stock_movements(
    inventory_item_id, inventory_lot_id, movement_type, quantity_delta,
    unit_cost_base, reference_type, reference_id, reason, recorded_by
  )
  values (
    v_move.inventory_item_id, v_move.inventory_lot_id, 'REVERSAL',
    abs(v_move.quantity_delta), v_move.unit_cost_base,
    'LOT_DISPOSAL_VOID', v_move.id,
    'Reversal of write-off: ' || v_reason,
    auth.uid()
  );

  insert into public.audit_logs(
    actor_user_id, action_code, entity_type, entity_id, new_data
  )
  values (
    auth.uid(), 'LOT_DISPOSAL_VOIDED', 'stock_movement', v_move.id::text,
    jsonb_build_object(
      'quantity', abs(v_move.quantity_delta),
      'written_off_as', v_move.movement_type,
      'reason', v_reason
    )
  );

  perform public.record_client_request(
    p_client_request_id, 'VOID_LOT_DISPOSAL', v_lot.id
  );

  return v_lot;
end;
$$;

revoke all on function public.void_lot_disposal(uuid, text, uuid)
  from public, anon;
grant execute on function public.void_lot_disposal(uuid, text, uuid)
  to authenticated;

-- 4. Remembered package sizes ----------------------------------------------------

create function public.remember_supplier_item()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_supplier_id uuid;
begin
  select gr.supplier_id into v_supplier_id
  from public.goods_receipts gr
  where gr.id = new.goods_receipt_id;

  if v_supplier_id is null or new.purchase_uom_id is null then
    return new;
  end if;

  insert into public.supplier_items(
    supplier_id, inventory_item_id, purchase_uom_id,
    base_quantity_per_purchase_unit, last_unit_cost
  )
  values (
    v_supplier_id, new.inventory_item_id, new.purchase_uom_id,
    new.base_quantity_per_purchase_unit, new.unit_cost_purchase_uom
  )
  on conflict (supplier_id, inventory_item_id, purchase_uom_id)
  do update
  set base_quantity_per_purchase_unit =
        excluded.base_quantity_per_purchase_unit,
      last_unit_cost = excluded.last_unit_cost,
      is_active = true,
      updated_at = now();

  return new;
end;
$$;

revoke all on function public.remember_supplier_item()
  from public, anon, authenticated;

create trigger trg_remember_supplier_item
after insert on public.goods_receipt_items
for each row execute function public.remember_supplier_item();

-- What has already been received teaches the same thing: the most recent
-- receipt of each supplier, item and unit wins.
insert into public.supplier_items(
  supplier_id, inventory_item_id, purchase_uom_id,
  base_quantity_per_purchase_unit, last_unit_cost
)
select distinct on (gr.supplier_id, gri.inventory_item_id, gri.purchase_uom_id)
  gr.supplier_id, gri.inventory_item_id, gri.purchase_uom_id,
  gri.base_quantity_per_purchase_unit, gri.unit_cost_purchase_uom
from public.goods_receipt_items gri
join public.goods_receipts gr on gr.id = gri.goods_receipt_id
where gr.status = 'POSTED'
  and gri.purchase_uom_id is not null
  and gri.base_quantity_per_purchase_unit > 0
order by
  gr.supplier_id, gri.inventory_item_id, gri.purchase_uom_id,
  coalesce(gr.posted_at, gr.received_at) desc
on conflict (supplier_id, inventory_item_id, purchase_uom_id) do nothing;

-- 5. Stock consistency -------------------------------------------------------------

create function public.check_stock_consistency()
returns table (
  inventory_lot_id uuid,
  item_name text,
  lot_balance numeric,
  movement_total numeric
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    l.id,
    ii.name,
    l.remaining_quantity,
    coalesce(sum(sm.quantity_delta), 0)
  from public.inventory_lots l
  join public.inventory_items ii on ii.id = l.inventory_item_id
  left join public.stock_movements sm on sm.inventory_lot_id = l.id
  where public.has_permission('inventory.adjust')
  group by l.id, ii.name, l.remaining_quantity
  having coalesce(sum(sm.quantity_delta), 0) <> l.remaining_quantity
  order by ii.name;
$$;

revoke all on function public.check_stock_consistency() from public, anon;
grant execute on function public.check_stock_consistency() to authenticated;

-- A receipt whose payments were all reversed can be voided -----------------------

create or replace function public.void_goods_receipt(
  p_goods_receipt_id uuid,
  p_reason text,
  p_client_request_id uuid default null
)
returns public.goods_receipts
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_request_result uuid;
  v_doc public.goods_receipts%rowtype;
  v_move public.stock_movements%rowtype;
  v_lot public.inventory_lots%rowtype;
  v_bill public.supplier_bills%rowtype;
  v_expected numeric(14,4);
  v_received numeric(14,4);
  v_reason text := nullif(btrim(coalesce(p_reason, '')), '');
begin
  v_request_result := public.claim_client_request(
    p_client_request_id, 'VOID_GOODS_RECEIPT'
  );
  if v_request_result is not null then
    select * into v_doc
    from public.goods_receipts
    where id = v_request_result;
    return v_doc;
  end if;

  if not public.has_permission('purchases.manage') then
    raise exception 'Permission denied';
  end if;

  if v_reason is null then
    raise exception 'A reason is required to void a goods receipt';
  end if;

  select * into v_doc
  from public.goods_receipts
  where id = p_goods_receipt_id
  for update;

  if not found or v_doc.status <> 'POSTED' then
    raise exception 'Only a posted goods receipt can be voided';
  end if;

  select * into v_bill
  from public.supplier_bills
  where goods_receipt_id = p_goods_receipt_id
  for update;

  -- Payments that were reversed no longer count against the bill.
  if found and (
    select coalesce(sum(sbp.amount), 0)
    from public.supplier_bill_payments sbp
    where sbp.supplier_bill_id = v_bill.id
  ) <> 0 then
    raise exception
      'The supplier bill for this receipt has payments recorded, so the receipt cannot be voided. Reverse the payments first.';
  end if;

  for v_move in
    select sm.*
    from public.stock_movements sm
    where sm.reference_type = 'GOODS_RECEIPT'
      and sm.reference_id = p_goods_receipt_id
      and sm.movement_type = 'PURCHASE_RECEIPT'
    order by sm.created_at, sm.id
  loop
    select * into v_lot
    from public.inventory_lots
    where id = v_move.inventory_lot_id
    for update;

    if not found or v_lot.remaining_quantity < v_move.quantity_delta then
      raise exception
        'Some of this stock has already been sold, released or disposed. Correct the remainder by disposal or adjustment instead of voiding the receipt.';
    end if;

    update public.inventory_lots
    set remaining_quantity = remaining_quantity - v_move.quantity_delta,
        status = case
          when remaining_quantity - v_move.quantity_delta <= 0 then 'DEPLETED'
          else status
        end
    where id = v_lot.id;

    insert into public.stock_movements(
      inventory_item_id, inventory_lot_id, movement_type, quantity_delta,
      unit_cost_base, reference_type, reference_id, reason, recorded_by
    )
    values (
      v_move.inventory_item_id, v_move.inventory_lot_id, 'REVERSAL',
      -v_move.quantity_delta, v_move.unit_cost_base, 'GOODS_RECEIPT',
      p_goods_receipt_id,
      'Void of GR-' || v_doc.receipt_number::text || ': ' || v_reason,
      auth.uid()
    );
  end loop;

  if v_bill.id is not null then
    update public.supplier_bills
    set status = 'VOID'
    where id = v_bill.id;
  end if;

  update public.goods_receipts
  set status = 'CANCELLED',
      voided_at = now(),
      voided_by = auth.uid(),
      void_reason = v_reason
  where id = p_goods_receipt_id
  returning * into v_doc;

  -- A purchase order goes back to what its remaining posted receipts say.
  if v_doc.purchase_order_id is not null then
    select coalesce(sum(
      poi.ordered_quantity * poi.base_quantity_per_purchase_unit
    ), 0)
    into v_expected
    from public.purchase_order_items poi
    where poi.purchase_order_id = v_doc.purchase_order_id;

    select coalesce(sum(gri.base_quantity), 0)
    into v_received
    from public.goods_receipt_items gri
    join public.goods_receipts gr
      on gr.id = gri.goods_receipt_id
     and gr.status = 'POSTED'
    join public.purchase_order_items poi
      on poi.id = gri.purchase_order_item_id
    where poi.purchase_order_id = v_doc.purchase_order_id;

    update public.purchase_orders
    set status = case
      when v_received <= 0 then 'APPROVED'
      when v_received < v_expected then 'PARTIALLY_RECEIVED'
      else 'RECEIVED'
    end
    where id = v_doc.purchase_order_id
      and status in ('PARTIALLY_RECEIVED', 'RECEIVED');
  end if;

  insert into public.audit_logs(
    actor_user_id, action_code, entity_type, entity_id, new_data
  )
  values (
    auth.uid(), 'GOODS_RECEIPT_VOIDED', 'goods_receipt',
    p_goods_receipt_id::text,
    jsonb_build_object(
      'receipt_number', v_doc.receipt_number, 'reason', v_reason
    )
  );

  perform public.record_client_request(
    p_client_request_id, 'VOID_GOODS_RECEIPT', v_doc.id
  );

  return v_doc;
end;
$$;

-- Business report: reversed write-offs come off the losses ---------------------

create or replace function public.get_business_report(p_from date, p_to date)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tz text := public.business_timezone();
  v_start timestamptz;
  v_end timestamptz;
  v_summary jsonb;
  v_by_day jsonb;
  v_by_payment jsonb;
  v_by_item jsonb;
  v_by_category jsonb;
  v_by_discount jsonb;
  v_by_employee jsonb;
  v_refunds jsonb;
  v_expenses jsonb;
  v_losses jsonb;
  v_expired jsonb;
  v_inventory jsonb;
begin
  if not (
    public.has_permission('reports.view')
    or public.has_permission('finance.view')
  ) then
    raise exception 'Permission denied';
  end if;

  if p_from is null or p_to is null or p_to < p_from then
    raise exception 'Choose a start date that is not after the end date';
  end if;

  if p_to - p_from > 366 then
    raise exception 'A report can cover at most 366 days';
  end if;

  -- The period as timestamps, so the date indexes are used.
  v_start := p_from::timestamp at time zone v_tz;
  v_end := (p_to + 1)::timestamp at time zone v_tz;

  -- Summary ---------------------------------------------------------------
  with sales as (
    select o.subtotal, o.discount_amount
    from public.orders o
    where o.completed_at >= v_start
      and o.completed_at < v_end
      and o.status in ('COMPLETED', 'PARTIALLY_REFUNDED', 'REFUNDED')
  ),
  totals as (
    select
      coalesce(sum(s.subtotal), 0)::numeric(14,2) as gross_sales,
      coalesce(sum(s.discount_amount), 0)::numeric(14,2) as discounts,
      count(*)::integer as orders
    from sales s
  ),
  refund_totals as (
    select
      coalesce(sum(r.total_amount), 0)::numeric(14,2) as refunds,
      count(*)::integer as refund_count
    from public.refunds r
    where r.status = 'COMPLETED'
      and r.created_at >= v_start
      and r.created_at < v_end
  ),
  expense_totals as (
    select coalesce(sum(e.amount), 0)::numeric(14,2) as expenses
    from public.expenses e
    where e.status = 'POSTED'
      and e.expense_date between p_from and p_to
  ),
  purchase_totals as (
    select coalesce(
      sum(round(gri.purchase_quantity * gri.unit_cost_purchase_uom, 2)), 0
    )::numeric(14,2) as purchases
    from public.goods_receipts gr
    join public.goods_receipt_items gri on gri.goods_receipt_id = gr.id
    where gr.status = 'POSTED'
      and gr.posted_at >= v_start
      and gr.posted_at < v_end
  ),
  supplier_payment_totals as (
    select coalesce(sum(sbp.amount), 0)::numeric(14,2) as supplier_payments
    from public.supplier_bill_payments sbp
    where sbp.paid_at >= v_start
      and sbp.paid_at < v_end
  ),
  loss_totals as (
    -- A write-off that was later reversed is taken off on the day of the
    -- reversal, the same way a refund is counted on the refund date.
    select coalesce(
      sum(round(-sm.quantity_delta * sm.unit_cost_base, 2)), 0
    )::numeric(14,2) as stock_loss_cost
    from public.stock_movements sm
    where (
        sm.movement_type in ('WASTE', 'DAMAGED', 'EXPIRED')
        or (
          sm.movement_type = 'REVERSAL'
          and sm.reference_type = 'LOT_DISPOSAL_VOID'
        )
      )
      and sm.created_at >= v_start
      and sm.created_at < v_end
  )
  select jsonb_build_object(
    'gross_sales', t.gross_sales,
    'discounts', t.discounts,
    'refunds', r.refunds,
    'net_sales', t.gross_sales - t.discounts - r.refunds,
    'orders', t.orders,
    'refund_count', r.refund_count,
    'average_order', case
      when t.orders = 0 then 0
      else round((t.gross_sales - t.discounts) / t.orders, 2)
    end,
    'expenses', e.expenses,
    'net_sales_less_expenses',
      t.gross_sales - t.discounts - r.refunds - e.expenses,
    'purchases', p.purchases,
    'supplier_payments', sp.supplier_payments,
    'stock_loss_cost', l.stock_loss_cost
  )
  into v_summary
  from totals t, refund_totals r, expense_totals e, purchase_totals p,
       supplier_payment_totals sp, loss_totals l;

  -- By day ----------------------------------------------------------------
  with days as (
    select d::date as day
    from generate_series(p_from::timestamp, p_to::timestamp, interval '1 day') d
  ),
  sales as (
    select
      (o.completed_at at time zone v_tz)::date as day,
      count(*)::integer as orders,
      sum(o.subtotal) as gross_sales,
      sum(o.discount_amount) as discounts
    from public.orders o
    where o.completed_at >= v_start
      and o.completed_at < v_end
      and o.status in ('COMPLETED', 'PARTIALLY_REFUNDED', 'REFUNDED')
    group by 1
  ),
  refunded as (
    select
      (r.created_at at time zone v_tz)::date as day,
      sum(r.total_amount) as refunds
    from public.refunds r
    where r.status = 'COMPLETED'
      and r.created_at >= v_start
      and r.created_at < v_end
    group by 1
  ),
  spent as (
    select e.expense_date as day, sum(e.amount) as expenses
    from public.expenses e
    where e.status = 'POSTED'
      and e.expense_date between p_from and p_to
    group by 1
  )
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'date', d.day,
      'orders', coalesce(s.orders, 0),
      'gross_sales', coalesce(s.gross_sales, 0)::numeric(14,2),
      'discounts', coalesce(s.discounts, 0)::numeric(14,2),
      'refunds', coalesce(rf.refunds, 0)::numeric(14,2),
      'net_sales', (
        coalesce(s.gross_sales, 0) - coalesce(s.discounts, 0)
        - coalesce(rf.refunds, 0)
      )::numeric(14,2),
      'expenses', coalesce(sp.expenses, 0)::numeric(14,2)
    )
    order by d.day
  ), '[]'::jsonb)
  into v_by_day
  from days d
  left join sales s on s.day = d.day
  left join refunded rf on rf.day = d.day
  left join spent sp on sp.day = d.day;

  -- By payment method -----------------------------------------------------
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'payment_method', x.name,
      'payments', x.payments,
      'refunds', x.refunds,
      'net_collected', x.payments - x.refunds,
      'transactions', x.transactions
    )
    order by x.sort_order, x.name
  ), '[]'::jsonb)
  into v_by_payment
  from (
    select
      pm.name,
      pm.sort_order,
      coalesce(sum(p.amount) filter (
        where p.transaction_type = 'PAYMENT'
      ), 0)::numeric(14,2) as payments,
      coalesce(sum(p.amount) filter (
        where p.transaction_type = 'REFUND'
      ), 0)::numeric(14,2) as refunds,
      count(*) filter (where p.transaction_type = 'PAYMENT')::integer
        as transactions
    from public.payments p
    join public.payment_methods pm on pm.id = p.payment_method_id
    where p.status = 'COMPLETED'
      and p.processed_at >= v_start
      and p.processed_at < v_end
    group by pm.name, pm.sort_order
  ) x;

  -- By item and by category -------------------------------------------------
  with sold as (
    select
      oi.id as order_item_id,
      oi.item_name_snapshot as item_name,
      coalesce(oi.variant_name_snapshot, '') as variant_name,
      coalesce(mc.name, 'Uncategorised') as category_name,
      oi.quantity,
      oi.line_subtotal as gross_sales,
      oi.discount_amount + coalesce((
        select sum(odi.discount_amount)
        from public.order_discount_items odi
        where odi.order_item_id = oi.id
      ), 0) as discounts
    from public.order_items oi
    join public.orders o on o.id = oi.order_id
    left join public.menu_items mi on mi.id = oi.menu_item_id
    left join public.menu_categories mc on mc.id = mi.category_id
    where o.completed_at >= v_start
      and o.completed_at < v_end
      and o.status in ('COMPLETED', 'PARTIALLY_REFUNDED', 'REFUNDED')
  ),
  refunded as (
    select
      oi.item_name_snapshot as item_name,
      coalesce(oi.variant_name_snapshot, '') as variant_name,
      coalesce(mc.name, 'Uncategorised') as category_name,
      ri.quantity,
      ri.refund_amount
    from public.refund_items ri
    join public.refunds r on r.id = ri.refund_id
    join public.order_items oi on oi.id = ri.order_item_id
    left join public.menu_items mi on mi.id = oi.menu_item_id
    left join public.menu_categories mc on mc.id = mi.category_id
    where r.status = 'COMPLETED'
      and r.created_at >= v_start
      and r.created_at < v_end
  ),
  item_sales as (
    select
      item_name, variant_name, category_name,
      sum(quantity) as quantity_sold,
      sum(gross_sales) as gross_sales,
      sum(discounts) as discounts
    from sold
    group by 1, 2, 3
  ),
  item_refunds as (
    select
      item_name, variant_name, category_name,
      sum(quantity) as quantity_refunded,
      sum(refund_amount) as refunds
    from refunded
    group by 1, 2, 3
  ),
  items as (
    select
      coalesce(s.item_name, r.item_name) as item_name,
      coalesce(s.variant_name, r.variant_name) as variant_name,
      coalesce(s.category_name, r.category_name) as category_name,
      coalesce(s.quantity_sold, 0) as quantity_sold,
      coalesce(r.quantity_refunded, 0) as quantity_refunded,
      coalesce(s.gross_sales, 0) as gross_sales,
      coalesce(s.discounts, 0) as discounts,
      coalesce(r.refunds, 0) as refunds
    from item_sales s
    full outer join item_refunds r
      on r.item_name = s.item_name
     and r.variant_name = s.variant_name
     and r.category_name = s.category_name
  )
  select
    coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'item_name', i.item_name,
          'variant_name', i.variant_name,
          'category_name', i.category_name,
          'quantity_sold', i.quantity_sold,
          'quantity_refunded', i.quantity_refunded,
          'gross_sales', i.gross_sales::numeric(14,2),
          'discounts', i.discounts::numeric(14,2),
          'refunds', i.refunds::numeric(14,2),
          'net_sales', (i.gross_sales - i.discounts - i.refunds)::numeric(14,2)
        )
        order by (i.gross_sales - i.discounts - i.refunds) desc,
                 i.item_name, i.variant_name
      )
      from items i
    ), '[]'::jsonb),
    coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'category_name', c.category_name,
          'quantity_sold', c.quantity_sold,
          'gross_sales', c.gross_sales::numeric(14,2),
          'discounts', c.discounts::numeric(14,2),
          'refunds', c.refunds::numeric(14,2),
          'net_sales', (c.gross_sales - c.discounts - c.refunds)::numeric(14,2)
        )
        order by (c.gross_sales - c.discounts - c.refunds) desc,
                 c.category_name
      )
      from (
        select
          i.category_name,
          sum(i.quantity_sold) as quantity_sold,
          sum(i.gross_sales) as gross_sales,
          sum(i.discounts) as discounts,
          sum(i.refunds) as refunds
        from items i
        group by i.category_name
      ) c
    ), '[]'::jsonb)
  into v_by_item, v_by_category;

  -- By discount -------------------------------------------------------------
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'discount_name', x.discount_name,
      'times_used', x.times_used,
      'amount', x.amount
    )
    order by x.amount desc, x.discount_name
  ), '[]'::jsonb)
  into v_by_discount
  from (
    select
      od.discount_name_snapshot as discount_name,
      count(*)::integer as times_used,
      sum(od.discount_amount)::numeric(14,2) as amount
    from public.order_discounts od
    join public.orders o on o.id = od.order_id
    where o.completed_at >= v_start
      and o.completed_at < v_end
      and o.status in ('COMPLETED', 'PARTIALLY_REFUNDED', 'REFUNDED')
    group by od.discount_name_snapshot
  ) x;

  -- By employee -------------------------------------------------------------
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'employee_name', x.employee_name,
      'orders', x.orders,
      'gross_sales', x.gross_sales,
      'discounts', x.discounts,
      'sales_after_discounts', x.gross_sales - x.discounts
    )
    order by (x.gross_sales - x.discounts) desc, x.employee_name
  ), '[]'::jsonb)
  into v_by_employee
  from (
    select
      coalesce(nullif(btrim(o.employee_name_snapshot), ''), 'Unknown')
        as employee_name,
      count(*)::integer as orders,
      sum(o.subtotal)::numeric(14,2) as gross_sales,
      sum(o.discount_amount)::numeric(14,2) as discounts
    from public.orders o
    where o.completed_at >= v_start
      and o.completed_at < v_end
      and o.status in ('COMPLETED', 'PARTIALLY_REFUNDED', 'REFUNDED')
    group by 1
  ) x;

  -- Refunds -----------------------------------------------------------------
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'refund_number', r.refund_number,
      'order_number', o.order_number,
      'refunded_at', r.created_at,
      'sold_on', (o.completed_at at time zone v_tz)::date,
      'amount', r.total_amount,
      'reason', r.reason
    )
    order by r.created_at
  ), '[]'::jsonb)
  into v_refunds
  from public.refunds r
  join public.orders o on o.id = r.order_id
  where r.status = 'COMPLETED'
    and r.created_at >= v_start
    and r.created_at < v_end;

  -- Expenses by category ------------------------------------------------------
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'category_name', x.category_name,
      'entries', x.entries,
      'amount', x.amount
    )
    order by x.amount desc, x.category_name
  ), '[]'::jsonb)
  into v_expenses
  from (
    select
      ec.name as category_name,
      count(*)::integer as entries,
      sum(e.amount)::numeric(14,2) as amount
    from public.expenses e
    join public.expense_categories ec on ec.id = e.expense_category_id
    where e.status = 'POSTED'
      and e.expense_date between p_from and p_to
    group by ec.name
  ) x;

  -- Stock losses recorded in the period ----------------------------------------
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'item_name', x.item_name,
      'unit', x.unit,
      'reason', x.movement_type,
      'quantity', x.quantity,
      'cost', x.cost
    )
    order by x.cost desc, x.item_name, x.movement_type
  ), '[]'::jsonb)
  into v_losses
  from (
    select
      ii.name as item_name,
      u.code as unit,
      -- A reversal is listed under the reason of the write-off it undoes.
      coalesce(written_off.movement_type, sm.movement_type) as movement_type,
      sum(-sm.quantity_delta)::numeric(14,4) as quantity,
      sum(round(-sm.quantity_delta * sm.unit_cost_base, 2))::numeric(14,2)
        as cost
    from public.stock_movements sm
    join public.inventory_items ii on ii.id = sm.inventory_item_id
    join public.units_of_measure u on u.id = ii.base_uom_id
    left join public.stock_movements written_off
      on sm.movement_type = 'REVERSAL'
     and sm.reference_type = 'LOT_DISPOSAL_VOID'
     and written_off.id = sm.reference_id
    where (
        sm.movement_type in ('WASTE', 'DAMAGED', 'EXPIRED')
        or (
          sm.movement_type = 'REVERSAL'
          and sm.reference_type = 'LOT_DISPOSAL_VOID'
        )
      )
      and sm.created_at >= v_start
      and sm.created_at < v_end
    group by ii.name, u.code, coalesce(written_off.movement_type, sm.movement_type)
    having sum(-sm.quantity_delta) <> 0
  ) x;

  -- Expired stock still on hand today: exposure, not yet a recorded loss.
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'item_name', x.item_name,
      'unit', x.unit,
      'quantity', x.quantity,
      'cost', x.cost
    )
    order by x.item_name
  ), '[]'::jsonb)
  into v_expired
  from (
    select
      ii.name as item_name,
      u.code as unit,
      sum(il.remaining_quantity)::numeric(14,4) as quantity,
      sum(round(il.remaining_quantity * il.unit_cost_base, 2))::numeric(14,2)
        as cost
    from public.inventory_lots il
    join public.inventory_items ii on ii.id = il.inventory_item_id
    join public.units_of_measure u on u.id = ii.base_uom_id
    where il.status = 'AVAILABLE'
      and il.remaining_quantity > 0
      and il.expiration_date < (select public.business_today())
    group by ii.name, u.code
  ) x;

  -- Stock movement per item: opening + movements = closing ----------------------
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'item_name', x.item_name,
      'unit', x.unit,
      'opening', x.opening,
      'received', x.received,
      'sold', x.sold,
      'released', x.released,
      'lost', x.lost,
      'other', x.other,
      'closing', x.opening + x.received - x.sold - x.released - x.lost + x.other
    )
    order by x.item_name
  ), '[]'::jsonb)
  into v_inventory
  from (
    select
      ii.name as item_name,
      u.code as unit,
      coalesce(sum(sm.quantity_delta) filter (
        where sm.created_at < v_start
      ), 0)::numeric(14,4) as opening,
      -- A voided document's reversal is netted against the same column, so
      -- a release that was voided shows as nothing released.
      coalesce(sum(sm.quantity_delta) filter (
        where sm.created_at >= v_start
          and (
            sm.movement_type = 'PURCHASE_RECEIPT'
            or (
              sm.movement_type = 'REVERSAL'
              and sm.reference_type = 'GOODS_RECEIPT'
            )
          )
      ), 0)::numeric(14,4) as received,
      coalesce(-sum(sm.quantity_delta) filter (
        where sm.created_at >= v_start
          and sm.movement_type = 'SALE_CONSUMPTION'
      ), 0)::numeric(14,4) as sold,
      coalesce(-sum(sm.quantity_delta) filter (
        where sm.created_at >= v_start
          and sm.reference_type = 'STOCK_OUT'
          and sm.movement_type in ('MANUAL_OUT', 'REVERSAL')
      ), 0)::numeric(14,4) as released,
      coalesce(-sum(sm.quantity_delta) filter (
        where sm.created_at >= v_start
          and (
            sm.movement_type in ('WASTE', 'DAMAGED', 'EXPIRED')
            or (
              sm.movement_type = 'REVERSAL'
              and sm.reference_type = 'LOT_DISPOSAL_VOID'
            )
          )
      ), 0)::numeric(14,4) as lost,
      -- Opening stock, count corrections, manual adjustments and refund
      -- restocks.
      coalesce(sum(sm.quantity_delta) filter (
        where sm.created_at >= v_start
          and sm.movement_type not in (
            'PURCHASE_RECEIPT', 'SALE_CONSUMPTION', 'WASTE', 'DAMAGED',
            'EXPIRED'
          )
          and not (
            sm.reference_type = 'STOCK_OUT'
            and sm.movement_type in ('MANUAL_OUT', 'REVERSAL')
          )
          and not (
            sm.movement_type = 'REVERSAL'
            and sm.reference_type in ('GOODS_RECEIPT', 'LOT_DISPOSAL_VOID')
          )
      ), 0)::numeric(14,4) as other
    from public.inventory_items ii
    join public.units_of_measure u on u.id = ii.base_uom_id
    left join public.stock_movements sm
      on sm.inventory_item_id = ii.id
     and sm.created_at < v_end
    where ii.track_inventory = true
    group by ii.name, u.code
    having count(sm.id) > 0
  ) x;

  return jsonb_build_object(
    'from', p_from,
    'to', p_to,
    'timezone', v_tz,
    'summary', v_summary,
    'by_day', v_by_day,
    'by_payment_method', v_by_payment,
    'by_item', v_by_item,
    'by_category', v_by_category,
    'by_discount', v_by_discount,
    'by_employee', v_by_employee,
    'refunds', v_refunds,
    'expenses_by_category', v_expenses,
    'stock_losses', v_losses,
    'expired_on_hand', v_expired,
    'stock_movement', v_inventory
  );
end;
$$;

-- Transaction trace: voided documents stay visible --------------------------

create or replace view public.v_business_transaction_trace
with (security_invoker = true)
as
with order_payment_references as (
  select
    p.order_id,
    max(nullif(btrim(p.external_reference), '')) as external_reference
  from public.payments p
  where p.transaction_type = 'PAYMENT'
    and p.status = 'COMPLETED'
  group by p.order_id
),
refund_payment_references as (
  select
    p.refund_id,
    max(nullif(btrim(p.external_reference), '')) as external_reference
  from public.payments p
  where p.transaction_type = 'REFUND'
    and p.status = 'COMPLETED'
  group by p.refund_id
),
goods_receipt_totals as (
  select
    gri.goods_receipt_id,
    count(*)::integer as line_count,
    round(
      sum(gri.purchase_quantity * gri.unit_cost_purchase_uom),
      2
    )::numeric(14,2) as receipt_total
  from public.goods_receipt_items gri
  group by gri.goods_receipt_id
),
stock_out_totals as (
  select
    soi.stock_out_id,
    count(*)::integer as line_count
  from public.stock_out_items soi
  group by soi.stock_out_id
),
stock_count_totals as (
  select
    sci.stock_count_id,
    count(*)::integer as line_count
  from public.stock_count_items sci
  group by sci.stock_count_id
)
select
  'SALE:' || o.id::text as event_key,
  o.completed_at as occurred_at,
  'SALE'::text as event_type,
  'ORD-' || o.order_number::text as document_number,
  coalesce(opr.external_reference, o.delivery_reference) as external_reference,
  replace(initcap(lower(o.order_type)), '_', ' ') as description,
  coalesce(nullif(btrim(o.customer_name), ''), 'Walk-in Customer')
    as party_name,
  o.total_amount::numeric(14,2) as amount,
  coalesce(
    nullif(btrim(p.display_name), ''),
    nullif(btrim(concat_ws(' ', p.first_name, p.last_name)), ''),
    o.employee_name_snapshot,
    'Unknown Employee'
  ) as actor_name,
  o.status,
  (
    select h.reason
    from public.order_status_history h
    where h.order_id = o.id
      and h.new_status = 'VOIDED'
    order by h.created_at desc
    limit 1
  ) as void_reason
from public.orders o
left join public.profiles p on p.id = o.created_by_user_id
left join order_payment_references opr on opr.order_id = o.id
where o.completed_at is not null
  and o.status in ('COMPLETED', 'PARTIALLY_REFUNDED', 'REFUNDED', 'VOIDED')
  and public.has_permission('reports.view')

union all

select
  'REFUND:' || r.id::text,
  r.created_at,
  'REFUND'::text,
  'RF-' || r.refund_number::text,
  rpr.external_reference,
  r.reason,
  coalesce(nullif(btrim(o.customer_name), ''), 'Walk-in Customer'),
  (-r.total_amount)::numeric(14,2),
  coalesce(
    nullif(btrim(p.display_name), ''),
    nullif(btrim(concat_ws(' ', p.first_name, p.last_name)), ''),
    'Unknown Employee'
  ),
  r.status,
  null::text
from public.refunds r
join public.orders o on o.id = r.order_id
left join public.profiles p on p.id = r.requested_by
left join refund_payment_references rpr on rpr.refund_id = r.id
where r.status = 'COMPLETED'
  and public.has_permission('reports.view')

union all

select
  'GOODS_RECEIPT:' || gr.id::text,
  coalesce(gr.posted_at, gr.received_at),
  'STOCK_IN'::text,
  'GR-' || gr.receipt_number::text,
  gr.supplier_invoice_number,
  coalesce(grt.line_count, 0)::text || ' item(s) received',
  s.name,
  coalesce(grt.receipt_total, 0)::numeric(14,2),
  coalesce(
    nullif(btrim(p.display_name), ''),
    nullif(btrim(concat_ws(' ', p.first_name, p.last_name)), ''),
    'Unknown Employee'
  ),
  case when gr.voided_at is not null then 'VOIDED' else gr.status end,
  gr.void_reason
from public.goods_receipts gr
join public.suppliers s on s.id = gr.supplier_id
left join public.profiles p on p.id = gr.received_by
left join goods_receipt_totals grt on grt.goods_receipt_id = gr.id
where (gr.status = 'POSTED' or gr.voided_at is not null)
  and public.has_permission('reports.view')

union all

select
  'STOCK_OUT:' || so.id::text,
  coalesce(so.posted_at, so.occurred_at),
  'STOCK_OUT'::text,
  'SO-' || so.stock_out_number::text,
  so.reference_number,
  so.purpose || ' · ' || coalesce(sot.line_count, 0)::text || ' item(s)',
  null::text,
  null::numeric(14,2),
  coalesce(
    nullif(btrim(p.display_name), ''),
    nullif(btrim(concat_ws(' ', p.first_name, p.last_name)), ''),
    'Unknown Employee'
  ),
  so.status,
  so.void_reason
from public.stock_out_transactions so
left join public.profiles p on p.id = so.recorded_by
left join stock_out_totals sot on sot.stock_out_id = so.id
where so.status in ('POSTED', 'VOIDED')
  and public.has_permission('reports.view')

union all

select
  'STOCK_COUNT:' || sc.id::text,
  coalesce(sc.posted_at, sc.counted_at),
  'INVENTORY_COUNT'::text,
  'IC-' || sc.count_number::text,
  null::text,
  coalesce(nullif(btrim(sc.notes), ''), 'Physical inventory count')
    || ' · ' || coalesce(sct.line_count, 0)::text || ' item(s)',
  null::text,
  null::numeric(14,2),
  coalesce(
    nullif(btrim(p.display_name), ''),
    nullif(btrim(concat_ws(' ', p.first_name, p.last_name)), ''),
    'Unknown Employee'
  ),
  case when sc.voided_at is not null then 'VOIDED' else sc.status end,
  sc.void_reason
from public.stock_counts sc
left join public.profiles p on p.id = coalesce(sc.posted_by, sc.counted_by)
left join stock_count_totals sct on sct.stock_count_id = sc.id
where (sc.status = 'POSTED' or sc.voided_at is not null)
  and public.has_permission('reports.view')

union all

select
  'EXPENSE:' || e.id::text,
  e.expense_date::timestamp at time zone 'Asia/Manila',
  'EXPENSE'::text,
  'EX-' || e.expense_number::text,
  e.reference_number,
  ec.name || ': ' || e.description,
  s.name,
  (-e.amount)::numeric(14,2),
  coalesce(
    nullif(btrim(p.display_name), ''),
    nullif(btrim(concat_ws(' ', p.first_name, p.last_name)), ''),
    'Unknown Employee'
  ),
  e.status,
  e.void_reason
from public.expenses e
join public.expense_categories ec on ec.id = e.expense_category_id
join public.suppliers s on s.id = e.supplier_id
left join public.profiles p on p.id = e.recorded_by
where e.status in ('POSTED', 'VOIDED')
  and public.has_permission('reports.view')

union all

select
  'SUPPLIER_PAYMENT:' || sbp.id::text,
  sbp.paid_at,
  'SUPPLIER_PAYMENT'::text,
  'BILL-' || coalesce(sb.supplier_invoice_number, left(sb.id::text, 8)),
  sbp.reference_number,
  case
    when sbp.reverses_payment_id is not null then
      'Reversal of a supplier payment via ' || pm.name
    else 'Supplier bill payment via ' || pm.name
  end,
  s.name,
  (-sbp.amount)::numeric(14,2),
  coalesce(
    nullif(btrim(p.display_name), ''),
    nullif(btrim(concat_ws(' ', p.first_name, p.last_name)), ''),
    'Unknown Employee'
  ),
  case
    when sbp.reverses_payment_id is not null then 'REVERSAL'
    when exists (
      select 1
      from public.supplier_bill_payments reversal
      where reversal.reverses_payment_id = sbp.id
    ) then 'REVERSED'
    else 'COMPLETED'
  end,
  case when sbp.reverses_payment_id is not null then sbp.notes end
from public.supplier_bill_payments sbp
join public.supplier_bills sb on sb.id = sbp.supplier_bill_id
join public.suppliers s on s.id = sb.supplier_id
join public.payment_methods pm on pm.id = sbp.payment_method_id
left join public.profiles p on p.id = sbp.recorded_by
where public.has_permission('reports.view');

-- Stock history: says whether a write-off has been reversed -----------------

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
  end as external_reference_number,
  exists (
    select 1
    from public.stock_movements reversal
    where reversal.movement_type = 'REVERSAL'
      and reversal.reference_type = 'LOT_DISPOSAL_VOID'
      and reversal.reference_id = sm.id
  ) as is_reversed
from public.stock_movements sm
left join public.stock_out_transactions so
  on sm.reference_type = 'STOCK_OUT' and so.id = sm.reference_id
left join public.goods_receipts gr
  on sm.reference_type = 'GOODS_RECEIPT' and gr.id = sm.reference_id
left join public.orders o
  on sm.reference_type = 'ORDER' and o.id = sm.reference_id
left join public.stock_counts sc
  on sm.reference_type = 'STOCK_COUNT' and sc.id = sm.reference_id;
