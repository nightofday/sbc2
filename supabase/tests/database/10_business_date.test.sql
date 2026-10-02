begin;

create extension if not exists pgtap with schema extensions;

select plan(9);

select is(
  public.business_today(),
  (now() at time zone 'Asia/Manila')::date,
  'the business date follows Asia/Manila, not the server date'
);

select ok(
  not has_function_privilege('anon', 'public.business_today()', 'EXECUTE'),
  'anonymous users cannot call business_today'
);

select ok(
  has_function_privilege(
    'authenticated', 'public.business_today()', 'EXECUTE'
  ),
  'authenticated users can call business_today through invoker views'
);

select is(
  (
    select count(*)::integer
    from pg_proc p
    where p.pronamespace = 'public'::regnamespace
      and p.prosrc ~* '\mcurrent_date\M'
  ),
  0,
  'no public function reads the UTC server date'
);

select is(
  (
    select count(*)::integer
    from pg_views v
    where v.schemaname = 'public'
      and v.definition ~* '\mcurrent_date\M'
  ),
  0,
  'no public view reads the UTC server date'
);

select is(
  (
    select column_default
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'expenses'
      and column_name = 'expense_date'
  ),
  'business_today()',
  'new expenses default to the business date'
);

select is(
  (
    select column_default
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'supplier_bills'
      and column_name = 'invoice_date'
  ),
  'business_today()',
  'new supplier bills default to the business date'
);

insert into public.inventory_items (id, name, base_uom_id, track_expiry)
values (
  '30000000-0000-0000-0000-000000000001',
  'Business Date Test Item',
  (select id from public.units_of_measure where code = 'pc'),
  true
);

insert into public.inventory_lots (
  inventory_item_id, lot_code, expiration_date,
  received_quantity, remaining_quantity
)
values
  (
    '30000000-0000-0000-0000-000000000001', 'EXPIRES-TODAY',
    public.business_today(), 5, 5
  ),
  (
    '30000000-0000-0000-0000-000000000001', 'EXPIRED-YESTERDAY',
    public.business_today() - 1, 3, 3
  );

select is(
  (
    select usable_quantity
    from public.v_inventory_stock
    where inventory_item_id = '30000000-0000-0000-0000-000000000001'
  ),
  5::numeric(14,4),
  'a lot expiring on the business date is still usable'
);

select is(
  (
    select expired_quantity
    from public.v_inventory_stock
    where inventory_item_id = '30000000-0000-0000-0000-000000000001'
  ),
  3::numeric(14,4),
  'a lot that expired before the business date is not usable'
);

select * from finish();

rollback;
