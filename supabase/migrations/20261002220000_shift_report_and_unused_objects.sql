-- Shift report, and removal of objects nothing uses.
--
-- 1. get_shift_report(shift) is the end-of-shift ("Z") report: sales,
--    discounts and refunds for the shift, what each payment method took,
--    every cash movement, and the drawer count against what was expected.
--    list_shifts(from, to) lists shifts for a date range so a closed shift
--    can be looked up later. Both replace the unused v_shift_summary view,
--    which showed order totals only and no cash.
--
-- 2. Views and functions that neither the app, another function, a policy
--    nor a trigger refers to are dropped. They are definitions only: no
--    stored data is removed.
--      v_daily_sales, v_product_sales, v_product_sales_daily: superseded by
--        get_business_report (20261002200000), which is the single place
--        the sales definitions live.
--      v_daily_profit_estimate, v_order_cogs: presented an estimated
--        "profit" from costs the business rules say must not be shown as
--        profit.
--      place_order (first version), update_order_item_quantity,
--        remove_order_item: an order-editing flow the till never used.
--        Checkout goes through place_order_v2 only.

drop view if exists public.v_daily_profit_estimate;
drop view if exists public.v_order_cogs;
drop view if exists public.v_product_sales;
drop view if exists public.v_product_sales_daily;
drop view if exists public.v_daily_sales;
drop view if exists public.v_shift_summary;

do $$
declare
  v_function record;
begin
  for v_function in
    select p.oid::regprocedure as signature
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname in (
        'place_order', 'update_order_item_quantity', 'remove_order_item'
      )
  loop
    execute format('drop function %s', v_function.signature);
  end loop;
end;
$$;

create function public.get_shift_report(p_shift_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_shift public.shifts%rowtype;
  v_cash jsonb;
  v_sales jsonb;
  v_by_payment jsonb;
  v_movements jsonb;
  v_refunds numeric(14,2);
begin
  select * into v_shift from public.shifts where id = p_shift_id;

  if not found then
    raise exception 'Shift not found';
  end if;

  if v_shift.employee_id <> auth.uid()
     and not public.has_permission('shift.manage') then
    raise exception 'Permission denied for this shift';
  end if;

  -- The same cash arithmetic the close-shift screen uses.
  v_cash := public.get_shift_cash_snapshot(p_shift_id);

  select coalesce(sum(r.total_amount), 0)
  into v_refunds
  from public.refunds r
  where r.shift_id = p_shift_id
    and r.status = 'COMPLETED';

  select jsonb_build_object(
    'order_count', count(*) filter (
      where o.status in ('COMPLETED', 'PARTIALLY_REFUNDED', 'REFUNDED')
    ),
    'voided_count', count(*) filter (where o.status = 'VOIDED'),
    'gross_sales', coalesce(sum(o.subtotal) filter (
      where o.status in ('COMPLETED', 'PARTIALLY_REFUNDED', 'REFUNDED')
    ), 0)::numeric(14,2),
    'discounts', coalesce(sum(o.discount_amount) filter (
      where o.status in ('COMPLETED', 'PARTIALLY_REFUNDED', 'REFUNDED')
    ), 0)::numeric(14,2),
    'refunds', v_refunds,
    'net_sales', (
      coalesce(sum(o.subtotal - o.discount_amount) filter (
        where o.status in ('COMPLETED', 'PARTIALLY_REFUNDED', 'REFUNDED')
      ), 0) - v_refunds
    )::numeric(14,2)
  )
  into v_sales
  from public.orders o
  where o.shift_id = p_shift_id;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'payment_method', x.name,
      'is_cash', x.is_cash,
      'payment_count', x.payment_count,
      'received', x.received,
      'refunded', x.refunded,
      'net', (x.received - x.refunded)::numeric(14,2)
    )
    order by x.is_cash desc, x.name
  ), '[]'::jsonb)
  into v_by_payment
  from (
    select
      pm.name,
      pm.is_cash,
      count(*) filter (where p.transaction_type = 'PAYMENT') as payment_count,
      coalesce(sum(p.amount) filter (
        where p.transaction_type = 'PAYMENT'
      ), 0)::numeric(14,2) as received,
      coalesce(sum(p.amount) filter (
        where p.transaction_type = 'REFUND'
      ), 0)::numeric(14,2) as refunded
    from public.payments p
    join public.payment_methods pm on pm.id = p.payment_method_id
    where p.shift_id = p_shift_id
      and p.status = 'COMPLETED'
    group by pm.name, pm.is_cash
  ) x;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'movement_type', m.movement_type,
      'amount', m.amount,
      'reason', m.reason,
      'recorded_by', coalesce(p.display_name, ''),
      'created_at', m.created_at
    )
    order by m.created_at
  ), '[]'::jsonb)
  into v_movements
  from public.shift_cash_movements m
  left join public.profiles p on p.id = m.recorded_by
  where m.shift_id = p_shift_id;

  return jsonb_build_object(
    'shift_id', v_shift.id,
    'shift_number', v_shift.shift_number,
    'status', v_shift.status,
    'employee_name', (
      select coalesce(
        p.display_name, concat_ws(' ', p.first_name, p.last_name)
      )
      from public.profiles p
      where p.id = v_shift.employee_id
    ),
    'started_at', v_shift.started_at,
    'ended_at', v_shift.ended_at,
    'closing_notes', v_shift.closing_notes,
    'sales', v_sales,
    'by_payment_method', v_by_payment,
    'cash_movements', v_movements,
    'cash', jsonb_build_object(
      'opening_cash', coalesce(v_shift.opening_cash, 0),
      'cash_sales', v_cash -> 'cash_sales',
      'cash_refunds', v_cash -> 'cash_refunds',
      'cash_in', v_cash -> 'cash_in',
      'cash_out', v_cash -> 'cash_out',
      -- A closed shift reports what was expected when it was closed.
      'expected_cash', coalesce(
        to_jsonb(v_shift.expected_closing_cash), v_cash -> 'expected_cash'
      ),
      'counted_cash', v_shift.closing_cash_counted,
      'variance', v_shift.cash_variance
    )
  );
end;
$$;

revoke all on function public.get_shift_report(uuid) from public, anon;
grant execute on function public.get_shift_report(uuid) to authenticated;

create function public.list_shifts(p_from date, p_to date)
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
  v_all boolean := public.has_permission('shift.manage');
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  if p_from is null or p_to is null or p_to < p_from then
    raise exception 'A valid date range is required';
  end if;

  v_start := p_from::timestamp at time zone v_tz;
  v_end := (p_to + 1)::timestamp at time zone v_tz;

  return coalesce((
    select jsonb_agg(
      jsonb_build_object(
        'shift_id', s.id,
        'shift_number', s.shift_number,
        'status', s.status,
        'employee_name', coalesce(
          p.display_name, concat_ws(' ', p.first_name, p.last_name)
        ),
        'started_at', s.started_at,
        'ended_at', s.ended_at,
        'opening_cash', coalesce(s.opening_cash, 0),
        'expected_cash', s.expected_closing_cash,
        'counted_cash', s.closing_cash_counted,
        'variance', s.cash_variance,
        'order_count', (
          select count(*)
          from public.orders o
          where o.shift_id = s.id
            and o.status in ('COMPLETED', 'PARTIALLY_REFUNDED', 'REFUNDED')
        )
      )
      order by s.started_at desc
    )
    from public.shifts s
    join public.profiles p on p.id = s.employee_id
    where s.started_at >= v_start
      and s.started_at < v_end
      -- Staff without shift management see their own shifts only.
      and (v_all or s.employee_id = auth.uid())
  ), '[]'::jsonb);
end;
$$;

revoke all on function public.list_shifts(date, date) from public, anon;
grant execute on function public.list_shifts(date, date) to authenticated;
