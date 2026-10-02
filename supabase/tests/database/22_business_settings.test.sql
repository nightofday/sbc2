begin;

create extension if not exists pgtap with schema extensions;

select plan(12);

insert into auth.users (id, email)
values
  ('f0000000-0000-0000-0000-000000000001', 'settings-admin-db-test@example.com'),
  ('f0000000-0000-0000-0000-000000000002', 'settings-cashier-db-test@example.com');

delete from public.profiles
where id in (
  'f0000000-0000-0000-0000-000000000001',
  'f0000000-0000-0000-0000-000000000002'
);

insert into public.profiles (id, role_id, status, display_name)
values
  (
    'f0000000-0000-0000-0000-000000000001',
    (select id from public.roles where code = 'ADMIN'),
    'ACTIVE',
    'Settings Test Admin'
  ),
  (
    'f0000000-0000-0000-0000-000000000002',
    (select id from public.roles where code = 'CASHIER'),
    'ACTIVE',
    'Settings Test Cashier'
  );

set local role authenticated;
set local request.jwt.claim.role = 'authenticated';
set local request.jwt.claim.sub = 'f0000000-0000-0000-0000-000000000002';

select throws_ok(
  $test$ select public.update_business_profile('Cashier Café') $test$,
  'P0001',
  'Permission denied',
  'a cashier cannot change the business details'
);

select throws_ok(
  $test$ select public.update_shift_cash_rules(true, true) $test$,
  'P0001',
  'Permission denied',
  'a cashier cannot change the cash rules'
);

select ok(
  (select trade_name is not null from public.business_profile limit 1),
  'a cashier can read the business name for receipts'
);

select throws_ok(
  $test$ update public.business_profile set trade_name = 'Direct Edit' $test$,
  '42501',
  null,
  'the business details cannot be edited directly'
);

set local request.jwt.claim.sub = 'f0000000-0000-0000-0000-000000000001';

select throws_ok(
  $test$ update public.system_settings set value = 'true'::jsonb $test$,
  '42501',
  null,
  'settings cannot be edited directly, even by an administrator'
);

select throws_ok(
  $test$ select public.update_business_profile('   ') $test$,
  'P0001',
  'The business name is required',
  'the business name cannot be blank'
);

select throws_ok(
  $test$ select public.update_business_profile('Test Café', p_email := 'not-an-email') $test$,
  'P0001',
  'The email address is not valid',
  'a malformed email is refused'
);

select lives_ok(
  $test$
    select public.update_business_profile(
      '  Settings Test Café  ', 'Settings Test Foods Inc.', '123-456-789-000',
      '12 Test Street', 'Davao City', 'Davao del Sur', '8000',
      '0917 000 0000', 'hello@example.com'
    )
  $test$,
  'management saves the business details'
);

select is(
  (select trade_name || ' / ' || tin || ' / ' || address_line from public.business_profile limit 1),
  'Settings Test Café / 123-456-789-000 / 12 Test Street',
  'the details are stored trimmed'
);

select ok(
  exists (
    select 1 from public.audit_logs
    where action_code = 'BUSINESS_PROFILE_UPDATED'
      and actor_user_id = 'f0000000-0000-0000-0000-000000000001'
      and new_data ->> 'trade_name' = 'Settings Test Café'
  ),
  'the change is in the audit log'
);

select lives_ok(
  $test$ select public.update_shift_cash_rules(true, false) $test$,
  'management requires an opening cash count'
);

select throws_ok(
  $test$ select public.start_shift(null, null) $test$,
  'P0001',
  'Opening cash is required',
  'a shift then cannot open without its cash count'
);

select * from finish();
rollback;
