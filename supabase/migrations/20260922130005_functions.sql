-- 0005_functions.sql
-- Security helpers and transactional business functions.

-- ===== Authorization helpers =====

create or replace function public.has_permission(p_permission_code text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.profiles pr
    join public.role_permissions rp on rp.role_id = pr.role_id
    join public.permissions pe on pe.id = rp.permission_id
    where pr.id = auth.uid()
      and pr.status = 'ACTIVE'
      and pe.code = p_permission_code
  );
$$;

revoke all on function public.has_permission(text) from public;
grant execute on function public.has_permission(text) to authenticated;

create or replace function public.current_open_shift_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select s.id
  from public.shifts s
  where s.employee_id = auth.uid()
    and s.status = 'OPEN'
  order by s.started_at desc
  limit 1;
$$;

revoke all on function public.current_open_shift_id() from public;
grant execute on function public.current_open_shift_id() to authenticated;

-- ===== Shift functions =====

create or replace function public.start_shift(
  p_device_id uuid default null,
  p_opening_cash numeric default null
)
returns public.shifts
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile public.profiles%rowtype;
  v_shift public.shifts%rowtype;
  v_require_opening boolean := false;
begin
  select * into v_profile
  from public.profiles
  where id = auth.uid()
    and status = 'ACTIVE';

  if not found then
    raise exception 'Active employee profile required';
  end if;

  if not public.has_permission('shift.start') then
    raise exception 'Permission denied';
  end if;

  if exists (
    select 1 from public.shifts
    where employee_id = auth.uid()
      and status = 'OPEN'
  ) then
    raise exception 'Employee already has an open shift';
  end if;

  select coalesce((value #>> '{}')::boolean, false)
  into v_require_opening
  from public.system_settings
  where key = 'require_opening_cash';

  if coalesce(v_require_opening, false) and p_opening_cash is null then
    raise exception 'Opening cash is required';
  end if;

  insert into public.shifts (
    employee_id,
    device_id,
    opening_cash
  )
  values (
    auth.uid(),
    p_device_id,
    p_opening_cash
  )
  returning * into v_shift;

  insert into public.audit_logs(actor_user_id, action_code, entity_type, entity_id, device_id, new_data)
  values (
    auth.uid(),
    'SHIFT_STARTED',
    'shift',
    v_shift.id::text,
    p_device_id,
    jsonb_build_object('opening_cash', p_opening_cash)
  );

  return v_shift;
end;
$$;

revoke all on function public.start_shift(uuid,numeric) from public;
grant execute on function public.start_shift(uuid,numeric) to authenticated;

create or replace function public.end_shift(
  p_shift_id uuid,
  p_closing_cash_counted numeric default null,
  p_notes text default null
)
returns public.shifts
language plpgsql
security definer
set search_path = public
as $$
declare
  v_shift public.shifts%rowtype;
  v_cash_sales numeric(14,2) := 0;
  v_cash_refunds numeric(14,2) := 0;
  v_cash_in numeric(14,2) := 0;
  v_cash_out numeric(14,2) := 0;
  v_expected numeric(14,2) := 0;
  v_cash_method uuid;
  v_require_closing boolean := false;
begin
  select * into v_shift
  from public.shifts
  where id = p_shift_id
  for update;

  if not found then
    raise exception 'Shift not found';
  end if;

  if v_shift.status <> 'OPEN' then
    raise exception 'Shift is not open';
  end if;

  if v_shift.employee_id <> auth.uid()
     and not public.has_permission('shift.manage') then
    raise exception 'Permission denied';
  end if;

  select coalesce((value #>> '{}')::boolean, false)
  into v_require_closing
  from public.system_settings
  where key = 'require_closing_cash';

  if coalesce(v_require_closing, false) and p_closing_cash_counted is null then
    raise exception 'Closing cash count is required';
  end if;

  select id into v_cash_method
  from public.payment_methods
  where code = 'CASH'
  limit 1;

  if v_cash_method is not null then
    select coalesce(sum(amount),0)
    into v_cash_sales
    from public.payments
    where shift_id = p_shift_id
      and payment_method_id = v_cash_method
      and transaction_type = 'PAYMENT'
      and status = 'COMPLETED';

    select coalesce(sum(amount),0)
    into v_cash_refunds
    from public.payments
    where shift_id = p_shift_id
      and payment_method_id = v_cash_method
      and transaction_type = 'REFUND'
      and status = 'COMPLETED';
  end if;

  select
    coalesce(sum(case when movement_type in ('PAY_IN','CORRECTION') then amount else 0 end),0),
    coalesce(sum(case when movement_type in ('PAY_OUT','CASH_DROP') then amount else 0 end),0)
  into v_cash_in, v_cash_out
  from public.shift_cash_movements
  where shift_id = p_shift_id;

  v_expected :=
    coalesce(v_shift.opening_cash,0)
    + v_cash_sales
    + v_cash_in
    - v_cash_refunds
    - v_cash_out;

  update public.shifts
  set
    ended_at = now(),
    closing_cash_counted = p_closing_cash_counted,
    expected_closing_cash = v_expected,
    cash_variance = case
      when p_closing_cash_counted is null then null
      else p_closing_cash_counted - v_expected
    end,
    status = 'CLOSED',
    closing_notes = p_notes,
    closed_by = auth.uid()
  where id = p_shift_id
  returning * into v_shift;

  insert into public.audit_logs(actor_user_id, action_code, entity_type, entity_id, device_id, new_data)
  values (
    auth.uid(),
    'SHIFT_ENDED',
    'shift',
    p_shift_id::text,
    v_shift.device_id,
    jsonb_build_object(
      'closing_cash_counted', p_closing_cash_counted,
      'expected_closing_cash', v_expected,
      'cash_variance', v_shift.cash_variance
    )
  );

  return v_shift;
end;
$$;

revoke all on function public.end_shift(uuid,numeric,text) from public;
grant execute on function public.end_shift(uuid,numeric,text) to authenticated;

-- ===== Inventory functions =====

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
        'Negative stock allowed: insufficient lot quantity'
      );
    else
      raise exception 'Insufficient stock for inventory item %', p_inventory_item_id;
    end if;
  end if;
end;
$$;

revoke all on function public.consume_inventory_fefo(uuid,numeric,uuid,uuid,uuid) from public;

create or replace function public.post_goods_receipt(p_goods_receipt_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_receipt public.goods_receipts%rowtype;
  v_line public.goods_receipt_items%rowtype;
  v_lot_id uuid;
begin
  if not public.has_permission('purchases.receive') then
    raise exception 'Permission denied';
  end if;

  select * into v_receipt
  from public.goods_receipts
  where id = p_goods_receipt_id
  for update;

  if not found then
    raise exception 'Goods receipt not found';
  end if;

  if v_receipt.status <> 'DRAFT' then
    raise exception 'Only DRAFT goods receipts can be posted';
  end if;

  if not exists (
    select 1 from public.goods_receipt_items where goods_receipt_id = p_goods_receipt_id
  ) then
    raise exception 'Goods receipt has no items';
  end if;

  for v_line in
    select * from public.goods_receipt_items
    where goods_receipt_id = p_goods_receipt_id
  loop
    insert into public.inventory_lots (
      inventory_item_id,
      goods_receipt_item_id,
      lot_code,
      received_at,
      expiration_date,
      received_quantity,
      remaining_quantity,
      unit_cost_base
    )
    values (
      v_line.inventory_item_id,
      v_line.id,
      v_line.lot_code,
      v_receipt.received_at,
      v_line.expiration_date,
      v_line.base_quantity,
      v_line.base_quantity,
      v_line.unit_cost_base
    )
    returning id into v_lot_id;

    insert into public.stock_movements (
      inventory_item_id,
      inventory_lot_id,
      movement_type,
      quantity_delta,
      unit_cost_base,
      reference_type,
      reference_id,
      recorded_by
    )
    values (
      v_line.inventory_item_id,
      v_lot_id,
      'PURCHASE_RECEIPT',
      v_line.base_quantity,
      v_line.unit_cost_base,
      'GOODS_RECEIPT',
      p_goods_receipt_id,
      auth.uid()
    );
  end loop;

  update public.goods_receipts
  set status = 'POSTED', posted_at = now()
  where id = p_goods_receipt_id;

  insert into public.audit_logs(actor_user_id, action_code, entity_type, entity_id, new_data)
  values (
    auth.uid(),
    'GOODS_RECEIPT_POSTED',
    'goods_receipt',
    p_goods_receipt_id::text,
    jsonb_build_object('receipt_number', v_receipt.receipt_number)
  );
end;
$$;

revoke all on function public.post_goods_receipt(uuid) from public;
grant execute on function public.post_goods_receipt(uuid) to authenticated;

-- ===== Order/invoice functions =====

create or replace function public.recalculate_order_totals(p_order_id uuid)
returns public.orders
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order public.orders%rowtype;
  v_subtotal numeric(14,2);
  v_item_discount numeric(14,2);
  v_order_discount numeric(14,2);
  v_tax numeric(14,2);
begin
  select * into v_order
  from public.orders
  where id = p_order_id
  for update;

  if not found then
    raise exception 'Order not found';
  end if;

  select
    coalesce(sum(line_subtotal),0),
    coalesce(sum(discount_amount),0),
    coalesce(sum(tax_amount),0)
  into v_subtotal, v_item_discount, v_tax
  from public.order_items
  where order_id = p_order_id;

  select coalesce(sum(discount_amount),0)
  into v_order_discount
  from public.order_discounts
  where order_id = p_order_id;

  update public.orders
  set
    subtotal = v_subtotal,
    discount_amount = v_item_discount + v_order_discount,
    tax_amount = v_tax,
    total_amount = greatest(0, v_subtotal - v_item_discount - v_order_discount + v_tax)
  where id = p_order_id
  returning * into v_order;

  return v_order;
end;
$$;

revoke all on function public.recalculate_order_totals(uuid) from public;
grant execute on function public.recalculate_order_totals(uuid) to authenticated;

create or replace function public.next_invoice_number(p_sequence_code text default 'SALES_INVOICE')
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_seq public.invoice_sequences%rowtype;
  v_number text;
begin
  select * into v_seq
  from public.invoice_sequences
  where code = p_sequence_code
    and is_active = true
  for update;

  if not found then
    raise exception 'Active invoice sequence % not found', p_sequence_code;
  end if;

  v_number := v_seq.prefix || lpad(v_seq.next_number::text, v_seq.number_width, '0');

  update public.invoice_sequences
  set next_number = next_number + 1
  where id = v_seq.id;

  return v_number;
end;
$$;

revoke all on function public.next_invoice_number(text) from public;

create or replace function public.issue_sales_invoice(p_order_id uuid)
returns public.sales_invoices
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order public.orders%rowtype;
  v_business public.business_profile%rowtype;
  v_sequence_id uuid;
  v_invoice_number text;
  v_invoice public.sales_invoices%rowtype;
begin
  select * into v_order
  from public.orders
  where id = p_order_id;

  if not found then
    raise exception 'Order not found';
  end if;

  if v_order.status <> 'COMPLETED' then
    raise exception 'Only completed orders can receive a sales invoice';
  end if;

  select * into v_invoice
  from public.sales_invoices
  where order_id = p_order_id;

  if found then
    return v_invoice;
  end if;

  select * into v_business
  from public.business_profile
  where id = 1;

  select id into v_sequence_id
  from public.invoice_sequences
  where code = 'SALES_INVOICE' and is_active = true
  limit 1;

  v_invoice_number := public.next_invoice_number('SALES_INVOICE');

  insert into public.sales_invoices (
    order_id,
    invoice_sequence_id,
    invoice_number,
    seller_registered_name,
    seller_trade_name,
    seller_tin,
    seller_branch_code,
    seller_address,
    seller_tax_registration_status,
    buyer_name,
    subtotal,
    discount_amount,
    vat_amount,
    total_amount,
    issued_by,
    device_id
  )
  values (
    p_order_id,
    v_sequence_id,
    v_invoice_number,
    v_business.registered_name,
    v_business.trade_name,
    v_business.tin,
    v_business.branch_code,
    concat_ws(', ', v_business.address_line, v_business.city, v_business.province, v_business.postal_code),
    v_business.tax_registration_status,
    v_order.customer_name,
    v_order.subtotal,
    v_order.discount_amount,
    v_order.tax_amount,
    v_order.total_amount,
    auth.uid(),
    v_order.device_id
  )
  returning * into v_invoice;

  return v_invoice;
end;
$$;

revoke all on function public.issue_sales_invoice(uuid) from public;

-- Checkout accepts one or many payments in JSON:
-- [
--   {"payment_method_id":"uuid","amount":150,"amount_tendered":200,"change_amount":50,"external_reference":"..."}
-- ]
create or replace function public.checkout_order(
  p_order_id uuid,
  p_payments jsonb
)
returns public.orders
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order public.orders%rowtype;
  v_item public.order_items%rowtype;
  v_component record;
  v_modifier_component record;
  v_payment jsonb;
  v_payment_total numeric(14,2) := 0;
  v_shift_id uuid;
begin
  if not public.has_permission('orders.checkout') then
    raise exception 'Permission denied';
  end if;

  select * into v_order
  from public.orders
  where id = p_order_id
  for update;

  if not found then
    raise exception 'Order not found';
  end if;

  if v_order.status not in ('OPEN','PENDING_PAYMENT') then
    raise exception 'Order is not available for checkout';
  end if;

  if v_order.created_by_user_id = auth.uid() then
    v_shift_id := public.current_open_shift_id();
    if v_shift_id is null then
      raise exception 'An active shift is required';
    end if;
  elsif not public.has_permission('orders.manage_all') then
    raise exception 'Permission denied for this order';
  else
    v_shift_id := v_order.shift_id;
  end if;

  perform public.recalculate_order_totals(p_order_id);

  select * into v_order
  from public.orders
  where id = p_order_id
  for update;

  if jsonb_typeof(p_payments) <> 'array' or jsonb_array_length(p_payments) = 0 then
    raise exception 'At least one payment is required';
  end if;

  for v_payment in select value from jsonb_array_elements(p_payments)
  loop
    v_payment_total := v_payment_total + coalesce((v_payment ->> 'amount')::numeric,0);
  end loop;

  if round(v_payment_total,2) < round(v_order.total_amount,2) then
    raise exception 'Payment total is less than order total';
  end if;

  -- Consume inventory for each sold line.
  for v_item in
    select * from public.order_items where order_id = p_order_id
  loop
    -- Finished good stock, e.g. bottled water/canned drink.
    for v_component in
      select
        mv.finished_inventory_item_id as inventory_item_id,
        v_item.quantity as quantity_needed
      from public.menu_variants mv
      where mv.id = v_item.menu_variant_id
        and mv.track_finished_inventory = true
        and mv.finished_inventory_item_id is not null
    loop
      perform public.consume_inventory_fefo(
        v_component.inventory_item_id,
        v_component.quantity_needed,
        p_order_id,
        v_item.id,
        auth.uid()
      );
    end loop;

    -- Base recipe.
    for v_component in
      select
        rc.inventory_item_id,
        (rc.quantity_base_uom * (1 + rc.wastage_percent / 100.0) * v_item.quantity) as quantity_needed
      from public.variant_recipe_components rc
      where rc.menu_variant_id = v_item.menu_variant_id
    loop
      perform public.consume_inventory_fefo(
        v_component.inventory_item_id,
        v_component.quantity_needed,
        p_order_id,
        v_item.id,
        auth.uid()
      );
    end loop;

    -- Modifier recipe additions.
    for v_modifier_component in
      select
        mrc.inventory_item_id,
        sum(
          mrc.quantity_base_uom
          * (1 + mrc.wastage_percent / 100.0)
          * oim.quantity
          * v_item.quantity
        ) as quantity_needed
      from public.order_item_modifiers oim
      join public.modifier_recipe_components mrc
        on mrc.modifier_id = oim.modifier_id
      where oim.order_item_id = v_item.id
      group by mrc.inventory_item_id
    loop
      perform public.consume_inventory_fefo(
        v_modifier_component.inventory_item_id,
        v_modifier_component.quantity_needed,
        p_order_id,
        v_item.id,
        auth.uid()
      );
    end loop;
  end loop;

  -- Insert sale payment records.
  for v_payment in select value from jsonb_array_elements(p_payments)
  loop
    insert into public.payments (
      order_id,
      payment_method_id,
      transaction_type,
      status,
      amount,
      amount_tendered,
      change_amount,
      external_provider,
      external_reference,
      idempotency_key,
      processed_by,
      shift_id,
      device_id
    )
    values (
      p_order_id,
      (v_payment ->> 'payment_method_id')::uuid,
      'PAYMENT',
      'COMPLETED',
      (v_payment ->> 'amount')::numeric,
      nullif(v_payment ->> 'amount_tendered','')::numeric,
      coalesce(nullif(v_payment ->> 'change_amount','')::numeric,0),
      v_payment ->> 'external_provider',
      v_payment ->> 'external_reference',
      nullif(v_payment ->> 'idempotency_key','')::uuid,
      auth.uid(),
      v_shift_id,
      v_order.device_id
    );
  end loop;

  update public.orders
  set
    status = 'COMPLETED',
    payment_status = 'PAID',
    shift_id = coalesce(shift_id, v_shift_id),
    completed_at = now()
  where id = p_order_id
  returning * into v_order;

  insert into public.order_status_history(order_id, old_status, new_status, changed_by)
  values (p_order_id, 'PENDING_PAYMENT', 'COMPLETED', auth.uid());

  perform public.issue_sales_invoice(p_order_id);

  insert into public.audit_logs(actor_user_id, action_code, entity_type, entity_id, device_id, new_data)
  values (
    auth.uid(),
    'ORDER_CHECKOUT',
    'order',
    p_order_id::text,
    v_order.device_id,
    jsonb_build_object('total_amount', v_order.total_amount, 'payment_total', v_payment_total)
  );

  return v_order;
end;
$$;

revoke all on function public.checkout_order(uuid,jsonb) from public;
grant execute on function public.checkout_order(uuid,jsonb) to authenticated;

create or replace function public.void_order(
  p_order_id uuid,
  p_reason text,
  p_authorized_by uuid
)
returns public.orders
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order public.orders%rowtype;
begin
  if not public.has_permission('orders.void') then
    raise exception 'Permission denied';
  end if;

  if p_reason is null or btrim(p_reason) = '' then
    raise exception 'Void reason is required';
  end if;

  select * into v_order
  from public.orders
  where id = p_order_id
  for update;

  if not found then
    raise exception 'Order not found';
  end if;

  if v_order.status = 'COMPLETED' or v_order.payment_status in ('PAID','PARTIALLY_REFUNDED','REFUNDED') then
    raise exception 'Paid orders must use the refund workflow';
  end if;

  update public.orders
  set status = 'VOIDED'
  where id = p_order_id
  returning * into v_order;

  insert into public.order_actions(order_id, action_type, reason, performed_by, authorized_by)
  values (p_order_id, 'VOID', p_reason, auth.uid(), p_authorized_by);

  insert into public.order_status_history(order_id, old_status, new_status, changed_by, reason)
  values (p_order_id, 'OPEN', 'VOIDED', auth.uid(), p_reason);

  return v_order;
end;
$$;

revoke all on function public.void_order(uuid,text,uuid) from public;
grant execute on function public.void_order(uuid,text,uuid) to authenticated;

-- Partial/full refund business record.
-- Payment return records are supplied as JSON and may use one or multiple methods.
-- Inventory is not automatically restored.
create or replace function public.process_refund(
  p_order_id uuid,
  p_items jsonb,
  p_payment_returns jsonb,
  p_reason text,
  p_authorized_by uuid
)
returns public.refunds
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order public.orders%rowtype;
  v_refund public.refunds%rowtype;
  v_item jsonb;
  v_payment jsonb;
  v_refund_total numeric(14,2) := 0;
  v_return_total numeric(14,2) := 0;
  v_order_item public.order_items%rowtype;
  v_already_refunded numeric(14,4);
  v_qty numeric(14,4);
  v_amount numeric(14,2);
  v_refund_type text;
  v_previous_refunds numeric(14,2);
begin
  if not public.has_permission('orders.refund') then
    raise exception 'Permission denied';
  end if;

  if p_reason is null or btrim(p_reason) = '' then
    raise exception 'Refund reason is required';
  end if;

  select * into v_order
  from public.orders
  where id = p_order_id
  for update;

  if not found or v_order.status not in ('COMPLETED','PARTIALLY_REFUNDED') then
    raise exception 'Order is not refundable';
  end if;

  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'Refund items are required';
  end if;

  for v_item in select value from jsonb_array_elements(p_items)
  loop
    select * into v_order_item
    from public.order_items
    where id = (v_item ->> 'order_item_id')::uuid
      and order_id = p_order_id;

    if not found then
      raise exception 'Refund item does not belong to order';
    end if;

    v_qty := (v_item ->> 'quantity')::numeric;
    v_amount := (v_item ->> 'refund_amount')::numeric;

    select coalesce(sum(ri.quantity),0)
    into v_already_refunded
    from public.refund_items ri
    join public.refunds r on r.id = ri.refund_id
    where ri.order_item_id = v_order_item.id
      and r.status = 'COMPLETED';

    if v_qty <= 0 or v_qty + v_already_refunded > v_order_item.quantity then
      raise exception 'Invalid refund quantity';
    end if;

    if v_amount < 0 then
      raise exception 'Invalid refund amount';
    end if;

    v_refund_total := v_refund_total + v_amount;
  end loop;

  select coalesce(sum(total_amount),0)
  into v_previous_refunds
  from public.refunds
  where order_id = p_order_id
    and status = 'COMPLETED';

  if v_refund_total <= 0 or v_previous_refunds + v_refund_total > v_order.total_amount then
    raise exception 'Invalid refund total';
  end if;

  v_refund_type := case
    when round(v_previous_refunds + v_refund_total,2) >= round(v_order.total_amount,2)
      then 'FULL'
    else 'PARTIAL'
  end;

  insert into public.refunds(
    order_id,
    refund_type,
    status,
    reason,
    total_amount,
    requested_by,
    authorized_by,
    shift_id
  )
  values (
    p_order_id,
    v_refund_type,
    'COMPLETED',
    p_reason,
    v_refund_total,
    auth.uid(),
    p_authorized_by,
    public.current_open_shift_id()
  )
  returning * into v_refund;

  for v_item in select value from jsonb_array_elements(p_items)
  loop
    insert into public.refund_items(
      refund_id,
      order_item_id,
      quantity,
      refund_amount,
      restock_approved,
      notes
    )
    values (
      v_refund.id,
      (v_item ->> 'order_item_id')::uuid,
      (v_item ->> 'quantity')::numeric,
      (v_item ->> 'refund_amount')::numeric,
      coalesce((v_item ->> 'restock_approved')::boolean,false),
      v_item ->> 'notes'
    );
  end loop;

  if jsonb_typeof(p_payment_returns) <> 'array' or jsonb_array_length(p_payment_returns) = 0 then
    raise exception 'Refund payment method is required';
  end if;

  for v_payment in select value from jsonb_array_elements(p_payment_returns)
  loop
    v_return_total := v_return_total + (v_payment ->> 'amount')::numeric;

    insert into public.payments(
      order_id,
      refund_id,
      payment_method_id,
      transaction_type,
      status,
      amount,
      external_provider,
      external_reference,
      idempotency_key,
      processed_by,
      shift_id,
      device_id
    )
    values (
      p_order_id,
      v_refund.id,
      (v_payment ->> 'payment_method_id')::uuid,
      'REFUND',
      'COMPLETED',
      (v_payment ->> 'amount')::numeric,
      v_payment ->> 'external_provider',
      v_payment ->> 'external_reference',
      nullif(v_payment ->> 'idempotency_key','')::uuid,
      auth.uid(),
      public.current_open_shift_id(),
      v_order.device_id
    );
  end loop;

  if round(v_return_total,2) <> round(v_refund_total,2) then
    raise exception 'Refund payment total must equal refund total';
  end if;

  update public.orders
  set
    status = case when v_refund_type = 'FULL' then 'REFUNDED' else 'PARTIALLY_REFUNDED' end,
    payment_status = case when v_refund_type = 'FULL' then 'REFUNDED' else 'PARTIALLY_REFUNDED' end
  where id = p_order_id;

  insert into public.order_actions(order_id, action_type, reason, performed_by, authorized_by)
  values (p_order_id, 'REFUND', p_reason, auth.uid(), p_authorized_by);

  insert into public.order_status_history(order_id, old_status, new_status, changed_by, reason)
  values (
    p_order_id,
    v_order.status,
    case when v_refund_type = 'FULL' then 'REFUNDED' else 'PARTIALLY_REFUNDED' end,
    auth.uid(),
    p_reason
  );

  insert into public.credit_notes(
    sales_invoice_id,
    refund_id,
    amount,
    reason,
    issued_by
  )
  select
    si.id,
    v_refund.id,
    v_refund_total,
    p_reason,
    auth.uid()
  from public.sales_invoices si
  where si.order_id = p_order_id;

  insert into public.audit_logs(actor_user_id, action_code, entity_type, entity_id, device_id, new_data)
  values (
    auth.uid(),
    'ORDER_REFUND',
    'order',
    p_order_id::text,
    v_order.device_id,
    jsonb_build_object(
      'refund_id', v_refund.id,
      'refund_total', v_refund_total,
      'refund_type', v_refund_type
    )
  );

  return v_refund;
end;
$$;

revoke all on function public.process_refund(uuid,jsonb,jsonb,text,uuid) from public;
grant execute on function public.process_refund(uuid,jsonb,jsonb,text,uuid) to authenticated;
