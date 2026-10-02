begin;

create extension if not exists pgtap with schema extensions;

select plan(20);

insert into auth.users (id, email)
values (
  '30000000-0000-0000-0000-000000000001',
  'practical-inventory-test@example.com'
);

delete from public.profiles
where id = '30000000-0000-0000-0000-000000000001';

insert into public.profiles (id, role_id, status, display_name)
values (
  '30000000-0000-0000-0000-000000000001',
  (select id from public.roles where code = 'MANAGER'),
  'ACTIVE',
  'Practical Inventory Test Manager'
);

insert into public.units_of_measure (id, code, name, dimension)
values
  (
    '30000000-0000-0000-0000-000000000010',
    'test_release_pc',
    'Test Release Piece',
    'COUNT'
  ),
  (
    '30000000-0000-0000-0000-000000000011',
    'test_release_box',
    'Test Release Box',
    'COUNT'
  );

insert into public.inventory_categories (id, name)
values (
  '30000000-0000-0000-0000-000000000020',
  'Practical Inventory Test Supplies'
);

insert into public.inventory_items (
  id, sku, name, category_id, base_uom_id, track_inventory,
  track_expiry, allow_negative_stock, reorder_level
)
values
  (
    '30000000-0000-0000-0000-000000000021',
    'TEST-CUPS',
    'Test Cups',
    '30000000-0000-0000-0000-000000000020',
    '30000000-0000-0000-0000-000000000010',
    true, false, false, 10
  ),
  (
    '30000000-0000-0000-0000-000000000022',
    'TEST-CAKE',
    'Test Cake',
    '30000000-0000-0000-0000-000000000020',
    '30000000-0000-0000-0000-000000000010',
    true, true, false, 1
  );

insert into public.inventory_lots (
  id, inventory_item_id, lot_code, received_at, expiration_date,
  received_quantity, remaining_quantity, unit_cost_base
)
values
  (
    '30000000-0000-0000-0000-000000000031',
    '30000000-0000-0000-0000-000000000021',
    'CUPS-100', now(), null, 100, 100, 2
  ),
  (
    '30000000-0000-0000-0000-000000000032',
    '30000000-0000-0000-0000-000000000022',
    'CAKE-EARLY', now() - interval '1 day', current_date + 2,
    2, 2, 80
  ),
  (
    '30000000-0000-0000-0000-000000000033',
    '30000000-0000-0000-0000-000000000022',
    'CAKE-LATER', now(), current_date + 5,
    2, 2, 80
  ),
  (
    '30000000-0000-0000-0000-000000000034',
    '30000000-0000-0000-0000-000000000022',
    'CAKE-EXPIRED', now() - interval '10 days', current_date - 1,
    3, 3, 80
  );

insert into public.stock_movements (
  inventory_item_id, inventory_lot_id, movement_type, quantity_delta,
  unit_cost_base, reference_type, recorded_by
)
values
  (
    '30000000-0000-0000-0000-000000000021',
    '30000000-0000-0000-0000-000000000031',
    'MANUAL_IN', 100, 2, 'DATABASE_TEST',
    '30000000-0000-0000-0000-000000000001'
  ),
  (
    '30000000-0000-0000-0000-000000000022',
    '30000000-0000-0000-0000-000000000032',
    'MANUAL_IN', 2, 80, 'DATABASE_TEST',
    '30000000-0000-0000-0000-000000000001'
  ),
  (
    '30000000-0000-0000-0000-000000000022',
    '30000000-0000-0000-0000-000000000033',
    'MANUAL_IN', 2, 80, 'DATABASE_TEST',
    '30000000-0000-0000-0000-000000000001'
  ),
  (
    '30000000-0000-0000-0000-000000000022',
    '30000000-0000-0000-0000-000000000034',
    'MANUAL_IN', 3, 80, 'DATABASE_TEST',
    '30000000-0000-0000-0000-000000000001'
  );

insert into public.menu_categories (id, name, sort_order)
values (
  '30000000-0000-0000-0000-000000000040',
  'Practical Inventory Test Menu',
  999
);

insert into public.menu_items (id, name, category_id)
values (
  '30000000-0000-0000-0000-000000000041',
  'Test Prepared Drink',
  '30000000-0000-0000-0000-000000000040'
);

insert into public.menu_variants (
  id, menu_item_id, name, price, is_default,
  track_finished_inventory, finished_inventory_item_id
)
values
  (
    '30000000-0000-0000-0000-000000000042',
    '30000000-0000-0000-0000-000000000041',
    'Regular', 100, true, false, null
  ),
  (
    '30000000-0000-0000-0000-000000000043',
    '30000000-0000-0000-0000-000000000041',
    'Packaged Cake', 120, false, true,
    '30000000-0000-0000-0000-000000000022'
  );

set local role authenticated;
set local request.jwt.claim.role = 'authenticated';
set local request.jwt.claim.sub = '30000000-0000-0000-0000-000000000001';

select lives_ok(
  $test$
    select public.create_and_post_stock_out(
      'Counter opening supplies',
      jsonb_build_array(
        jsonb_build_object(
          'inventory_item_id', '30000000-0000-0000-0000-000000000021',
          'issue_uom_id', '30000000-0000-0000-0000-000000000011',
          'issue_quantity', 1,
          'base_quantity_per_issue_unit', 50
        ),
        jsonb_build_object(
          'inventory_item_id', '30000000-0000-0000-0000-000000000022',
          'issue_uom_id', '30000000-0000-0000-0000-000000000010',
          'issue_quantity', 1,
          'base_quantity_per_issue_unit', 1
        )
      ),
      'REQ-TEST-001'
    )
  $test$,
  'one stock-out transaction accepts multiple supply lines'
);

select is(
  (select count(*) from public.stock_out_items),
  2::bigint,
  'the posted stock-out contains two item rows'
);

select is(
  (
    select remaining_quantity from public.inventory_lots
    where id = '30000000-0000-0000-0000-000000000031'
  ),
  50::numeric,
  'one box of fifty cups converts to fifty base pieces'
);

select is(
  (
    select remaining_quantity from public.inventory_lots
    where id = '30000000-0000-0000-0000-000000000032'
  ),
  1::numeric,
  'the earliest-expiring cake lot is released first'
);

select is(
  (
    select remaining_quantity from public.inventory_lots
    where id = '30000000-0000-0000-0000-000000000033'
  ),
  2::numeric,
  'the later cake lot remains untouched'
);

select is(
  (
    select current_quantity
    from public.v_inventory_stock
    where inventory_item_id = '30000000-0000-0000-0000-000000000022'
  ),
  6::numeric,
  'on-hand stock still includes an expired lot until disposal'
);

select is(
  (
    select usable_quantity
    from public.v_inventory_stock
    where inventory_item_id = '30000000-0000-0000-0000-000000000022'
  ),
  3::numeric,
  'usable stock excludes the expired cake lot'
);

select is(
  (
    select expired_quantity
    from public.v_inventory_stock
    where inventory_item_id = '30000000-0000-0000-0000-000000000022'
  ),
  3::numeric,
  'expired stock is reported separately'
);

select is(
  (
    select next_expiration_date
    from public.v_inventory_catalog
    where inventory_item_id = '30000000-0000-0000-0000-000000000022'
  ),
  current_date + 2,
  'the inventory catalog reports the next usable expiration date'
);

select is(
  (
    select available_quantity
    from public.v_pos_menu
    where variant_id = '30000000-0000-0000-0000-000000000043'
  ),
  3::numeric,
  'POS availability uses usable rather than total on-hand stock'
);

reset role;

select lives_ok(
  $test$
    select public.consume_inventory_fefo(
      '30000000-0000-0000-0000-000000000022',
      1,
      null,
      null,
      '30000000-0000-0000-0000-000000000001'
    )
  $test$,
  'sale consumption can use the remaining unexpired cake stock'
);

select is(
  (
    select remaining_quantity
    from public.inventory_lots
    where id = '30000000-0000-0000-0000-000000000034'
  ),
  3::numeric,
  'sale consumption leaves the expired lot untouched'
);

select is(
  (
    select usable_quantity
    from public.v_inventory_stock
    where inventory_item_id = '30000000-0000-0000-0000-000000000022'
  ),
  2::numeric,
  'usable availability decreases after FEFO sale consumption'
);

set local role authenticated;
set local request.jwt.claim.role = 'authenticated';
set local request.jwt.claim.sub = '30000000-0000-0000-0000-000000000001';

select is(
  (
    select sum(quantity_delta)
    from public.stock_movements
    where reference_type = 'STOCK_OUT'
  ),
  (-51)::numeric,
  'the stock ledger records the full multi-item release'
);

select is(
  (
    select count(*)
    from public.stock_movements
    where reference_type = 'STOCK_OUT'
      and stock_out_item_id is not null
  ),
  2::bigint,
  'each movement links back to its stock-out item row'
);

select is(
  (
    select count(*) from public.audit_logs
    where action_code = 'STOCK_OUT_POSTED'
      and actor_user_id = '30000000-0000-0000-0000-000000000001'
  ),
  1::bigint,
  'posting the release writes an audit event'
);

select throws_ok(
  $test$
    select public.create_and_post_stock_out(
      'Impossible release',
      jsonb_build_array(
        jsonb_build_object(
          'inventory_item_id', '30000000-0000-0000-0000-000000000021',
          'issue_uom_id', '30000000-0000-0000-0000-000000000011',
          'issue_quantity', 2,
          'base_quantity_per_issue_unit', 50
        )
      )
    )
  $test$,
  'P0001',
  'Insufficient usable stock for item Test Cups',
  'a release above usable stock is rejected'
);

select is(
  (select count(*) from public.stock_out_transactions),
  1::bigint,
  'a rejected release leaves no partial transaction'
);

select throws_ok(
  $test$
    select public.update_menu_variant(
      '30000000-0000-0000-0000-000000000042',
      'Test Prepared Drink',
      '30000000-0000-0000-0000-000000000040',
      'Regular',
      'TEST-PREPARED-REGULAR',
      100,
      true,
      'RECIPE',
      null,
      jsonb_build_array(
        jsonb_build_object(
          'inventory_item_id', '30000000-0000-0000-0000-000000000021',
          'quantity_base_uom', 1
        )
      )
    )
  $test$,
  'P0001',
  'Recipe ingredient tracking is outside the approved system scope',
  'recipe-based menu inventory can no longer be configured'
);

select throws_ok(
  $test$
    insert into public.variant_recipe_components(
      menu_variant_id, inventory_item_id, quantity_base_uom
    )
    values (
      '30000000-0000-0000-0000-000000000042',
      '30000000-0000-0000-0000-000000000021',
      1
    )
  $test$,
  '42501',
  null,
  'direct recipe component writes are not allowed'
);

select * from finish();
rollback;
