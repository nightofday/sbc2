begin;

create extension if not exists pgtap with schema extensions;

select plan(13);

insert into auth.users (id, email)
values
  (
    '60000000-0000-0000-0000-000000000001',
    'phase-six-manager@example.com'
  ),
  (
    '60000000-0000-0000-0000-000000000002',
    'phase-six-cashier@example.com'
  );

delete from public.profiles
where id in (
  '60000000-0000-0000-0000-000000000001',
  '60000000-0000-0000-0000-000000000002'
);

insert into public.profiles (id, role_id, status, display_name)
values
  (
    '60000000-0000-0000-0000-000000000001',
    (select id from public.roles where code = 'MANAGER'),
    'ACTIVE',
    'Phase Six Manager'
  ),
  (
    '60000000-0000-0000-0000-000000000002',
    (select id from public.roles where code = 'CASHIER'),
    'ACTIVE',
    'Phase Six Cashier'
  );

insert into public.menu_categories (id, name, sort_order)
values (
  '60000000-0000-0000-0000-000000000010',
  'Phase Six Prepared Items',
  998
);

insert into public.menu_items (id, name, category_id)
values (
  '60000000-0000-0000-0000-000000000011',
  'Phase Six Prepared Bowl',
  '60000000-0000-0000-0000-000000000010'
);

insert into public.menu_variants (
  id, menu_item_id, sku, name, price, is_default,
  track_finished_inventory, finished_inventory_item_id
)
values (
  '60000000-0000-0000-0000-000000000012',
  '60000000-0000-0000-0000-000000000011',
  'PHASE6-PREPARED',
  'Regular',
  125,
  true,
  false,
  null
);

insert into public.suppliers (id, supplier_code, name)
values (
  '60000000-0000-0000-0000-000000000020',
  'PHASE6-GROCERY',
  'Phase Six Grocery'
);

set local role authenticated;
set local request.jwt.claim.role = 'authenticated';
set local request.jwt.claim.sub = '60000000-0000-0000-0000-000000000001';

select is(
  (
    select inventory_tracking_mode
    from public.v_pos_menu
    where variant_id = '60000000-0000-0000-0000-000000000012'
  ),
  'UNTRACKED',
  'prepared-to-order menu variants use only the approved untracked mode'
);

select is(
  (
    select available_quantity
    from public.v_pos_menu
    where variant_id = '60000000-0000-0000-0000-000000000012'
  ),
  null::numeric,
  'prepared-to-order variants do not expose recipe-derived availability'
);

select throws_ok(
  $test$
    select public.create_expense(
      (select id from public.expense_categories where code = 'INGREDIENTS'),
      'Milk and other untracked grocery items',
      850,
      current_date,
      null,
      null,
      'GROCERY-001',
      null
    )
  $test$,
  'P0001',
  'A valid supplier or grocery is required',
  'a posted expense requires a supplier or grocery'
);

select throws_ok(
  $test$
    select public.create_expense(
      (select id from public.expense_categories where code = 'INGREDIENTS'),
      'Milk and other untracked grocery items',
      850,
      current_date,
      null,
      '60000000-0000-0000-0000-000000000020',
      null,
      null
    )
  $test$,
  'P0001',
  'Receipt or reference number is required',
  'a posted expense requires a receipt or reference number'
);

select lives_ok(
  $test$
    select public.create_expense(
      (select id from public.expense_categories where code = 'INGREDIENTS'),
      'Milk and other untracked grocery items',
      850,
      current_date,
      null,
      '60000000-0000-0000-0000-000000000020',
      'GROCERY-001',
      'Weekly grocery purchase'
    )
  $test$,
  'management can record a traceable grocery expense'
);

select is(
  (
    select expense_type
    from public.expenses
    where supplier_id = '60000000-0000-0000-0000-000000000020'
      and reference_number = 'GROCERY-001'
  ),
  'NON_INVENTORY_PURCHASE',
  'ingredient and grocery expenses are classified as non-inventory purchases'
);

select is(
  (
    select reference_number
    from public.expenses
    where supplier_id = '60000000-0000-0000-0000-000000000020'
      and reference_number = 'GROCERY-001'
  ),
  'GROCERY-001',
  'the external receipt number remains attached to the expense'
);

select is(
  (
    select recorded_by
    from public.expenses
    where supplier_id = '60000000-0000-0000-0000-000000000020'
      and reference_number = 'GROCERY-001'
  ),
  '60000000-0000-0000-0000-000000000001'::uuid,
  'the expense records the responsible user'
);

select throws_ok(
  $test$
    select public.create_expense(
      (select id from public.expense_categories where code = 'INGREDIENTS'),
      'Duplicate grocery receipt',
      100,
      current_date,
      null,
      '60000000-0000-0000-0000-000000000020',
      'GROCERY-001',
      null
    )
  $test$,
  'P0001',
  'This supplier receipt or reference is already recorded',
  'the same supplier receipt cannot be posted twice'
);

select throws_ok(
  $test$
    select public.update_expense(
      (
        select id from public.expenses
        where supplier_id = '60000000-0000-0000-0000-000000000020'
          and reference_number = 'GROCERY-001'
      ),
      (select id from public.expense_categories where code = 'INGREDIENTS'),
      'Invalid zero-value edit',
      0,
      current_date,
      null,
      '60000000-0000-0000-0000-000000000020',
      'GROCERY-001',
      null
    )
  $test$,
  'P0001',
  'Amount must be greater than zero',
  'expense edits repeat the amount validation'
);

select lives_ok(
  $test$
    select public.update_expense(
      (
        select id from public.expenses
        where supplier_id = '60000000-0000-0000-0000-000000000020'
          and reference_number = 'GROCERY-001'
      ),
      (select id from public.expense_categories where code = 'OTHER'),
      'Traceable operating expense',
      900,
      current_date,
      null,
      '60000000-0000-0000-0000-000000000020',
      'GROCERY-001',
      'Reclassified after review'
    )
  $test$,
  'management can update a traceable expense'
);

select is(
  (
    select expense_type
    from public.expenses
    where supplier_id = '60000000-0000-0000-0000-000000000020'
      and reference_number = 'GROCERY-001'
  ),
  'OPERATING',
  'non-grocery categories are classified as operating expenses'
);

set local request.jwt.claim.sub = '60000000-0000-0000-0000-000000000002';

select throws_ok(
  $test$
    select public.create_expense(
      (select id from public.expense_categories where code = 'OTHER'),
      'Unauthorized expense',
      100,
      current_date,
      null,
      '60000000-0000-0000-0000-000000000020',
      'CASHIER-001',
      null
    )
  $test$,
  'P0001',
  'Permission denied',
  'cashiers cannot manage expenses'
);

select * from finish();
rollback;
