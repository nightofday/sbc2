-- Cash-drawer movement RPC and shift cash snapshot for Flutter.

create or replace function public.record_shift_cash_movement(
  p_shift_id uuid,
  p_movement_type text,
  p_amount numeric,
  p_reason text
)
returns public.shift_cash_movements
language plpgsql
security definer
set search_path = public
as $$
declare
  v_shift public.shifts%rowtype;
  v_movement public.shift_cash_movements%rowtype;
  v_type text;
begin
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

  return v_movement;
end;
$$;

revoke all on function public.record_shift_cash_movement(uuid,text,numeric,text)
from public, anon;
grant execute on function public.record_shift_cash_movement(uuid,text,numeric,text)
to authenticated;

create or replace function public.get_shift_cash_snapshot(
  p_shift_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_shift public.shifts%rowtype;
  v_shift_id uuid;
  v_cash_method uuid;
  v_cash_sales numeric(14,2) := 0;
  v_cash_refunds numeric(14,2) := 0;
  v_cash_in numeric(14,2) := 0;
  v_cash_out numeric(14,2) := 0;
  v_expected numeric(14,2) := 0;
begin
  v_shift_id := coalesce(p_shift_id,public.current_open_shift_id());

  if v_shift_id is null then
    raise exception 'Open shift not found';
  end if;

  select * into v_shift from public.shifts where id=v_shift_id;

  if not found then
    raise exception 'Shift not found';
  end if;

  if v_shift.employee_id <> auth.uid()
     and not public.has_permission('shift.manage') then
    raise exception 'Permission denied for this shift';
  end if;

  select id into v_cash_method
  from public.payment_methods where code='CASH' limit 1;

  if v_cash_method is not null then
    select coalesce(sum(amount),0)
    into v_cash_sales
    from public.payments
    where shift_id=v_shift_id
      and payment_method_id=v_cash_method
      and transaction_type='PAYMENT'
      and status='COMPLETED';

    select coalesce(sum(amount),0)
    into v_cash_refunds
    from public.payments
    where shift_id=v_shift_id
      and payment_method_id=v_cash_method
      and transaction_type='REFUND'
      and status='COMPLETED';
  end if;

  select
    coalesce(sum(case
      when movement_type in ('PAY_IN','CORRECTION') then amount
      else 0 end),0),
    coalesce(sum(case
      when movement_type in ('PAY_OUT','CASH_DROP') then amount
      else 0 end),0)
  into v_cash_in,v_cash_out
  from public.shift_cash_movements
  where shift_id=v_shift_id;

  v_expected :=
    coalesce(v_shift.opening_cash,0)
    + v_cash_sales
    + v_cash_in
    - v_cash_refunds
    - v_cash_out;

  return jsonb_build_object(
    'shift_id',v_shift_id,
    'opening_cash',coalesce(v_shift.opening_cash,0),
    'cash_sales',v_cash_sales,
    'cash_refunds',v_cash_refunds,
    'cash_in',v_cash_in,
    'cash_out',v_cash_out,
    'expected_cash',v_expected,
    'status',v_shift.status
  );
end;
$$;

revoke all on function public.get_shift_cash_snapshot(uuid)
from public, anon;
grant execute on function public.get_shift_cash_snapshot(uuid)
to authenticated;
