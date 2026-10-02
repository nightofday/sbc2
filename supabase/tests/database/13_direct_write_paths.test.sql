begin;

create extension if not exists pgtap with schema extensions;

select plan(13);

select is(
  (
    select count(*)
    from pg_policies p
    where p.schemaname = 'public'
      and p.cmd <> 'SELECT'
      and p.tablename in (
        'orders', 'order_items', 'order_item_modifiers', 'order_discounts',
        'order_discount_items', 'payments', 'refunds', 'refund_items',
        'order_actions', 'order_status_history', 'sales_invoices',
        'credit_notes', 'invoice_sequences', 'expenses', 'purchase_orders',
        'purchase_order_items', 'goods_receipts', 'goods_receipt_items',
        'inventory_lots', 'stock_movements', 'stock_counts',
        'stock_count_items', 'stock_out_transactions', 'stock_out_items',
        'supplier_bills', 'supplier_bill_payments', 'shifts',
        'shift_cash_movements', 'audit_logs', 'client_requests'
      )
  ),
  0::bigint,
  'no transactional table has a client write policy'
);

select is(
  (
    select count(*)
    from unnest(array[
      'orders', 'order_items', 'payments', 'refunds', 'refund_items',
      'sales_invoices', 'credit_notes', 'invoice_sequences', 'expenses',
      'purchase_orders', 'purchase_order_items', 'goods_receipts',
      'goods_receipt_items', 'inventory_lots', 'stock_movements',
      'stock_counts', 'stock_count_items', 'stock_out_transactions',
      'stock_out_items', 'supplier_bills', 'supplier_bill_payments',
      'shifts', 'shift_cash_movements', 'audit_logs'
    ]) as t(name)
    where has_table_privilege('authenticated', 'public.' || t.name, 'INSERT')
       or has_table_privilege('authenticated', 'public.' || t.name, 'UPDATE')
       or has_table_privilege('authenticated', 'public.' || t.name, 'DELETE')
  ),
  0::bigint,
  'clients hold no write privilege on transactional tables'
);

select is(
  (
    select count(*)
    from unnest(array[
      'menu_categories', 'menu_items', 'menu_variants', 'modifier_groups',
      'modifiers', 'discount_types', 'inventory_categories',
      'inventory_items', 'units_of_measure', 'suppliers', 'supplier_items',
      'expense_categories', 'payment_methods', 'tax_rates', 'devices',
      'system_settings', 'roles', 'permissions'
    ]) as t(name)
    where has_table_privilege('authenticated', 'public.' || t.name, 'DELETE')
  ),
  0::bigint,
  'clients cannot delete master data that history refers to'
);

select ok(
  not has_function_privilege(
    'authenticated', 'public.set_updated_at()', 'EXECUTE'
  ),
  'clients cannot execute the updated_at trigger function'
);

insert into auth.users (id, email)
values ('60000000-0000-0000-0000-000000000001', 'writes-db-test@example.com');

delete from public.profiles
where id = '60000000-0000-0000-0000-000000000001';

insert into public.profiles (id, role_id, status, display_name)
values (
  '60000000-0000-0000-0000-000000000001',
  (select id from public.roles where code = 'ADMIN'),
  'ACTIVE',
  'Direct Write Test Admin'
);

set local role authenticated;
set local request.jwt.claim.role = 'authenticated';
set local request.jwt.claim.sub = '60000000-0000-0000-0000-000000000001';

-- The functions still work for the same user.
select lives_ok(
  $test$ select public.create_supplier('Direct Write Test Supplier') $test$,
  'an administrator can still create a supplier through its function'
);

select lives_ok(
  $test$
    select public.create_expense(
      (select id from public.expense_categories where code = 'INGREDIENTS'),
      'Direct write test expense', 100, null, null,
      (
        select id from public.suppliers
        where name = 'Direct Write Test Supplier'
      ),
      'DIRECT-WRITE-EX-1'
    )
  $test$,
  'an administrator can still record an expense through its function'
);

-- The same administrator cannot touch the rows directly.
select throws_ok(
  $test$
    delete from public.expenses
    where reference_number = 'DIRECT-WRITE-EX-1'
  $test$,
  '42501',
  null,
  'a posted expense cannot be deleted directly'
);

select throws_ok(
  $test$
    update public.expenses
    set amount = 1
    where reference_number = 'DIRECT-WRITE-EX-1'
  $test$,
  '42501',
  null,
  'a posted expense cannot be edited directly'
);

select throws_ok(
  $test$ update public.invoice_sequences set next_number = 1 $test$,
  '42501',
  null,
  'the invoice sequence cannot be reset directly'
);

select throws_ok(
  $test$ delete from public.shifts $test$,
  '42501',
  null,
  'shifts cannot be deleted directly'
);

select throws_ok(
  $test$
    delete from public.suppliers
    where name = 'Direct Write Test Supplier'
  $test$,
  '42501',
  null,
  'a supplier cannot be deleted directly'
);

select is(
  (
    select amount
    from public.expenses
    where reference_number = 'DIRECT-WRITE-EX-1'
  ),
  100::numeric(14,2),
  'the expense is unchanged after the rejected attempts'
);

-- The one direct write the app performs is still allowed.
select lives_ok(
  $test$
    update public.suppliers
    set notes = 'Edited directly'
    where name = 'Direct Write Test Supplier'
  $test$,
  'master data can still be edited by an authorised user'
);

select * from finish();

rollback;
