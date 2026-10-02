begin;

create extension if not exists pgtap with schema extensions;

select plan(35);

insert into auth.users (id, email)
values (
  '20000000-0000-0000-0000-000000000001',
  'manager-db-test@example.com'
);

delete from public.profiles
where id = '20000000-0000-0000-0000-000000000001';

insert into public.profiles (id, role_id, status, display_name)
values (
  '20000000-0000-0000-0000-000000000001',
  (select id from public.roles where code = 'MANAGER'),
  'ACTIVE',
  'Database Test Manager'
);

insert into public.units_of_measure (id, code, name, dimension)
values (
  '20000000-0000-0000-0000-000000000010',
  'test_pc',
  'Test Piece',
  'COUNT'
);

insert into public.inventory_categories (id, name)
values (
  '20000000-0000-0000-0000-000000000011',
  'Database Test Finished Goods'
);

insert into public.inventory_items (
  id,
  sku,
  name,
  category_id,
  base_uom_id,
  track_inventory,
  track_expiry,
  allow_negative_stock,
  reorder_level
)
values (
  '20000000-0000-0000-0000-000000000012',
  'DB-TEST-ITEM',
  'Database Test Bottled Drink',
  '20000000-0000-0000-0000-000000000011',
  '20000000-0000-0000-0000-000000000010',
  true,
  false,
  false,
  2
);

insert into public.inventory_lots (
  id,
  inventory_item_id,
  lot_code,
  received_at,
  expiration_date,
  received_quantity,
  remaining_quantity,
  unit_cost_base
)
values
  (
    '20000000-0000-0000-0000-000000000013',
    '20000000-0000-0000-0000-000000000012',
    'DB-TEST-EARLY',
    now() - interval '1 day',
    current_date + 5,
    5,
    5,
    20
  ),
  (
    '20000000-0000-0000-0000-000000000014',
    '20000000-0000-0000-0000-000000000012',
    'DB-TEST-LATE',
    now(),
    current_date + 10,
    5,
    5,
    20
  );

insert into public.stock_movements (
  inventory_item_id,
  inventory_lot_id,
  movement_type,
  quantity_delta,
  unit_cost_base,
  reference_type,
  recorded_by
)
values
  (
    '20000000-0000-0000-0000-000000000012',
    '20000000-0000-0000-0000-000000000013',
    'MANUAL_IN',
    5,
    20,
    'DATABASE_TEST',
    '20000000-0000-0000-0000-000000000001'
  ),
  (
    '20000000-0000-0000-0000-000000000012',
    '20000000-0000-0000-0000-000000000014',
    'MANUAL_IN',
    5,
    20,
    'DATABASE_TEST',
    '20000000-0000-0000-0000-000000000001'
  );

insert into public.menu_categories (id, name, sort_order)
values (
  '20000000-0000-0000-0000-000000000020',
  'Database Test Menu',
  999
);

insert into public.menu_items (id, name, category_id)
values (
  '20000000-0000-0000-0000-000000000021',
  'Database Test Drink',
  '20000000-0000-0000-0000-000000000020'
);

insert into public.menu_variants (
  id,
  menu_item_id,
  sku,
  name,
  price,
  is_default,
  track_finished_inventory,
  finished_inventory_item_id
)
values (
  '20000000-0000-0000-0000-000000000022',
  '20000000-0000-0000-0000-000000000021',
  'DB-TEST-VARIANT',
  'Regular',
  50,
  true,
  true,
  '20000000-0000-0000-0000-000000000012'
);

insert into public.suppliers (id, supplier_code, name)
values (
  '20000000-0000-0000-0000-000000000030',
  'DB-TEST-SUPPLIER',
  'Database Test Supplier'
);

set local role authenticated;
set local request.jwt.claim.role = 'authenticated';
set local request.jwt.claim.sub = '20000000-0000-0000-0000-000000000001';

select lives_ok(
  $test$select public.start_shift(null, 200)$test$,
  'manager can start a POS shift'
);

select lives_ok(
  $test$
    select public.create_order(
      p_order_type => 'TAKE_OUT',
      p_customer_name => 'Database Test Customer'
    )
  $test$,
  'manager can create an order during an open shift'
);

select lives_ok(
  $test$
    select public.add_order_item(
      (
        select id
        from public.orders
        where created_by_user_id = '20000000-0000-0000-0000-000000000001'
          and status = 'OPEN'
        order by created_at desc
        limit 1
      ),
      '20000000-0000-0000-0000-000000000022',
      2
    )
  $test$,
  'server adds the selected menu variant to the order'
);

select is(
  (
    select unit_price
    from public.order_items
    where menu_variant_id = '20000000-0000-0000-0000-000000000022'
    order by created_at desc
    limit 1
  ),
  50::numeric,
  'order item price comes from the database variant price'
);

select is(
  (
    select total_amount
    from public.orders
    where created_by_user_id = '20000000-0000-0000-0000-000000000001'
      and status = 'OPEN'
    order by created_at desc
    limit 1
  ),
  100::numeric,
  'order total is recalculated from trusted line values'
);

select lives_ok(
  $test$
    select public.checkout_order(
      (
        select id
        from public.orders
        where created_by_user_id = '20000000-0000-0000-0000-000000000001'
          and status = 'OPEN'
        order by created_at desc
        limit 1
      ),
      jsonb_build_array(
        jsonb_build_object(
          'payment_method_id',
          (select id from public.payment_methods where code = 'CASH'),
          'amount', 100,
          'amount_tendered', 100,
          'change_amount', 0
        )
      )
    )
  $test$,
  'checkout succeeds with an exact cash payment'
);

select is(
  (
    select status
    from public.orders
    where created_by_user_id = '20000000-0000-0000-0000-000000000001'
    order by created_at desc
    limit 1
  ),
  'COMPLETED',
  'successful checkout completes the order'
);

select is(
  (
    select count(*)
    from public.payments
    where order_id = (
      select id
      from public.orders
      where created_by_user_id = '20000000-0000-0000-0000-000000000001'
      order by created_at desc
      limit 1
    )
      and transaction_type = 'PAYMENT'
      and status = 'COMPLETED'
  ),
  1::bigint,
  'checkout records one completed payment'
);

select is(
  (
    select sum(quantity_delta)
    from public.stock_movements
    where inventory_item_id = '20000000-0000-0000-0000-000000000012'
  ),
  8::numeric,
  'checkout deducts finished-good inventory'
);

select is(
  (
    select remaining_quantity
    from public.inventory_lots
    where id = '20000000-0000-0000-0000-000000000013'
  ),
  3::numeric,
  'FEFO consumes the earliest-expiring lot first'
);

select is(
  (
    select remaining_quantity
    from public.inventory_lots
    where id = '20000000-0000-0000-0000-000000000014'
  ),
  5::numeric,
  'later inventory lot remains untouched'
);

select is(
  (
    select count(*)
    from public.audit_logs
    where action_code = 'ORDER_CHECKOUT'
      and actor_user_id = '20000000-0000-0000-0000-000000000001'
  ),
  1::bigint,
  'checkout writes an audit event'
);

select lives_ok(
  $test$
    select public.process_refund_items(
      (
        select id
        from public.orders
        where created_by_user_id = '20000000-0000-0000-0000-000000000001'
        order by created_at desc
        limit 1
      ),
      jsonb_build_array(
        jsonb_build_object(
          'order_item_id',
          (
            select id
            from public.order_items
            where menu_variant_id = '20000000-0000-0000-0000-000000000022'
            order by created_at desc
            limit 1
          ),
          'quantity', 1
        )
      ),
      'Database test partial refund'
    )
  $test$,
  'manager can process a partial item refund'
);

select is(
  (
    select status
    from public.orders
    where created_by_user_id = '20000000-0000-0000-0000-000000000001'
    order by created_at desc
    limit 1
  ),
  'PARTIALLY_REFUNDED',
  'partial refund changes the order status'
);

select is(
  (
    select total_amount
    from public.refunds
    where requested_by = '20000000-0000-0000-0000-000000000001'
    order by created_at desc
    limit 1
  ),
  50::numeric,
  'refund amount is calculated from the stored sale price'
);

select is(
  (
    select sum(quantity_delta)
    from public.stock_movements
    where inventory_item_id = '20000000-0000-0000-0000-000000000012'
  ),
  8::numeric,
  'refund does not automatically restock inventory'
);

select is(
  (
    select restock_approved
    from public.refund_items
    order by id desc
    limit 1
  ),
  false,
  'refunded item initially requires explicit restock approval'
);

select lives_ok(
  $test$
    select public.approve_refund_item_restock(
      (select id from public.refund_items order by id desc limit 1),
      'Returned sealed product inspected'
    )
  $test$,
  'manager can approve an eligible finished-good restock'
);

select is(
  (
    select sum(quantity_delta)
    from public.stock_movements
    where inventory_item_id = '20000000-0000-0000-0000-000000000012'
  ),
  9::numeric,
  'approved refund restock returns one unit to the ledger'
);

select is(
  (
    select restock_approved
    from public.refund_items
    order by id desc
    limit 1
  ),
  true,
  'refund item records its restock approval'
);

select throws_ok(
  $test$
    select public.approve_refund_item_restock(
      (select id from public.refund_items order by id desc limit 1),
      'Duplicate attempt'
    )
  $test$,
  'P0001',
  'Refund item was already restocked',
  'same refund item cannot be restocked twice'
);

select throws_ok(
  $test$
    select public.process_refund_items(
      (
        select id
        from public.orders
        where created_by_user_id = '20000000-0000-0000-0000-000000000001'
        order by created_at desc
        limit 1
      ),
      jsonb_build_array(
        jsonb_build_object(
          'order_item_id',
          (
            select id
            from public.order_items
            where menu_variant_id = '20000000-0000-0000-0000-000000000022'
            order by created_at desc
            limit 1
          ),
          'quantity', 2
        )
      ),
      'Over-refund attempt'
    )
  $test$,
  'P0001',
  'Refund quantity exceeds remaining refundable quantity',
  'refund cannot exceed the remaining sold quantity'
);

select lives_ok(
  $test$
    select public.create_purchase_order(
      '20000000-0000-0000-0000-000000000030',
      jsonb_build_array(
        jsonb_build_object(
          'inventory_item_id', '20000000-0000-0000-0000-000000000012',
          'purchase_uom_id', '20000000-0000-0000-0000-000000000010',
          'ordered_quantity', 10,
          'base_quantity_per_purchase_unit', 1,
          'unit_cost', 20
        )
      ),
      current_date + 2,
      'Database test purchase order'
    )
  $test$,
  'manager can create a purchase order'
);

select lives_ok(
  $test$
    select public.approve_purchase_order(
      (
        select id
        from public.purchase_orders
        where supplier_id = '20000000-0000-0000-0000-000000000030'
        order by created_at desc
        limit 1
      )
    )
  $test$,
  'manager can approve a draft purchase order'
);

select lives_ok(
  $test$
    select public.create_and_post_goods_receipt(
      '20000000-0000-0000-0000-000000000030',
      jsonb_build_array(
        jsonb_build_object(
          'purchase_order_item_id',
          (
            select id
            from public.purchase_order_items
            where purchase_order_id = (
              select id
              from public.purchase_orders
              where supplier_id = '20000000-0000-0000-0000-000000000030'
              order by created_at desc
              limit 1
            )
            limit 1
          ),
          'inventory_item_id', '20000000-0000-0000-0000-000000000012',
          'purchase_uom_id', '20000000-0000-0000-0000-000000000010',
          'purchase_quantity', 4,
          'base_quantity_per_purchase_unit', 1,
          'unit_cost_purchase_uom', 20,
          'lot_code', 'DB-TEST-RECEIPT-1'
        )
      ),
      (
        select id
        from public.purchase_orders
        where supplier_id = '20000000-0000-0000-0000-000000000030'
        order by created_at desc
        limit 1
      ),
      'DB-TEST-INVOICE-1',
      current_date,
      'First partial receipt',
      false,
      null
    )
  $test$,
  'manager can post a partial goods receipt'
);

select is(
  (
    select status
    from public.purchase_orders
    where supplier_id = '20000000-0000-0000-0000-000000000030'
    order by created_at desc
    limit 1
  ),
  'PARTIALLY_RECEIVED',
  'first receipt changes purchase order to partially received'
);

select is(
  (
    select sum(quantity_delta)
    from public.stock_movements
    where inventory_item_id = '20000000-0000-0000-0000-000000000012'
      and movement_type = 'PURCHASE_RECEIPT'
  ),
  4::numeric,
  'first receipt adds four units to the inventory ledger'
);

select throws_ok(
  $test$
    select public.create_and_post_goods_receipt(
      '20000000-0000-0000-0000-000000000030',
      jsonb_build_array(
        jsonb_build_object(
          'purchase_order_item_id',
          (
            select id
            from public.purchase_order_items
            where purchase_order_id = (
              select id
              from public.purchase_orders
              where supplier_id = '20000000-0000-0000-0000-000000000030'
              order by created_at desc
              limit 1
            )
            limit 1
          ),
          'inventory_item_id', '20000000-0000-0000-0000-000000000012',
          'purchase_uom_id', '20000000-0000-0000-0000-000000000010',
          'purchase_quantity', 7,
          'base_quantity_per_purchase_unit', 1,
          'unit_cost_purchase_uom', 20
        )
      ),
      (
        select id
        from public.purchase_orders
        where supplier_id = '20000000-0000-0000-0000-000000000030'
        order by created_at desc
        limit 1
      ),
      'DB-TEST-INVOICE-OVER-RECEIPT',
      current_date,
      'Over-receipt attempt',
      false,
      null
    )
  $test$,
  'P0001',
  'Received quantity exceeds remaining purchase order quantity',
  'receipt cannot exceed the remaining purchase order quantity'
);

select is(
  (
    select count(*)
    from public.goods_receipts
    where supplier_id = '20000000-0000-0000-0000-000000000030'
  ),
  1::bigint,
  'failed over-receipt leaves no draft receipt behind'
);

select lives_ok(
  $test$
    select public.create_and_post_goods_receipt(
      '20000000-0000-0000-0000-000000000030',
      jsonb_build_array(
        jsonb_build_object(
          'purchase_order_item_id',
          (
            select id
            from public.purchase_order_items
            where purchase_order_id = (
              select id
              from public.purchase_orders
              where supplier_id = '20000000-0000-0000-0000-000000000030'
              order by created_at desc
              limit 1
            )
            limit 1
          ),
          'inventory_item_id', '20000000-0000-0000-0000-000000000012',
          'purchase_uom_id', '20000000-0000-0000-0000-000000000010',
          'purchase_quantity', 6,
          'base_quantity_per_purchase_unit', 1,
          'unit_cost_purchase_uom', 20,
          'lot_code', 'DB-TEST-RECEIPT-2'
        )
      ),
      (
        select id
        from public.purchase_orders
        where supplier_id = '20000000-0000-0000-0000-000000000030'
        order by created_at desc
        limit 1
      ),
      'DB-TEST-INVOICE-2',
      current_date,
      'Final receipt',
      false,
      null
    )
  $test$,
  'manager can receive the exact remaining purchase quantity'
);

select is(
  (
    select status
    from public.purchase_orders
    where supplier_id = '20000000-0000-0000-0000-000000000030'
    order by created_at desc
    limit 1
  ),
  'RECEIVED',
  'final receipt completes the purchase order'
);

select is(
  (
    select sum(quantity_delta)
    from public.stock_movements
    where inventory_item_id = '20000000-0000-0000-0000-000000000012'
      and movement_type = 'PURCHASE_RECEIPT'
  ),
  10::numeric,
  'both receipts add exactly the ordered quantity'
);

select is(
  (
    select sum(quantity_delta)
    from public.stock_movements
    where inventory_item_id = '20000000-0000-0000-0000-000000000012'
  ),
  19::numeric,
  'ledger balance reflects sale, approved return, and receipts'
);

select throws_ok(
  $test$
    select public.post_goods_receipt(
      (
        select id
        from public.goods_receipts
        where supplier_id = '20000000-0000-0000-0000-000000000030'
        order by created_at desc
        limit 1
      )
    )
  $test$,
  'P0001',
  'Only DRAFT goods receipts can be posted',
  'posted goods receipt cannot be posted twice'
);

select is(
  (
    select count(*)
    from public.audit_logs
    where action_code = 'GOODS_RECEIPT_POSTED'
      and actor_user_id = '20000000-0000-0000-0000-000000000001'
  ),
  2::bigint,
  'both successful goods receipts are audited'
);

select * from finish();
rollback;
