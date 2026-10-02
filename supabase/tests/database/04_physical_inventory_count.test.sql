begin;

create extension if not exists pgtap with schema extensions;

select plan(12);

insert into auth.users (id, email)
values
  (
    '40000000-0000-0000-0000-000000000001',
    'inventory-count-manager@example.com'
  ),
  (
    '40000000-0000-0000-0000-000000000002',
    'inventory-count-cashier@example.com'
  );

delete from public.profiles
where id in (
  '40000000-0000-0000-0000-000000000001',
  '40000000-0000-0000-0000-000000000002'
);

insert into public.profiles (id, role_id, status, display_name)
values
  (
    '40000000-0000-0000-0000-000000000001',
    (select id from public.roles where code = 'MANAGER'),
    'ACTIVE',
    'Inventory Count Manager'
  ),
  (
    '40000000-0000-0000-0000-000000000002',
    (select id from public.roles where code = 'CASHIER'),
    'ACTIVE',
    'Inventory Count Cashier'
  );

insert into public.units_of_measure (id, code, name, dimension)
values (
  '40000000-0000-0000-0000-000000000010',
  'test_count_pc',
  'Test Count Piece',
  'COUNT'
);

insert into public.inventory_categories (id, name)
values (
  '40000000-0000-0000-0000-000000000020',
  'Physical Count Test Items'
);

insert into public.inventory_items (
  id, sku, name, category_id, base_uom_id, track_inventory,
  track_expiry, allow_negative_stock, reorder_level
)
values
  (
    '40000000-0000-0000-0000-000000000021',
    'COUNT-CUPS',
    'Count Test Cups',
    '40000000-0000-0000-0000-000000000020',
    '40000000-0000-0000-0000-000000000010',
    true, false, false, 10
  ),
  (
    '40000000-0000-0000-0000-000000000022',
    'COUNT-CAKES',
    'Count Test Cakes',
    '40000000-0000-0000-0000-000000000020',
    '40000000-0000-0000-0000-000000000010',
    true, true, false, 1
  );

insert into public.inventory_lots (
  id, inventory_item_id, lot_code, received_at, expiration_date,
  received_quantity, remaining_quantity, unit_cost_base
)
values
  (
    '40000000-0000-0000-0000-000000000031',
    '40000000-0000-0000-0000-000000000021',
    'COUNT-CUPS-EARLY', now() - interval '2 days', null,
    60, 60, 2
  ),
  (
    '40000000-0000-0000-0000-000000000032',
    '40000000-0000-0000-0000-000000000021',
    'COUNT-CUPS-LATER', now() - interval '1 day', null,
    40, 40, 2
  ),
  (
    '40000000-0000-0000-0000-000000000033',
    '40000000-0000-0000-0000-000000000022',
    'COUNT-CAKES-OPENING', now(), current_date + 3,
    4, 4, 80
  );

set local role authenticated;
set local request.jwt.claim.role = 'authenticated';
set local request.jwt.claim.sub = '40000000-0000-0000-0000-000000000001';

select lives_ok(
  $test$
    select public.create_and_post_stock_count(
      jsonb_build_array(
        jsonb_build_object(
          'inventory_item_id', '40000000-0000-0000-0000-000000000021',
          'counted_quantity', 70,
          'notes', 'Thirty cups missing'
        ),
        jsonb_build_object(
          'inventory_item_id', '40000000-0000-0000-0000-000000000022',
          'counted_quantity', 6,
          'adjustment_expiration_date', (current_date + 5)::text,
          'unit_cost_base', 80,
          'notes', 'Two cakes found'
        )
      ),
      'End-of-day test count'
    )
  $test$,
  'one physical count accepts multiple inventory items'
);

select is(
  (
    select status
    from public.stock_counts
    where counted_by = '40000000-0000-0000-0000-000000000001'
    order by created_at desc
    limit 1
  ),
  'POSTED',
  'the physical count is posted atomically'
);

select is(
  (
    select count(*)
    from public.stock_count_items
    where stock_count_id = (
      select id
      from public.stock_counts
      where counted_by = '40000000-0000-0000-0000-000000000001'
      order by created_at desc
      limit 1
    )
  ),
  2::bigint,
  'the count stores both item lines'
);

select is(
  (
    select variance_quantity
    from public.stock_count_items
    where inventory_item_id = '40000000-0000-0000-0000-000000000021'
  ),
  (-30)::numeric,
  'the negative variance is calculated from system stock'
);

select is(
  (
    select remaining_quantity
    from public.inventory_lots
    where id = '40000000-0000-0000-0000-000000000031'
  ),
  30::numeric,
  'the negative variance is deducted from the earliest lot first'
);

select is(
  (
    select remaining_quantity
    from public.inventory_lots
    where id = '40000000-0000-0000-0000-000000000032'
  ),
  40::numeric,
  'the later lot remains untouched when the early lot is sufficient'
);

select is(
  (
    select remaining_quantity
    from public.inventory_lots il
    where il.id = (
      select sm.inventory_lot_id
      from public.stock_movements sm
      where sm.reference_type = 'STOCK_COUNT'
        and sm.inventory_item_id = '40000000-0000-0000-0000-000000000022'
        and sm.quantity_delta > 0
      limit 1
    )
  ),
  2::numeric,
  'a positive variance creates a new count lot'
);

select is(
  (
    select expiration_date
    from public.inventory_lots il
    where il.id = (
      select sm.inventory_lot_id
      from public.stock_movements sm
      where sm.reference_type = 'STOCK_COUNT'
        and sm.inventory_item_id = '40000000-0000-0000-0000-000000000022'
        and sm.quantity_delta > 0
      limit 1
    )
  ),
  current_date + 5,
  'the positive expiry-tracked variance keeps its expiration date'
);

select is(
  (
    select count(*)
    from public.stock_movements
    where reference_type = 'STOCK_COUNT'
      and movement_type = 'STOCK_COUNT_ADJUSTMENT'
  ),
  2::bigint,
  'count variances are recorded in the immutable stock ledger'
);

select matches(
  (
    select source_document_number
    from public.v_inventory_movement_history
    where reference_type = 'STOCK_COUNT'
    limit 1
  ),
  '^IC-[0-9]+$',
  'count movements expose a readable source document number'
);

select throws_ok(
  $test$
    select public.create_and_post_stock_count(
      jsonb_build_array(
        jsonb_build_object(
          'inventory_item_id', '40000000-0000-0000-0000-000000000022',
          'counted_quantity', 7
        )
      ),
      'Missing expiry test'
    )
  $test$,
  'P0001',
  'Expiration date is required for positive variance on item Count Test Cakes',
  'positive variance on an expiry-tracked item requires an expiration date'
);

set local request.jwt.claim.sub = '40000000-0000-0000-0000-000000000002';

select throws_ok(
  $test$
    select public.create_and_post_stock_count(
      jsonb_build_array(
        jsonb_build_object(
          'inventory_item_id', '40000000-0000-0000-0000-000000000021',
          'counted_quantity', 70
        )
      ),
      'Unauthorized count'
    )
  $test$,
  'P0001',
  'Permission denied',
  'cashiers cannot post physical inventory counts'
);

select * from finish();
rollback;
