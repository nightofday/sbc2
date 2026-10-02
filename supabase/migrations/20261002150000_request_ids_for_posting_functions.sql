-- S-06: request IDs for the remaining posting functions.
--
-- Order placement was made retry-safe in 20261002134000. The functions below
-- post a document or a ledger movement and had no protection: a retry after
-- a lost response posted it twice. Each gains an optional final parameter,
-- `p_client_request_id`. When it is supplied and that request has already
-- completed for the same user, the stored result is returned and nothing is
-- posted again. When it is null the function behaves exactly as before.
--
-- A new parameter is a new signature, so each function is dropped and
-- recreated instead of leaving two overloads. Bodies are the current
-- definitions with only the request-ID lines added.

create table public.client_requests (
  request_id uuid primary key,
  operation text not null,
  user_id uuid not null references public.profiles(id),
  result_id uuid not null,
  created_at timestamptz not null default now()
);

create index idx_client_requests_user
  on public.client_requests(user_id, created_at desc);

-- Written and read only by the functions below.
alter table public.client_requests enable row level security;
revoke all on table public.client_requests from public, anon, authenticated;

-- Returns the stored result of a completed request, or null when the request
-- is new. A second submission of the same request waits on the lock until
-- the first transaction ends.
create function public.claim_client_request(
  p_request_id uuid,
  p_operation text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_request public.client_requests%rowtype;
begin
  if p_request_id is null then
    return null;
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended('client_request:' || p_request_id::text, 0)
  );

  select * into v_request
  from public.client_requests
  where request_id = p_request_id;

  if not found then
    return null;
  end if;

  if v_request.user_id is distinct from auth.uid()
     or v_request.operation <> p_operation then
    raise exception 'This request ID is not available';
  end if;

  return v_request.result_id;
end;
$$;

create function public.record_client_request(
  p_request_id uuid,
  p_operation text,
  p_result_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_request_id is null then
    return;
  end if;

  insert into public.client_requests(
    request_id, operation, user_id, result_id
  )
  values (p_request_id, p_operation, auth.uid(), p_result_id);
end;
$$;

revoke all on function public.claim_client_request(uuid,text)
from public, anon, authenticated;
revoke all on function public.record_client_request(uuid,text,uuid)
from public, anon, authenticated;

drop function public.start_shift(uuid,numeric);

create function public.start_shift(
  p_device_id uuid default null,
  p_opening_cash numeric default null,
  p_client_request_id uuid default null
)
returns public.shifts
language plpgsql
security definer
set search_path = public
as $$
declare
  v_request_result uuid;
  v_profile public.profiles%rowtype;
  v_shift public.shifts%rowtype;
  v_require_opening boolean := false;
begin
  v_request_result := public.claim_client_request(
    p_client_request_id, 'START_SHIFT'
  );
  if v_request_result is not null then
    select * into v_shift from public.shifts where id = v_request_result;
    return v_shift;
  end if;

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
  perform public.record_client_request(
    p_client_request_id, 'START_SHIFT', v_shift.id
  );

  return v_shift;
end;
$$;

revoke all on function public.start_shift(uuid,numeric,uuid)
from public, anon;
grant execute on function public.start_shift(uuid,numeric,uuid)
to authenticated;

drop function public.end_shift(uuid,numeric,text);

create function public.end_shift(
  p_shift_id uuid,
  p_closing_cash_counted numeric default null,
  p_notes text default null,
  p_client_request_id uuid default null
)
returns public.shifts
language plpgsql
security definer
set search_path = public
as $$
declare
  v_request_result uuid;
  v_shift public.shifts%rowtype;
  v_cash_sales numeric(14,2) := 0;
  v_cash_refunds numeric(14,2) := 0;
  v_cash_in numeric(14,2) := 0;
  v_cash_out numeric(14,2) := 0;
  v_expected numeric(14,2) := 0;
  v_cash_method uuid;
  v_require_closing boolean := false;
begin
  v_request_result := public.claim_client_request(
    p_client_request_id, 'END_SHIFT'
  );
  if v_request_result is not null then
    select * into v_shift from public.shifts where id = v_request_result;
    return v_shift;
  end if;

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
  perform public.record_client_request(
    p_client_request_id, 'END_SHIFT', v_shift.id
  );

  return v_shift;
end;
$$;

revoke all on function public.end_shift(uuid,numeric,text,uuid)
from public, anon;
grant execute on function public.end_shift(uuid,numeric,text,uuid)
to authenticated;

drop function public.record_shift_cash_movement(uuid,text,numeric,text);

create function public.record_shift_cash_movement(
  p_shift_id uuid,
  p_movement_type text,
  p_amount numeric,
  p_reason text,
  p_client_request_id uuid default null
)
returns public.shift_cash_movements
language plpgsql
security definer
set search_path = public
as $$
declare
  v_request_result uuid;
  v_shift public.shifts%rowtype;
  v_movement public.shift_cash_movements%rowtype;
  v_type text;
begin
  v_request_result := public.claim_client_request(
    p_client_request_id, 'SHIFT_CASH_MOVEMENT'
  );
  if v_request_result is not null then
    select * into v_movement from public.shift_cash_movements where id = v_request_result;
    return v_movement;
  end if;

  if not public.has_permission('shift.cash_movement') then
    raise exception 'Permission denied';
  end if;

  select *
  into v_shift
  from public.shifts
  where id = p_shift_id
  for update;

  if not found or v_shift.status <> 'OPEN' then
    raise exception 'Open shift not found';
  end if;

  if v_shift.employee_id <> auth.uid()
     and not public.has_permission('shift.manage') then
    raise exception 'Permission denied for this shift';
  end if;

  v_type := upper(btrim(coalesce(p_movement_type,'')));

  if v_type not in ('PAY_IN','PAY_OUT','CASH_DROP','CORRECTION') then
    raise exception 'Invalid cash movement type';
  end if;

  if p_amount is null or p_amount <= 0 then
    raise exception 'Amount must be greater than zero';
  end if;

  if nullif(btrim(coalesce(p_reason,'')), '') is null then
    raise exception 'Reason is required';
  end if;

  insert into public.shift_cash_movements(
    shift_id,movement_type,amount,reason,recorded_by
  )
  values (
    p_shift_id,v_type,round(p_amount,2),btrim(p_reason),auth.uid()
  )
  returning * into v_movement;

  insert into public.audit_logs(
    actor_user_id,action_code,entity_type,entity_id,device_id,new_data
  )
  values (
    auth.uid(),'SHIFT_CASH_MOVEMENT','shift',p_shift_id::text,
    v_shift.device_id,
    jsonb_build_object(
      'movement_id',v_movement.id,
      'movement_type',v_type,
      'amount',v_movement.amount,
      'reason',v_movement.reason
    )
  );
  perform public.record_client_request(
    p_client_request_id, 'SHIFT_CASH_MOVEMENT', v_movement.id
  );

  return v_movement;
end;
$$;

revoke all on function public.record_shift_cash_movement(uuid,text,numeric,text,uuid)
from public, anon;
grant execute on function public.record_shift_cash_movement(uuid,text,numeric,text,uuid)
to authenticated;

drop function public.process_refund(uuid,jsonb,jsonb,text,uuid);

create function public.process_refund(
  p_order_id uuid,
  p_items jsonb,
  p_payment_returns jsonb,
  p_reason text,
  p_authorized_by uuid,
  p_client_request_id uuid default null
)
returns public.refunds
language plpgsql
security definer
set search_path = public
as $$
declare
  v_request_result uuid;
  v_order public.orders%rowtype;
  v_refund public.refunds%rowtype;
  v_item_json jsonb;
  v_payment jsonb;
  v_order_item public.order_items%rowtype;
  v_qty numeric(14,4);
  v_already_qty numeric(14,4);
  v_already_amount numeric(14,2);
  v_allocated_order_discount numeric(14,2);
  v_net_line numeric(14,2);
  v_unit_refundable numeric(14,6);
  v_line_refund numeric(14,2);
  v_refund_total numeric(14,2) := 0;
  v_return_total numeric(14,2) := 0;
  v_previous_refunds numeric(14,2);
  v_refund_type text;
  v_method public.payment_methods%rowtype;
begin
  v_request_result := public.claim_client_request(
    p_client_request_id, 'REFUND'
  );
  if v_request_result is not null then
    select * into v_refund from public.refunds where id = v_request_result;
    return v_refund;
  end if;

  if not public.has_permission('orders.refund') then
    raise exception 'Permission denied';
  end if;

  if nullif(btrim(coalesce(p_reason,'')), '') is null then
    raise exception 'Refund reason is required';
  end if;

  if p_authorized_by is null then
    raise exception 'Manager authorization is required';
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

  -- First pass validates and calculates the refund from stored sale values.
  for v_item_json in select value from jsonb_array_elements(p_items)
  loop
    select * into v_order_item
    from public.order_items
    where id = (v_item_json ->> 'order_item_id')::uuid
      and order_id = p_order_id;

    if not found then
      raise exception 'Refund item does not belong to order';
    end if;

    v_qty := (v_item_json ->> 'quantity')::numeric;

    select
      coalesce(sum(ri.quantity),0),
      coalesce(sum(ri.refund_amount),0)
    into v_already_qty, v_already_amount
    from public.refund_items ri
    join public.refunds r on r.id = ri.refund_id
    where ri.order_item_id = v_order_item.id
      and r.status = 'COMPLETED';

    if v_qty <= 0 or v_qty + v_already_qty > v_order_item.quantity then
      raise exception 'Invalid refund quantity for order item %', v_order_item.id;
    end if;

    select coalesce(sum(odi.discount_amount),0)
    into v_allocated_order_discount
    from public.order_discount_items odi
    join public.order_discounts od on od.id = odi.order_discount_id
    where odi.order_item_id = v_order_item.id
      and od.order_id = p_order_id;

    v_net_line := greatest(
      0,
      v_order_item.line_total - v_allocated_order_discount
    );

    v_unit_refundable := v_net_line / v_order_item.quantity;
    v_line_refund := round(v_unit_refundable * v_qty,2);

    if v_line_refund <= 0 then
      raise exception 'Calculated refundable amount is zero';
    end if;

    if v_already_amount + v_line_refund > v_net_line + 0.01 then
      raise exception 'Refund exceeds remaining refundable amount';
    end if;

    v_refund_total := v_refund_total + v_line_refund;
  end loop;

  select coalesce(sum(total_amount),0)
  into v_previous_refunds
  from public.refunds
  where order_id = p_order_id
    and status = 'COMPLETED';

  if v_refund_total <= 0
     or round(v_previous_refunds + v_refund_total,2) > round(v_order.total_amount,2) then
    raise exception 'Refund exceeds order total';
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

  -- Second pass stores exactly the server-calculated refund amounts.
  for v_item_json in select value from jsonb_array_elements(p_items)
  loop
    select * into v_order_item
    from public.order_items
    where id = (v_item_json ->> 'order_item_id')::uuid
      and order_id = p_order_id;

    v_qty := (v_item_json ->> 'quantity')::numeric;

    select coalesce(sum(odi.discount_amount),0)
    into v_allocated_order_discount
    from public.order_discount_items odi
    join public.order_discounts od on od.id = odi.order_discount_id
    where odi.order_item_id = v_order_item.id
      and od.order_id = p_order_id;

    v_net_line := greatest(0, v_order_item.line_total - v_allocated_order_discount);
    v_unit_refundable := v_net_line / v_order_item.quantity;
    v_line_refund := round(v_unit_refundable * v_qty,2);

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
      v_order_item.id,
      v_qty,
      v_line_refund,
      false,
      nullif(btrim(coalesce(v_item_json ->> 'notes','')), '')
    );
  end loop;

  if jsonb_typeof(p_payment_returns) <> 'array'
     or jsonb_array_length(p_payment_returns) = 0 then
    raise exception 'Refund payment method is required';
  end if;

  for v_payment in select value from jsonb_array_elements(p_payment_returns)
  loop
    select * into v_method
    from public.payment_methods
    where id = (v_payment ->> 'payment_method_id')::uuid
      and is_active = true;

    if not found then
      raise exception 'Invalid refund payment method';
    end if;

    if v_method.requires_reference
       and nullif(btrim(coalesce(v_payment ->> 'external_reference','')), '') is null then
      raise exception 'Refund reference is required for %', v_method.name;
    end if;

    v_return_total := v_return_total + round((v_payment ->> 'amount')::numeric,2);
  end loop;

  if round(v_return_total,2) <> round(v_refund_total,2) then
    raise exception 'Refund payment total must equal calculated refund total %', v_refund_total;
  end if;

  for v_payment in select value from jsonb_array_elements(p_payment_returns)
  loop
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
      round((v_payment ->> 'amount')::numeric,2),
      nullif(btrim(coalesce(v_payment ->> 'external_provider','')), ''),
      nullif(btrim(coalesce(v_payment ->> 'external_reference','')), ''),
      nullif(v_payment ->> 'idempotency_key','')::uuid,
      auth.uid(),
      public.current_open_shift_id(),
      v_order.device_id
    );
  end loop;

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

  insert into public.audit_logs(
    actor_user_id,
    action_code,
    entity_type,
    entity_id,
    device_id,
    new_data
  )
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
  perform public.record_client_request(
    p_client_request_id, 'REFUND', v_refund.id
  );

  return v_refund;
end;
$$;

revoke all on function public.process_refund(uuid,jsonb,jsonb,text,uuid,uuid)
from public, anon;
grant execute on function public.process_refund(uuid,jsonb,jsonb,text,uuid,uuid)
to authenticated;

drop function public.process_refund_items(uuid,jsonb,text,text);

create function public.process_refund_items(
  p_order_id uuid,
  p_items jsonb,
  p_reason text,
  p_external_reference text default null,
  p_client_request_id uuid default null
)
returns public.refunds
language plpgsql
security definer
set search_path = public
as $$
declare
  v_request_result uuid;
  v_refund public.refunds%rowtype;
  v_preview jsonb;
  v_item jsonb;
  v_requested jsonb;
  v_request_qty numeric(14,4);
  v_remaining_qty numeric(14,4);
  v_unit_refundable numeric(14,6);
  v_total numeric(14,2) := 0;
  v_payment_method_id uuid;
  v_requires_reference boolean;
  v_returns jsonb;
begin
  v_request_result := public.claim_client_request(
    p_client_request_id, 'REFUND'
  );
  if v_request_result is not null then
    select * into v_refund from public.refunds where id = v_request_result;
    return v_refund;
  end if;

  if not public.has_permission('orders.refund') then
    raise exception 'Permission denied';
  end if;

  if jsonb_typeof(coalesce(p_items,'[]'::jsonb)) <> 'array'
     or jsonb_array_length(coalesce(p_items,'[]'::jsonb)) = 0 then
    raise exception 'Select at least one item to refund';
  end if;

  v_preview := public.get_refund_preview(p_order_id);
  v_payment_method_id :=
    nullif(v_preview ->> 'payment_method_id','')::uuid;
  v_requires_reference :=
    coalesce((v_preview ->> 'requires_reference')::boolean,false);

  if v_requires_reference
     and nullif(btrim(coalesce(p_external_reference,'')), '') is null then
    raise exception 'Refund transaction reference is required';
  end if;

  for v_requested in
    select value from jsonb_array_elements(p_items)
  loop
    v_request_qty :=
      nullif(v_requested ->> 'quantity','')::numeric;

    if v_request_qty is null or v_request_qty <= 0 then
      raise exception 'Refund quantity must be greater than zero';
    end if;

    select value
    into v_item
    from jsonb_array_elements(v_preview -> 'items')
    where value ->> 'order_item_id' =
      v_requested ->> 'order_item_id'
    limit 1;

    if v_item is null then
      raise exception 'Order item is not refundable';
    end if;

    v_remaining_qty :=
      (v_item ->> 'remaining_quantity')::numeric;
    v_unit_refundable :=
      (v_item ->> 'unit_refundable')::numeric;

    if v_request_qty > v_remaining_qty then
      raise exception 'Refund quantity exceeds remaining refundable quantity';
    end if;

    v_total := v_total
      + round(v_request_qty * v_unit_refundable,2);
  end loop;

  if v_total <= 0 then
    raise exception 'Calculated refund amount is zero';
  end if;

  v_returns := jsonb_build_array(
    jsonb_build_object(
      'payment_method_id',v_payment_method_id,
      'amount',v_total,
      'external_reference',
        nullif(btrim(coalesce(p_external_reference,'')), '')
    )
  );

  return public.process_refund(
    p_order_id,
    p_items,
    v_returns,
    p_reason,
    auth.uid(),
    p_client_request_id
  );
end;
$$;

revoke all on function public.process_refund_items(uuid,jsonb,text,text,uuid)
from public, anon;
grant execute on function public.process_refund_items(uuid,jsonb,text,text,uuid)
to authenticated;

drop function public.create_and_post_stock_out(text,jsonb,text,text,timestamptz);

create function public.create_and_post_stock_out(
  p_purpose text,
  p_items jsonb,
  p_reference_number text default null,
  p_notes text default null,
  p_occurred_at timestamptz default now(),
  p_client_request_id uuid default null
)
returns public.stock_out_transactions
language plpgsql
security definer
set search_path = public
as $$
declare
  v_request_result uuid;
  v_stock_out public.stock_out_transactions%rowtype;
  v_item public.inventory_items%rowtype;
  v_line jsonb;
  v_lot public.inventory_lots%rowtype;
  v_stock_out_item_id uuid;
  v_inventory_item_id uuid;
  v_issue_uom_id uuid;
  v_issue_quantity numeric(14,4);
  v_base_per_unit numeric(14,4);
  v_base_quantity numeric(14,4);
  v_remaining numeric(14,4);
  v_take numeric(14,4);
begin
  v_request_result := public.claim_client_request(
    p_client_request_id, 'STOCK_OUT'
  );
  if v_request_result is not null then
    select * into v_stock_out from public.stock_out_transactions where id = v_request_result;
    return v_stock_out;
  end if;

  if not public.has_permission('inventory.adjust') then
    raise exception 'Permission denied';
  end if;

  if nullif(btrim(coalesce(p_purpose, '')), '') is null then
    raise exception 'Stock-out purpose is required';
  end if;

  if jsonb_typeof(coalesce(p_items, '[]'::jsonb)) <> 'array'
     or jsonb_array_length(coalesce(p_items, '[]'::jsonb)) = 0 then
    raise exception 'At least one stock-out item is required';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(p_items) line
    group by line ->> 'inventory_item_id'
    having count(*) > 1
  ) then
    raise exception 'Each inventory item may appear only once per stock-out';
  end if;

  insert into public.stock_out_transactions(
    occurred_at, purpose, reference_number, notes, status, recorded_by
  )
  values (
    coalesce(p_occurred_at, now()), btrim(p_purpose),
    nullif(btrim(coalesce(p_reference_number, '')), ''),
    nullif(btrim(coalesce(p_notes, '')), ''), 'DRAFT', auth.uid()
  )
  returning * into v_stock_out;

  for v_line in select value from jsonb_array_elements(p_items)
  loop
    v_inventory_item_id := nullif(v_line ->> 'inventory_item_id', '')::uuid;
    v_issue_uom_id := nullif(v_line ->> 'issue_uom_id', '')::uuid;
    v_issue_quantity := nullif(v_line ->> 'issue_quantity', '')::numeric;
    v_base_per_unit :=
      nullif(v_line ->> 'base_quantity_per_issue_unit', '')::numeric;

    if v_inventory_item_id is null or v_issue_uom_id is null then
      raise exception 'Inventory item and release unit are required';
    end if;

    if v_issue_quantity is null or v_issue_quantity <= 0
       or v_base_per_unit is null or v_base_per_unit <= 0 then
      raise exception 'Stock-out quantities must be greater than zero';
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

    if not exists (
      select 1
      from public.units_of_measure issue_uom
      join public.units_of_measure base_uom
        on base_uom.id = v_item.base_uom_id
       and base_uom.dimension = issue_uom.dimension
      where issue_uom.id = v_issue_uom_id
        and issue_uom.is_active = true
    ) then
      raise exception 'Release unit is unavailable or incompatible with the item base unit';
    end if;

    v_base_quantity := v_issue_quantity * v_base_per_unit;

    insert into public.stock_out_items(
      stock_out_id, inventory_item_id, issue_uom_id, issue_quantity,
      base_quantity_per_issue_unit, base_quantity, notes
    )
    values (
      v_stock_out.id, v_inventory_item_id, v_issue_uom_id,
      v_issue_quantity, v_base_per_unit, v_base_quantity,
      nullif(btrim(coalesce(v_line ->> 'notes', '')), '')
    )
    returning id into v_stock_out_item_id;

    v_remaining := v_base_quantity;

    for v_lot in
      select *
      from public.inventory_lots
      where inventory_item_id = v_inventory_item_id
        and remaining_quantity > 0
        and status = 'AVAILABLE'
        and (expiration_date is null or expiration_date >= (select public.business_today()))
      order by expiration_date asc nulls last, received_at asc
      for update
    loop
      exit when v_remaining <= 0;
      v_take := least(v_remaining, v_lot.remaining_quantity);

      update public.inventory_lots
      set remaining_quantity = remaining_quantity - v_take,
          status = case
            when remaining_quantity - v_take <= 0 then 'DEPLETED'
            else status
          end
      where id = v_lot.id;

      insert into public.stock_movements(
        inventory_item_id, inventory_lot_id, movement_type,
        quantity_delta, unit_cost_base, reference_type, reference_id,
        stock_out_item_id, reason, recorded_by
      )
      values (
        v_inventory_item_id, v_lot.id, 'MANUAL_OUT',
        -v_take, v_lot.unit_cost_base, 'STOCK_OUT', v_stock_out.id,
        v_stock_out_item_id, btrim(p_purpose), auth.uid()
      );

      v_remaining := v_remaining - v_take;
    end loop;

    if v_remaining > 0 then
      raise exception 'Insufficient usable stock for item %', v_item.name;
    end if;
  end loop;

  update public.stock_out_transactions
  set status = 'POSTED', posted_at = now()
  where id = v_stock_out.id
  returning * into v_stock_out;

  insert into public.audit_logs(
    actor_user_id, action_code, entity_type, entity_id, new_data
  )
  values (
    auth.uid(), 'STOCK_OUT_POSTED', 'stock_out_transaction',
    v_stock_out.id::text,
    jsonb_build_object(
      'stock_out_number', v_stock_out.stock_out_number,
      'purpose', v_stock_out.purpose,
      'line_count', jsonb_array_length(p_items)
    )
  );
  perform public.record_client_request(
    p_client_request_id, 'STOCK_OUT', v_stock_out.id
  );

  return v_stock_out;
end;
$$;

revoke all on function public.create_and_post_stock_out(text,jsonb,text,text,timestamptz,uuid)
from public, anon;
grant execute on function public.create_and_post_stock_out(text,jsonb,text,text,timestamptz,uuid)
to authenticated;

drop function public.create_and_post_stock_count(jsonb,text,timestamptz);

create function public.create_and_post_stock_count(
  p_items jsonb,
  p_notes text default null,
  p_counted_at timestamptz default now(),
  p_client_request_id uuid default null
)
returns public.stock_counts
language plpgsql
security definer
set search_path = public
as $$
declare
  v_request_result uuid;
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
  v_request_result := public.claim_client_request(
    p_client_request_id, 'STOCK_COUNT'
  );
  if v_request_result is not null then
    select * into v_count from public.stock_counts where id = v_request_result;
    return v_count;
  end if;

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
  perform public.record_client_request(
    p_client_request_id, 'STOCK_COUNT', v_count.id
  );

  return v_count;
end;
$$;

revoke all on function public.create_and_post_stock_count(jsonb,text,timestamptz,uuid)
from public, anon;
grant execute on function public.create_and_post_stock_count(jsonb,text,timestamptz,uuid)
to authenticated;

drop function public.dispose_inventory_lot(uuid,text,numeric,text);

create function public.dispose_inventory_lot(
  p_inventory_lot_id uuid,
  p_movement_type text,
  p_quantity numeric,
  p_reason text default null,
  p_client_request_id uuid default null
)
returns public.inventory_lots
language plpgsql
security definer
set search_path = public
as $$
declare
  v_request_result uuid;
  v_lot public.inventory_lots%rowtype;
  v_type text;
begin
  v_request_result := public.claim_client_request(
    p_client_request_id, 'LOT_DISPOSAL'
  );
  if v_request_result is not null then
    select * into v_lot from public.inventory_lots where id = v_request_result;
    return v_lot;
  end if;

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
  perform public.record_client_request(
    p_client_request_id, 'LOT_DISPOSAL', v_lot.id
  );

  return v_lot;
end;
$$;

revoke all on function public.dispose_inventory_lot(uuid,text,numeric,text,uuid)
from public, anon;
grant execute on function public.dispose_inventory_lot(uuid,text,numeric,text,uuid)
to authenticated;

drop function public.record_supplier_bill_payment(uuid,uuid,numeric,text,text);

create function public.record_supplier_bill_payment(
  p_supplier_bill_id uuid,
  p_payment_method_id uuid,
  p_amount numeric,
  p_reference_number text default null,
  p_notes text default null,
  p_client_request_id uuid default null
)
returns public.supplier_bill_payments
language plpgsql
security definer
set search_path = public
as $$
declare
  v_request_result uuid;
  v_bill public.supplier_bills%rowtype;
  v_paid numeric(14,2);
  v_payment public.supplier_bill_payments%rowtype;
begin
  v_request_result := public.claim_client_request(
    p_client_request_id, 'SUPPLIER_BILL_PAYMENT'
  );
  if v_request_result is not null then
    select * into v_payment from public.supplier_bill_payments where id = v_request_result;
    return v_payment;
  end if;

  if not public.has_permission('finance.manage') then
    raise exception 'Permission denied';
  end if;

  select * into v_bill
  from public.supplier_bills
  where id = p_supplier_bill_id
  for update;

  if not found or v_bill.status = 'VOID' then
    raise exception 'Supplier bill not available';
  end if;

  select coalesce(sum(amount),0)
  into v_paid
  from public.supplier_bill_payments
  where supplier_bill_id = p_supplier_bill_id;

  if p_amount <= 0 or round(v_paid + p_amount,2) > round(v_bill.amount,2) then
    raise exception 'Payment exceeds supplier bill balance';
  end if;

  if exists (
    select 1
    from public.payment_methods pm
    where pm.id = p_payment_method_id
      and pm.requires_reference = true
      and nullif(btrim(coalesce(p_reference_number,'')), '') is null
  ) then
    raise exception 'Payment reference is required';
  end if;

  insert into public.supplier_bill_payments(
    supplier_bill_id,
    payment_method_id,
    amount,
    reference_number,
    recorded_by,
    notes
  )
  values (
    p_supplier_bill_id,
    p_payment_method_id,
    round(p_amount,2),
    nullif(btrim(coalesce(p_reference_number,'')), ''),
    auth.uid(),
    nullif(btrim(coalesce(p_notes,'')), '')
  )
  returning * into v_payment;

  perform public.sync_supplier_bill_status(p_supplier_bill_id);
  perform public.record_client_request(
    p_client_request_id, 'SUPPLIER_BILL_PAYMENT', v_payment.id
  );

  return v_payment;
end;
$$;

revoke all on function public.record_supplier_bill_payment(uuid,uuid,numeric,text,text,uuid)
from public, anon;
grant execute on function public.record_supplier_bill_payment(uuid,uuid,numeric,text,text,uuid)
to authenticated;

drop function public.adjust_inventory_stock(uuid,text,numeric,text,date,numeric);

create function public.adjust_inventory_stock(
  p_inventory_item_id uuid,
  p_movement_type text,
  p_quantity numeric,
  p_reason text,
  p_expiration_date date default null,
  p_unit_cost_base numeric default 0,
  p_client_request_id uuid default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_request_result uuid;
  v_item public.inventory_items%rowtype;
  v_remaining numeric(14,4);
  v_lot public.inventory_lots%rowtype;
  v_take numeric(14,4);
  v_new_lot uuid;
begin
  v_request_result := public.claim_client_request(
    p_client_request_id, 'STOCK_ADJUSTMENT'
  );
  if v_request_result is not null then
    return;
  end if;

  if not public.has_permission('inventory.adjust') then
    raise exception 'Permission denied';
  end if;

  if p_quantity is null or p_quantity <= 0 then
    raise exception 'Quantity must be greater than zero';
  end if;

  select * into v_item
  from public.inventory_items
  where id = p_inventory_item_id
  for update;

  if not found or not v_item.track_inventory then
    raise exception 'Tracked inventory item not found';
  end if;

  p_movement_type := upper(btrim(p_movement_type));

  if p_movement_type = 'MANUAL_IN' then
    if v_item.track_expiry and p_expiration_date is null then
      raise exception 'Expiration date is required for this item';
    end if;

    insert into public.inventory_lots(
      inventory_item_id,
      lot_code,
      received_at,
      expiration_date,
      received_quantity,
      remaining_quantity,
      unit_cost_base
    )
    values (
      p_inventory_item_id,
      'MANUAL-' || to_char(now(),'YYYYMMDDHH24MISS'),
      now(),
      p_expiration_date,
      p_quantity,
      p_quantity,
      greatest(coalesce(p_unit_cost_base,0),0)
    )
    returning id into v_new_lot;

    insert into public.stock_movements(
      inventory_item_id,
      inventory_lot_id,
      movement_type,
      quantity_delta,
      unit_cost_base,
      reference_type,
      reason,
      recorded_by
    )
    values (
      p_inventory_item_id,
      v_new_lot,
      'MANUAL_IN',
      p_quantity,
      greatest(coalesce(p_unit_cost_base,0),0),
      'MANUAL_ADJUSTMENT',
      p_reason,
      auth.uid()
    );

    perform public.record_client_request(
      p_client_request_id, 'STOCK_ADJUSTMENT', p_inventory_item_id
    );

    return;
  end if;

  if p_movement_type not in (
    'MANUAL_OUT','WASTE','DAMAGED','EXPIRED','COMPLIMENTARY','STAFF_MEAL','STOCK_COUNT_ADJUSTMENT'
  ) then
    raise exception 'Unsupported stock-out movement type';
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

    insert into public.stock_movements(
      inventory_item_id,
      inventory_lot_id,
      movement_type,
      quantity_delta,
      unit_cost_base,
      reference_type,
      reason,
      recorded_by
    )
    values (
      p_inventory_item_id,
      v_lot.id,
      p_movement_type,
      -v_take,
      v_lot.unit_cost_base,
      'MANUAL_ADJUSTMENT',
      p_reason,
      auth.uid()
    );

    v_remaining := v_remaining - v_take;
  end loop;

  if v_remaining > 0 then
    raise exception 'Insufficient stock for adjustment';
  end if;

  perform public.record_client_request(
    p_client_request_id, 'STOCK_ADJUSTMENT', p_inventory_item_id
  );
end;
$$;

revoke all on function public.adjust_inventory_stock(uuid,text,numeric,text,date,numeric,uuid)
from public, anon;
grant execute on function public.adjust_inventory_stock(uuid,text,numeric,text,date,numeric,uuid)
to authenticated;

drop function public.create_and_post_goods_receipt(uuid,jsonb,uuid,text,date,text,boolean,date);

create function public.create_and_post_goods_receipt(
  p_supplier_id uuid,
  p_items jsonb,
  p_purchase_order_id uuid default null,
  p_supplier_invoice_number text default null,
  p_supplier_invoice_date date default null,
  p_notes text default null,
  p_create_supplier_bill boolean default true,
  p_due_date date default null,
  p_client_request_id uuid default null
)
returns public.goods_receipts
language plpgsql
security definer
set search_path = public
as $$
declare
  v_request_result uuid;
  v_receipt public.goods_receipts%rowtype;
  v_line jsonb;
  v_inventory_item_id uuid;
  v_purchase_uom_id uuid;
  v_po_item_id uuid;
  v_purchase_qty numeric;
  v_base_per_unit numeric;
  v_base_qty numeric;
  v_unit_cost_purchase numeric;
  v_unit_cost_base numeric;
  v_expiration date;
  v_lot_code text;
  v_total numeric(14,2) := 0;
begin
  v_request_result := public.claim_client_request(
    p_client_request_id, 'GOODS_RECEIPT'
  );
  if v_request_result is not null then
    select * into v_receipt from public.goods_receipts where id = v_request_result;
    return v_receipt;
  end if;

  if not public.has_permission('purchases.receive') then
    raise exception 'Permission denied';
  end if;

  if not exists (
    select 1 from public.suppliers
    where id = p_supplier_id and is_active = true
  ) then
    raise exception 'Supplier is unavailable';
  end if;

  if p_purchase_order_id is not null and not exists (
    select 1
    from public.purchase_orders
    where id = p_purchase_order_id
      and supplier_id = p_supplier_id
      and status in ('APPROVED','SENT','PARTIALLY_RECEIVED')
  ) then
    raise exception 'Purchase order is unavailable for receiving';
  end if;

  if jsonb_typeof(coalesce(p_items,'[]'::jsonb)) <> 'array'
     or jsonb_array_length(coalesce(p_items,'[]'::jsonb)) = 0 then
    raise exception 'At least one received item is required';
  end if;

  insert into public.goods_receipts(
    supplier_id,purchase_order_id,supplier_invoice_number,
    supplier_invoice_date,received_by,status,notes
  )
  values (
    p_supplier_id,p_purchase_order_id,
    nullif(btrim(coalesce(p_supplier_invoice_number,'')), ''),
    p_supplier_invoice_date,auth.uid(),'DRAFT',
    nullif(btrim(coalesce(p_notes,'')), '')
  )
  returning * into v_receipt;

  for v_line in select value from jsonb_array_elements(p_items)
  loop
    v_inventory_item_id := nullif(v_line ->> 'inventory_item_id','')::uuid;
    v_purchase_uom_id := nullif(v_line ->> 'purchase_uom_id','')::uuid;
    v_po_item_id := nullif(v_line ->> 'purchase_order_item_id','')::uuid;
    v_purchase_qty := nullif(v_line ->> 'purchase_quantity','')::numeric;
    v_base_per_unit := nullif(v_line ->> 'base_quantity_per_purchase_unit','')::numeric;
    v_unit_cost_purchase := nullif(v_line ->> 'unit_cost_purchase_uom','')::numeric;
    v_expiration := nullif(v_line ->> 'expiration_date','')::date;
    v_lot_code := nullif(btrim(coalesce(v_line ->> 'lot_code','')), '');

    if v_purchase_qty is null or v_purchase_qty <= 0
       or v_base_per_unit is null or v_base_per_unit <= 0
       or v_unit_cost_purchase is null or v_unit_cost_purchase < 0 then
      raise exception 'Invalid received item values';
    end if;

    if not exists (
      select 1 from public.inventory_items
      where id = v_inventory_item_id and is_active = true
    ) then
      raise exception 'Inventory item is unavailable';
    end if;

    v_base_qty := v_purchase_qty * v_base_per_unit;
    v_unit_cost_base := case
      when v_base_per_unit = 0 then 0
      else v_unit_cost_purchase / v_base_per_unit
    end;

    insert into public.goods_receipt_items(
      goods_receipt_id,purchase_order_item_id,inventory_item_id,purchase_uom_id,
      purchase_quantity,base_quantity_per_purchase_unit,base_quantity,
      unit_cost_purchase_uom,unit_cost_base,lot_code,expiration_date
    )
    values (
      v_receipt.id,v_po_item_id,v_inventory_item_id,v_purchase_uom_id,
      v_purchase_qty,v_base_per_unit,v_base_qty,v_unit_cost_purchase,
      v_unit_cost_base,v_lot_code,v_expiration
    );

    v_total := v_total + round(v_purchase_qty * v_unit_cost_purchase,2);
  end loop;

  perform public.post_goods_receipt(v_receipt.id);

  if coalesce(p_create_supplier_bill,true) then
    insert into public.supplier_bills(
      supplier_id,goods_receipt_id,supplier_invoice_number,invoice_date,
      due_date,amount,status,created_by,notes
    )
    values (
      p_supplier_id,v_receipt.id,
      nullif(btrim(coalesce(p_supplier_invoice_number,'')), ''),
      coalesce(p_supplier_invoice_date,(select public.business_today())),p_due_date,v_total,
      case when v_total = 0 then 'PAID' else 'UNPAID' end,
      auth.uid(),'Created from posted goods receipt'
    );
  end if;

  select * into v_receipt
  from public.goods_receipts
  where id = v_receipt.id;
  perform public.record_client_request(
    p_client_request_id, 'GOODS_RECEIPT', v_receipt.id
  );

  return v_receipt;
end;
$$;

revoke all on function public.create_and_post_goods_receipt(uuid,jsonb,uuid,text,date,text,boolean,date,uuid)
from public, anon;
grant execute on function public.create_and_post_goods_receipt(uuid,jsonb,uuid,text,date,text,boolean,date,uuid)
to authenticated;

drop function public.create_expense(uuid,text,numeric,date,uuid,uuid,text,text);

create function public.create_expense(
  p_expense_category_id uuid,
  p_description text,
  p_amount numeric,
  p_expense_date date default null,
  p_payment_method_id uuid default null,
  p_supplier_id uuid default null,
  p_reference_number text default null,
  p_notes text default null,
  p_client_request_id uuid default null
)
returns public.expenses
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_request_result uuid;
  v_expense public.expenses%rowtype;
  v_category_code text;
begin
  v_request_result := public.claim_client_request(
    p_client_request_id, 'EXPENSE'
  );
  if v_request_result is not null then
    select * into v_expense from public.expenses where id = v_request_result;
    return v_expense;
  end if;

  if not public.has_permission('expenses.manage') then
    raise exception 'Permission denied';
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

  insert into public.expenses(
    expense_date,
    expense_category_id,
    expense_type,
    description,
    amount,
    payment_method_id,
    supplier_id,
    reference_number,
    status,
    recorded_by,
    notes
  )
  values (
    coalesce(p_expense_date, (select public.business_today())),
    p_expense_category_id,
    case
      when v_category_code = 'INGREDIENTS' then 'NON_INVENTORY_PURCHASE'
      else 'OPERATING'
    end,
    btrim(p_description),
    round(p_amount, 2),
    p_payment_method_id,
    p_supplier_id,
    btrim(p_reference_number),
    'POSTED',
    auth.uid(),
    nullif(btrim(coalesce(p_notes, '')), '')
  )
  returning * into v_expense;
  perform public.record_client_request(
    p_client_request_id, 'EXPENSE', v_expense.id
  );

  return v_expense;
end;
$$;

revoke all on function public.create_expense(uuid,text,numeric,date,uuid,uuid,text,text,uuid)
from public, anon;
grant execute on function public.create_expense(uuid,text,numeric,date,uuid,uuid,text,text,uuid)
to authenticated;
