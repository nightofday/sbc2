-- S-04 and S-05: keep history when posted records are corrected.
--
-- S-04. Posted records were edited in place:
--   * update_expense changed a posted expense with no trace of the old values;
--   * void_expense needed no reason and did not record who voided it or when;
--   * update_supplier overwrote every column, so a caller that sent only the
--     name wiped the contact person, email, address, terms and notes (SUP-01).
--
-- S-05. Posted stock documents could not be corrected at all. The statuses
-- CANCELLED and VOIDED existed for goods receipts, stock releases and counts,
-- but nothing set them.
--
-- Corrections below never delete or rewrite a ledger row. A void posts
-- REVERSAL movements against the same lots and marks the document.

-- ============================================================
-- 1. Expenses
-- ============================================================

alter table public.expenses
  add column voided_at timestamptz,
  add column voided_by uuid references public.profiles(id),
  add column void_reason text;

create or replace function public.update_expense(
  p_expense_id uuid,
  p_expense_category_id uuid,
  p_description text,
  p_amount numeric,
  p_expense_date date,
  p_payment_method_id uuid default null,
  p_supplier_id uuid default null,
  p_reference_number text default null,
  p_notes text default null
)
returns public.expenses
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_old public.expenses%rowtype;
  v_expense public.expenses%rowtype;
  v_category_code text;
begin
  if not public.has_permission('expenses.manage') then
    raise exception 'Permission denied';
  end if;

  select *
  into v_expense
  from public.expenses e
  where e.id = p_expense_id
  for update;

  if not found or v_expense.status = 'VOIDED' then
    raise exception 'Expense not available';
  end if;

  if nullif(btrim(coalesce(p_description, '')), '') is null then
    raise exception 'Expense purpose is required';
  end if;

  if p_amount is null or p_amount <= 0 then
    raise exception 'Amount must be greater than zero';
  end if;

  if p_supplier_id is null or not exists (
    select 1
    from public.suppliers s
    where s.id = p_supplier_id
      and s.is_active = true
  ) then
    raise exception 'A valid supplier or grocery is required';
  end if;

  if nullif(btrim(coalesce(p_reference_number, '')), '') is null then
    raise exception 'Receipt or reference number is required';
  end if;

  select ec.code
  into v_category_code
  from public.expense_categories ec
  where ec.id = p_expense_category_id
    and ec.is_active = true;

  if not found then
    raise exception 'Invalid expense category';
  end if;

  if p_payment_method_id is not null and not exists (
    select 1
    from public.payment_methods pm
    where pm.id = p_payment_method_id
      and pm.is_active = true
  ) then
    raise exception 'Invalid payment method';
  end if;

  v_old := v_expense;

  update public.expenses
  set
    expense_category_id = p_expense_category_id,
    expense_type = case
      when v_category_code = 'INGREDIENTS' then 'NON_INVENTORY_PURCHASE'
      else 'OPERATING'
    end,
    description = btrim(p_description),
    amount = round(p_amount, 2),
    expense_date = coalesce(p_expense_date, expense_date),
    payment_method_id = p_payment_method_id,
    supplier_id = p_supplier_id,
    reference_number = btrim(p_reference_number),
    notes = nullif(btrim(coalesce(p_notes, '')), '')
  where id = p_expense_id
  returning * into v_expense;

  -- Keep what the posted record said before and after the edit.
  insert into public.audit_logs(
    actor_user_id, action_code, entity_type, entity_id, old_data, new_data
  )
  values (
    auth.uid(), 'EXPENSE_UPDATED', 'expense', p_expense_id::text,
    to_jsonb(v_old), to_jsonb(v_expense)
  );

  return v_expense;
end;
$$;

create or replace function public.void_expense(
  p_expense_id uuid,
  p_reason text default null
)
returns public.expenses
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_expense public.expenses%rowtype;
  v_reason text := nullif(btrim(coalesce(p_reason, '')), '');
begin
  if not public.has_permission('expenses.manage') then
    raise exception 'Permission denied';
  end if;

  if v_reason is null then
    raise exception 'A reason is required to void an expense';
  end if;

  update public.expenses
  set status = 'VOIDED',
      voided_at = now(),
      voided_by = auth.uid(),
      void_reason = v_reason
  where id = p_expense_id
    and status <> 'VOIDED'
  returning * into v_expense;

  if not found then
    raise exception 'Expense not available';
  end if;

  insert into public.audit_logs(
    actor_user_id, action_code, entity_type, entity_id, new_data
  )
  values (
    auth.uid(), 'EXPENSE_VOIDED', 'expense', p_expense_id::text,
    jsonb_build_object(
      'expense_number', v_expense.expense_number,
      'amount', v_expense.amount,
      'reason', v_reason
    )
  );

  return v_expense;
end;
$$;

-- ============================================================
-- 2. Suppliers: change only what the caller sends
-- ============================================================

-- A null argument now means "leave this field as it is". An empty string
-- clears a text field. The defaults for terms and active status become null
-- for the same reason; the signature and its grants are unchanged.
create or replace function public.update_supplier(
  p_supplier_id uuid,
  p_name text,
  p_contact_person text default null,
  p_phone text default null,
  p_email text default null,
  p_address text default null,
  p_payment_terms_days integer default null,
  p_notes text default null,
  p_is_active boolean default null
)
returns public.suppliers
language plpgsql
security definer
set search_path = public
as $$
declare
  v_old public.suppliers%rowtype;
  v_supplier public.suppliers%rowtype;
begin
  if not public.has_permission('suppliers.manage') then
    raise exception 'Permission denied';
  end if;

  select * into v_old
  from public.suppliers
  where id = p_supplier_id
  for update;

  if not found then
    raise exception 'Supplier not found';
  end if;

  if p_name is not null and btrim(p_name) = '' then
    raise exception 'Supplier name is required';
  end if;

  if p_payment_terms_days is not null and p_payment_terms_days < 0 then
    raise exception 'Payment terms cannot be negative';
  end if;

  update public.suppliers
  set
    name = coalesce(btrim(p_name), name),
    contact_person = case
      when p_contact_person is null then contact_person
      else nullif(btrim(p_contact_person), '')
    end,
    phone = case
      when p_phone is null then phone
      else nullif(btrim(p_phone), '')
    end,
    email = case
      when p_email is null then email
      else nullif(btrim(p_email), '')
    end,
    address = case
      when p_address is null then address
      else nullif(btrim(p_address), '')
    end,
    payment_terms_days = coalesce(p_payment_terms_days, payment_terms_days),
    notes = case
      when p_notes is null then notes
      else nullif(btrim(p_notes), '')
    end,
    is_active = coalesce(p_is_active, is_active),
    archived_at = case
      when p_is_active is null then archived_at
      when p_is_active then null
      else coalesce(archived_at, now())
    end
  where id = p_supplier_id
  returning * into v_supplier;

  insert into public.audit_logs(
    actor_user_id, action_code, entity_type, entity_id, old_data, new_data
  )
  values (
    auth.uid(), 'SUPPLIER_UPDATED', 'supplier', p_supplier_id::text,
    to_jsonb(v_old), to_jsonb(v_supplier)
  );

  return v_supplier;
end;
$$;

-- ============================================================
-- 3. Voiding posted stock documents
-- ============================================================

alter table public.goods_receipts
  add column voided_at timestamptz,
  add column voided_by uuid references public.profiles(id),
  add column void_reason text;

alter table public.stock_out_transactions
  add column voided_at timestamptz,
  add column voided_by uuid references public.profiles(id),
  add column void_reason text;

alter table public.stock_counts
  add column voided_at timestamptz,
  add column voided_by uuid references public.profiles(id),
  add column void_reason text;

-- A release took stock out of lots. Voiding puts each quantity back into
-- the lot it came from.
create function public.void_stock_out(
  p_stock_out_id uuid,
  p_reason text,
  p_client_request_id uuid default null
)
returns public.stock_out_transactions
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_request_result uuid;
  v_doc public.stock_out_transactions%rowtype;
  v_move public.stock_movements%rowtype;
  v_reason text := nullif(btrim(coalesce(p_reason, '')), '');
begin
  v_request_result := public.claim_client_request(
    p_client_request_id, 'VOID_STOCK_OUT'
  );
  if v_request_result is not null then
    select * into v_doc
    from public.stock_out_transactions
    where id = v_request_result;
    return v_doc;
  end if;

  if not public.has_permission('inventory.adjust') then
    raise exception 'Permission denied';
  end if;

  if v_reason is null then
    raise exception 'A reason is required to void a stock release';
  end if;

  select * into v_doc
  from public.stock_out_transactions
  where id = p_stock_out_id
  for update;

  if not found or v_doc.status <> 'POSTED' then
    raise exception 'Only a posted stock release can be voided';
  end if;

  for v_move in
    select sm.*
    from public.stock_movements sm
    where sm.reference_type = 'STOCK_OUT'
      and sm.reference_id = p_stock_out_id
      and sm.movement_type = 'MANUAL_OUT'
    order by sm.created_at, sm.id
  loop
    if v_move.inventory_lot_id is null then
      raise exception 'A release movement has no lot and cannot be reversed';
    end if;

    update public.inventory_lots
    set remaining_quantity = remaining_quantity + abs(v_move.quantity_delta),
        status = case when status = 'DEPLETED' then 'AVAILABLE' else status end
    where id = v_move.inventory_lot_id;

    insert into public.stock_movements(
      inventory_item_id, inventory_lot_id, movement_type, quantity_delta,
      unit_cost_base, reference_type, reference_id, stock_out_item_id,
      reason, recorded_by
    )
    values (
      v_move.inventory_item_id, v_move.inventory_lot_id, 'REVERSAL',
      abs(v_move.quantity_delta), v_move.unit_cost_base, 'STOCK_OUT',
      p_stock_out_id, v_move.stock_out_item_id,
      'Void of SO-' || v_doc.stock_out_number::text || ': ' || v_reason,
      auth.uid()
    );
  end loop;

  update public.stock_out_transactions
  set status = 'VOIDED',
      voided_at = now(),
      voided_by = auth.uid(),
      void_reason = v_reason
  where id = p_stock_out_id
  returning * into v_doc;

  insert into public.audit_logs(
    actor_user_id, action_code, entity_type, entity_id, new_data
  )
  values (
    auth.uid(), 'STOCK_OUT_VOIDED', 'stock_out_transaction',
    p_stock_out_id::text,
    jsonb_build_object(
      'stock_out_number', v_doc.stock_out_number, 'reason', v_reason
    )
  );

  perform public.record_client_request(
    p_client_request_id, 'VOID_STOCK_OUT', v_doc.id
  );

  return v_doc;
end;
$$;

-- A count posted its variances. Voiding removes the stock it added, provided
-- that stock is still there, and puts back the stock it removed.
create function public.void_stock_count(
  p_stock_count_id uuid,
  p_reason text,
  p_client_request_id uuid default null
)
returns public.stock_counts
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_request_result uuid;
  v_doc public.stock_counts%rowtype;
  v_move public.stock_movements%rowtype;
  v_lot public.inventory_lots%rowtype;
  v_reason text := nullif(btrim(coalesce(p_reason, '')), '');
begin
  v_request_result := public.claim_client_request(
    p_client_request_id, 'VOID_STOCK_COUNT'
  );
  if v_request_result is not null then
    select * into v_doc
    from public.stock_counts
    where id = v_request_result;
    return v_doc;
  end if;

  if not public.has_permission('inventory.adjust') then
    raise exception 'Permission denied';
  end if;

  if v_reason is null then
    raise exception 'A reason is required to void an inventory count';
  end if;

  select * into v_doc
  from public.stock_counts
  where id = p_stock_count_id
  for update;

  if not found or v_doc.status <> 'POSTED' then
    raise exception 'Only a posted inventory count can be voided';
  end if;

  for v_move in
    select sm.*
    from public.stock_movements sm
    where sm.reference_type = 'STOCK_COUNT'
      and sm.reference_id = p_stock_count_id
      and sm.movement_type = 'STOCK_COUNT_ADJUSTMENT'
    order by sm.created_at, sm.id
  loop
    if v_move.inventory_lot_id is null then
      raise exception 'A count movement has no lot and cannot be reversed';
    end if;

    select * into v_lot
    from public.inventory_lots
    where id = v_move.inventory_lot_id
    for update;

    if v_move.quantity_delta > 0 then
      if v_lot.remaining_quantity < v_move.quantity_delta then
        raise exception
          'Stock added by this count has already been used. Post a new count instead of voiding this one.';
      end if;

      update public.inventory_lots
      set remaining_quantity = remaining_quantity - v_move.quantity_delta,
          status = case
            when remaining_quantity - v_move.quantity_delta <= 0
              then 'DEPLETED'
            else status
          end
      where id = v_lot.id;
    else
      update public.inventory_lots
      set remaining_quantity = remaining_quantity + abs(v_move.quantity_delta),
          status = case
            when status = 'DEPLETED' then 'AVAILABLE' else status
          end
      where id = v_lot.id;
    end if;

    insert into public.stock_movements(
      inventory_item_id, inventory_lot_id, movement_type, quantity_delta,
      unit_cost_base, reference_type, reference_id, reason, recorded_by
    )
    values (
      v_move.inventory_item_id, v_move.inventory_lot_id, 'REVERSAL',
      -v_move.quantity_delta, v_move.unit_cost_base, 'STOCK_COUNT',
      p_stock_count_id,
      'Void of IC-' || v_doc.count_number::text || ': ' || v_reason,
      auth.uid()
    );
  end loop;

  update public.stock_counts
  set status = 'CANCELLED',
      voided_at = now(),
      voided_by = auth.uid(),
      void_reason = v_reason
  where id = p_stock_count_id
  returning * into v_doc;

  insert into public.audit_logs(
    actor_user_id, action_code, entity_type, entity_id, new_data
  )
  values (
    auth.uid(), 'STOCK_COUNT_VOIDED', 'stock_count', p_stock_count_id::text,
    jsonb_build_object('count_number', v_doc.count_number, 'reason', v_reason)
  );

  perform public.record_client_request(
    p_client_request_id, 'VOID_STOCK_COUNT', v_doc.id
  );

  return v_doc;
end;
$$;

-- A receipt put stock into new lots. It can be voided only while all of
-- that stock is still there and its supplier bill is unpaid; otherwise the
-- remainder is corrected by disposal or adjustment.
create function public.void_goods_receipt(
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

  if found and exists (
    select 1
    from public.supplier_bill_payments sbp
    where sbp.supplier_bill_id = v_bill.id
  ) then
    raise exception
      'The supplier bill for this receipt has payments recorded, so the receipt cannot be voided.';
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

revoke all on function public.void_stock_out(uuid,text,uuid)
from public, anon;
grant execute on function public.void_stock_out(uuid,text,uuid)
to authenticated;

revoke all on function public.void_stock_count(uuid,text,uuid)
from public, anon;
grant execute on function public.void_stock_count(uuid,text,uuid)
to authenticated;

revoke all on function public.void_goods_receipt(uuid,text,uuid)
from public, anon;
grant execute on function public.void_goods_receipt(uuid,text,uuid)
to authenticated;
