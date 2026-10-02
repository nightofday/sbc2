begin;

create extension if not exists pgtap with schema extensions;

select plan(20);

insert into auth.users (id, email)
values
  ('c0000000-0000-0000-0000-000000000001', 'shift-admin-db-test@example.com'),
  ('c0000000-0000-0000-0000-000000000002', 'shift-cashier-db-test@example.com'),
  ('c0000000-0000-0000-0000-000000000003', 'shift-other-db-test@example.com');

delete from public.profiles
where id in (
  'c0000000-0000-0000-0000-000000000001',
  'c0000000-0000-0000-0000-000000000002',
  'c0000000-0000-0000-0000-000000000003'
);

insert into public.profiles (id, role_id, status, display_name)
values
  (
    'c0000000-0000-0000-0000-000000000001',
    (select id from public.roles where code = 'ADMIN'),
    'ACTIVE',
    'Shift Test Admin'
  ),
  (
    'c0000000-0000-0000-0000-000000000002',
    (select id from public.roles where code = 'CASHIER'),
    'ACTIVE',
    'Shift Test Cashier'
  ),
  (
    'c0000000-0000-0000-0000-000000000003',
    (select id from public.roles where code = 'CASHIER'),
    'ACTIVE',
    'Shift Test Other Cashier'
  );

-- Unused objects are gone -------------------------------------------------

select ok(
  to_regclass('public.v_daily_sales') is null
    and to_regclass('public.v_product_sales') is null
    and to_regclass('public.v_product_sales_daily') is null
    and to_regclass('public.v_daily_profit_estimate') is null
    and to_regclass('public.v_order_cogs') is null
    and to_regclass('public.v_shift_summary') is null,
  'the unused reporting views are removed'
);

select ok(
  not exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname in (
        'place_order', 'update_order_item_quantity', 'remove_order_item'
      )
  ),
  'the unused order-editing functions are removed'
);

select ok(
  to_regprocedure(
    'public.place_order_v2(text,jsonb,jsonb,jsonb,text,text,text,text,uuid)'
  ) is not null,
  'the checkout function the till uses is still there'
);

-- A shift with two sales and a payout --------------------------------------

set local role authenticated;
set local request.jwt.claim.role = 'authenticated';
set local request.jwt.claim.sub = 'c0000000-0000-0000-0000-000000000001';

select lives_ok(
  $test$
    select public.create_inventory_item_with_initial_stock(
      'Shift Test Bar', null,
      (select id from public.units_of_measure where code = 'pc'),
      'SHIFT-TEST-INV', false, 0, 20, null, 10
    );
    select public.create_menu_item_with_variant(
      'Shift Test Bar',
      (select id from public.menu_categories where name = 'Snacks'),
      'Regular', 'SHIFT-TEST-SKU', 80, 'FINISHED_GOOD',
      (select id from public.inventory_items where sku = 'SHIFT-TEST-INV')
    );
  $test$,
  'a product is set up'
);

set local request.jwt.claim.sub = 'c0000000-0000-0000-0000-000000000002';

select lives_ok(
  $test$ select public.start_shift(null, 500) $test$,
  'the cashier opens a shift with 500 in the drawer'
);

select lives_ok(
  $test$
    select public.place_order_v2(
      p_order_type := 'TAKE_OUT',
      p_items := jsonb_build_array(jsonb_build_object(
        'menu_variant_id',
        (select id from public.menu_variants where sku = 'SHIFT-TEST-SKU'),
        'quantity', 2
      )),
      p_payment := jsonb_build_object(
        'payment_method_id',
        (select id from public.payment_methods where code = 'CASH'),
        'amount_tendered', 200
      ),
      p_customer_name := 'Shift Test Cash Sale'
    );
    select public.place_order_v2(
      p_order_type := 'TAKE_OUT',
      p_items := jsonb_build_array(jsonb_build_object(
        'menu_variant_id',
        (select id from public.menu_variants where sku = 'SHIFT-TEST-SKU'),
        'quantity', 1
      )),
      p_payment := jsonb_build_object(
        'payment_method_id',
        (select id from public.payment_methods where code = 'GCASH'),
        'external_reference', 'SHIFT-TEST-REF'
      ),
      p_customer_name := 'Shift Test GCash Sale'
    );
    select public.record_shift_cash_movement(
      public.current_open_shift_id(), 'PAY_OUT', 50, 'Shift test ice'
    );
  $test$,
  'a cash sale, a GCash sale and a payout are recorded'
);

create temporary table shift_report on commit drop as
select public.get_shift_report(public.current_open_shift_id()) as report;
grant select on shift_report to authenticated;

select is(
  (select (report #>> '{sales,order_count}')::int from shift_report),
  2,
  'the report counts both sales'
);

select is(
  (select (report #>> '{sales,gross_sales}')::numeric from shift_report),
  240::numeric,
  'gross sales are the value of both sales'
);

select is(
  (select (report #>> '{sales,net_sales}')::numeric from shift_report),
  240::numeric,
  'with no discount or refund, net equals gross'
);

select is(
  (
    select (method ->> 'received')::numeric
    from shift_report, jsonb_array_elements(report -> 'by_payment_method') method
    where (method ->> 'is_cash')::boolean
  ),
  160::numeric,
  'cash received is the cash sale, not the amount tendered'
);

select is(
  (
    select sum((method ->> 'net')::numeric)
    from shift_report, jsonb_array_elements(report -> 'by_payment_method') method
  ),
  (select (report #>> '{sales,net_sales}')::numeric from shift_report),
  'the payment methods add up to net sales'
);

select is(
  (select (report #>> '{cash,expected_cash}')::numeric from shift_report),
  610::numeric,
  'expected cash is opening plus cash sales less the payout'
);

select is(
  (select jsonb_array_length(report -> 'cash_movements') from shift_report),
  1,
  'the payout is listed'
);

select is(
  (select report ->> 'status' from shift_report),
  'OPEN',
  'the report can be read while the shift is open'
);

-- Closing ------------------------------------------------------------------

select lives_ok(
  $test$
    select public.end_shift(
      public.current_open_shift_id(), 600, 'Shift test close'
    )
  $test$,
  'the cashier closes the shift counting 600'
);

select is(
  (
    select (public.get_shift_report(s.id) #>> '{cash,variance}')::numeric
    from public.shifts s
    where s.employee_id = 'c0000000-0000-0000-0000-000000000002'
  ),
  -10::numeric,
  'the closed shift reports the drawer 10 short'
);

select is(
  (
    select jsonb_array_length(
      public.list_shifts(public.business_today(), public.business_today())
    )
  ),
  1,
  'a cashier lists their own shift'
);

-- Who may read it ----------------------------------------------------------

-- Row security hides the shift itself from the other cashier, so its ID
-- is noted first to prove the function refuses it too.
create temporary table closed_shift on commit drop as
select id from public.shifts
where employee_id = 'c0000000-0000-0000-0000-000000000002';
grant select on closed_shift to authenticated;

set local request.jwt.claim.sub = 'c0000000-0000-0000-0000-000000000003';

select throws_ok(
  $test$
    select public.get_shift_report((select id from closed_shift))
  $test$,
  'P0001',
  'Permission denied for this shift',
  'another cashier cannot read the report'
);

select is(
  (
    select jsonb_array_length(
      public.list_shifts(public.business_today(), public.business_today())
    )
  ),
  0,
  'another cashier does not see the shift in the list'
);

set local request.jwt.claim.sub = 'c0000000-0000-0000-0000-000000000001';

select ok(
  (
    select count(*)
    from jsonb_array_elements(
      public.list_shifts(public.business_today(), public.business_today())
    ) shift
    where shift.value ->> 'employee_name' = 'Shift Test Cashier'
      and (shift.value ->> 'variance')::numeric = -10
  ) = 1,
  'a manager sees the shift and its variance in the list'
);

select * from finish();
rollback;
