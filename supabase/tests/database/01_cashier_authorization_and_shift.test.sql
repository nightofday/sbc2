begin;

create extension if not exists pgtap with schema extensions;

select plan(22);

insert into auth.users (id, email)
values
  ('10000000-0000-0000-0000-000000000001', 'cashier-db-test@example.com'),
  ('10000000-0000-0000-0000-000000000002', 'admin-db-test@example.com');

delete from public.profiles
where id in (
  '10000000-0000-0000-0000-000000000001',
  '10000000-0000-0000-0000-000000000002'
);

insert into public.profiles (id, role_id, status, display_name)
values
  (
    '10000000-0000-0000-0000-000000000001',
    (select id from public.roles where code = 'CASHIER'),
    'ACTIVE',
    'Database Test Cashier'
  ),
  (
    '10000000-0000-0000-0000-000000000002',
    (select id from public.roles where code = 'ADMIN'),
    'ACTIVE',
    'Database Test Admin'
  );

set local role authenticated;
set local request.jwt.claim.role = 'authenticated';
set local request.jwt.claim.sub = '10000000-0000-0000-0000-000000000001';

select ok(
  public.has_permission('orders.create'),
  'cashier can create orders'
);

select ok(
  public.has_permission('orders.checkout'),
  'cashier can checkout orders'
);

select ok(
  public.has_permission('inventory.view'),
  'cashier can view inventory'
);

select ok(
  not public.has_permission('users.manage'),
  'cashier cannot manage users'
);

select ok(
  not public.has_permission('purchases.manage'),
  'cashier cannot manage purchases'
);

select ok(
  not public.has_permission('finance.view'),
  'cashier cannot view finance records'
);

select is(
  (select count(*) from public.profiles),
  1::bigint,
  'cashier can only read their own profile'
);

select is(
  (
    select count(*)
    from public.profiles
    where id = '10000000-0000-0000-0000-000000000002'
  ),
  0::bigint,
  'cashier cannot read the administrator profile'
);

select lives_ok(
  $test$
    update public.profiles
    set display_name = 'Compromised Admin'
    where id = '10000000-0000-0000-0000-000000000002'
  $test$,
  'unauthorized profile update is safely filtered by RLS'
);

reset role;

select is(
  (
    select display_name
    from public.profiles
    where id = '10000000-0000-0000-0000-000000000002'
  ),
  'Database Test Admin',
  'administrator profile remains unchanged'
);

set local role authenticated;

select throws_ok(
  $test$
    select public.create_order(
      p_order_type => 'TAKE_OUT',
      p_customer_name => 'No Shift Customer'
    )
  $test$,
  'P0001',
  'An active shift is required before creating an order',
  'cashier cannot create an order without an open shift'
);

select lives_ok(
  $test$select public.start_shift(null, 100)$test$,
  'cashier can start a shift'
);

select is(
  (
    select count(*)
    from public.shifts
    where employee_id = '10000000-0000-0000-0000-000000000001'
      and status = 'OPEN'
  ),
  1::bigint,
  'cashier has one open shift'
);

select throws_ok(
  $test$select public.start_shift(null, 100)$test$,
  'P0001',
  'Employee already has an open shift',
  'cashier cannot open a second shift'
);

select lives_ok(
  $test$
    select public.record_shift_cash_movement(
      public.current_open_shift_id(),
      'PAY_IN',
      20,
      'Test cash float addition'
    )
  $test$,
  'cashier can record a pay-in'
);

select lives_ok(
  $test$
    select public.record_shift_cash_movement(
      public.current_open_shift_id(),
      'CASH_DROP',
      10,
      'Test safe drop'
    )
  $test$,
  'cashier can record a cash drop'
);

select is(
  (
    public.get_shift_cash_snapshot(public.current_open_shift_id())
      ->> 'expected_cash'
  )::numeric,
  110::numeric,
  'cash snapshot calculates opening cash plus pay-in minus cash drop'
);

select lives_ok(
  $test$
    select public.end_shift(
      public.current_open_shift_id(),
      110,
      'Database test close'
    )
  $test$,
  'cashier can close their shift'
);

select is(
  (
    select status
    from public.shifts
    where employee_id = '10000000-0000-0000-0000-000000000001'
    order by started_at desc
    limit 1
  ),
  'CLOSED',
  'closed shift has CLOSED status'
);

select is(
  (
    select expected_closing_cash
    from public.shifts
    where employee_id = '10000000-0000-0000-0000-000000000001'
    order by started_at desc
    limit 1
  ),
  110::numeric,
  'closed shift stores the expected cash amount'
);

select is(
  (
    select cash_variance
    from public.shifts
    where employee_id = '10000000-0000-0000-0000-000000000001'
    order by started_at desc
    limit 1
  ),
  0::numeric,
  'matching closing count produces zero variance'
);

reset role;

select is(
  (
    select count(*)
    from public.audit_logs
    where actor_user_id = '10000000-0000-0000-0000-000000000001'
      and action_code in ('SHIFT_STARTED', 'SHIFT_ENDED')
  ),
  2::bigint,
  'shift start and end are both audited'
);

select * from finish();
rollback;
