begin;

create extension if not exists pgtap with schema extensions;

select plan(19);

insert into auth.users (id, email)
values
  ('d0000000-0000-0000-0000-000000000001', 'audit-admin-db-test@example.com'),
  ('d0000000-0000-0000-0000-000000000002', 'audit-cashier-db-test@example.com'),
  ('d0000000-0000-0000-0000-000000000003', 'audit-newhire-db-test@example.com');

-- Accounts ------------------------------------------------------------------

select is(
  (
    select status from public.profiles
    where id = 'd0000000-0000-0000-0000-000000000003'
  ),
  'PENDING',
  'a new sign-in account starts without access'
);

select lives_ok(
  $test$
    update public.profiles
    set role_id = (select id from public.roles where code = 'ADMIN'),
        status = 'ACTIVE',
        display_name = 'Audit Test Admin'
    where id = 'd0000000-0000-0000-0000-000000000001';
    update public.profiles
    set role_id = (select id from public.roles where code = 'CASHIER'),
        status = 'ACTIVE',
        display_name = 'Audit Test Cashier'
    where id = 'd0000000-0000-0000-0000-000000000002';
  $test$,
  'the database owner can assign the first roles directly'
);

select throws_ok(
  $test$ select public.bootstrap_first_admin('audit-newhire-db-test@example.com') $test$,
  'P0001',
  'An active administrator already exists. Use User Management in the app.',
  'the bootstrap refuses once an administrator exists'
);

update auth.users
set email = 'audit-cashier-renamed-db-test@example.com'
where id = 'd0000000-0000-0000-0000-000000000002';

select is(
  (
    select email from public.profiles
    where id = 'd0000000-0000-0000-0000-000000000002'
  ),
  'audit-cashier-renamed-db-test@example.com',
  'the profile email follows a changed sign-in email'
);

select is(
  (
    select count(*)
    from public.profiles p
    join auth.users u on u.id = p.id
    where p.email is distinct from u.email
  ),
  0::bigint,
  'no profile email differs from its sign-in email'
);

-- Only one administrator is left active for the lock-out checks.
update public.profiles
set status = 'INACTIVE'
where role_id = (select id from public.roles where code = 'ADMIN')
  and id <> 'd0000000-0000-0000-0000-000000000001';

set local role authenticated;
set local request.jwt.claim.role = 'authenticated';
set local request.jwt.claim.sub = 'd0000000-0000-0000-0000-000000000002';

-- Whether the attempt is refused or simply matches no row it may change,
-- the role must be untouched afterwards.
do $$
begin
  update public.profiles
  set role_id = (select id from public.roles where code = 'ADMIN')
  where id = 'd0000000-0000-0000-0000-000000000002';
exception when others then
  null;
end;
$$;

select is(
  (
    select r.code
    from public.profiles p
    join public.roles r on r.id = p.role_id
    where p.id = 'd0000000-0000-0000-0000-000000000002'
  ),
  'CASHIER',
  'a cashier cannot make themselves an administrator'
);

select throws_ok(
  $test$ select public.bootstrap_first_admin('audit-cashier-renamed-db-test@example.com') $test$,
  '42501',
  null,
  'the app cannot call the bootstrap function'
);

select throws_ok(
  $test$ select public.get_audit_log(public.business_today(), public.business_today()) $test$,
  'P0001',
  'Permission denied',
  'a cashier cannot read the audit log'
);

set local request.jwt.claim.sub = 'd0000000-0000-0000-0000-000000000001';

select throws_ok(
  $test$
    select public.update_employee_profile(
      'd0000000-0000-0000-0000-000000000001',
      'Audit Test Admin',
      'ACTIVE',
      (select id from public.roles where code = 'MANAGER')
    )
  $test$,
  'P0001',
  'This is the only active administrator. Make another account an administrator first.',
  'the only administrator cannot give up the role'
);

select lives_ok(
  $test$
    select public.update_employee_profile(
      'd0000000-0000-0000-0000-000000000003',
      'Audit Test Second Admin',
      'ACTIVE',
      (select id from public.roles where code = 'ADMIN')
    );
    select public.update_employee_profile(
      'd0000000-0000-0000-0000-000000000001',
      'Audit Test Admin',
      'ACTIVE',
      (select id from public.roles where code = 'MANAGER')
    );
  $test$,
  'with a second administrator in place the first can step down'
);

select is(
  (
    select new_data ->> 'role_id'
    from public.audit_logs
    where action_code = 'PROFILES_UPDATED'
      and entity_id = 'd0000000-0000-0000-0000-000000000001'
      and actor_user_id = 'd0000000-0000-0000-0000-000000000001'
    order by created_at desc
    limit 1
  ),
  (select id::text from public.roles where code = 'MANAGER'),
  'the role change is recorded with who made it'
);

-- Audit of master data --------------------------------------------------------

select lives_ok(
  $test$
    select public.create_menu_item_with_variant(
      'Audit Test Drink',
      (select id from public.menu_categories where name = 'Coffee'),
      'Regular', 'AUDIT-TEST-SKU', 100, 'UNTRACKED', null
    );
  $test$,
  'a product is created'
);

select is(
  (
    select count(*) from public.audit_logs
    where action_code = 'MENU_VARIANTS_CREATED'
      and new_data ->> 'sku' = 'AUDIT-TEST-SKU'
  ),
  1::bigint,
  'creating the product is recorded'
);

select lives_ok(
  $test$
    select public.update_menu_variant(
      (select id from public.menu_variants where sku = 'AUDIT-TEST-SKU'),
      'Audit Test Drink',
      (select id from public.menu_categories where name = 'Coffee'),
      'Regular', 'AUDIT-TEST-SKU', 120, true, 'UNTRACKED', null
    )
  $test$,
  'its price is changed'
);

select is(
  (
    select (old_data ->> 'price')::numeric || ' -> ' || (new_data ->> 'price')::numeric
    from public.audit_logs
    where action_code = 'MENU_VARIANTS_UPDATED'
      and entity_id = (
        select id::text from public.menu_variants where sku = 'AUDIT-TEST-SKU'
      )
  ),
  '100.00 -> 120.00',
  'the price change is recorded with the price before and after'
);

select is(
  (
    select array_agg(key order by key)
    from public.audit_logs a, jsonb_object_keys(a.old_data) as key
    where a.action_code = 'MENU_VARIANTS_UPDATED'
      and a.entity_id = (
        select id::text from public.menu_variants where sku = 'AUDIT-TEST-SKU'
      )
  ),
  array['price'],
  'only the field that changed is kept'
);

select lives_ok(
  $test$
    select public.update_menu_variant(
      (select id from public.menu_variants where sku = 'AUDIT-TEST-SKU'),
      'Audit Test Drink',
      (select id from public.menu_categories where name = 'Coffee'),
      'Regular', 'AUDIT-TEST-SKU', 120, true, 'UNTRACKED', null
    )
  $test$,
  'saving again with nothing changed works'
);

select is(
  (
    select count(*) from public.audit_logs
    where action_code = 'MENU_VARIANTS_UPDATED'
      and entity_id = (
        select id::text from public.menu_variants where sku = 'AUDIT-TEST-SKU'
      )
  ),
  1::bigint,
  'a save that changes nothing is not recorded'
);

select ok(
  (
    select count(*)
    from jsonb_array_elements(
      public.get_audit_log(
        public.business_today(), public.business_today(), 'AUDIT-TEST-SKU'
      )
    ) entry
    where entry.value ->> 'actor_name' = 'Audit Test Admin'
      and entry.value ->> 'label' = 'Regular'
  ) >= 1,
  'management can search the audit log and see who made each change'
);

select * from finish();
rollback;
