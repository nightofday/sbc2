begin;

create extension if not exists pgtap with schema extensions;

select plan(33);

insert into auth.users (id, email)
values
  ('50000000-0000-0000-0000-000000000001', 'posting-admin-db-test@example.com'),
  ('50000000-0000-0000-0000-000000000002', 'posting-other-db-test@example.com');

delete from public.profiles
where id in (
  '50000000-0000-0000-0000-000000000001',
  '50000000-0000-0000-0000-000000000002'
);

insert into public.profiles (id, role_id, status, display_name)
values
  (
    '50000000-0000-0000-0000-000000000001',
    (select id from public.roles where code = 'ADMIN'),
    'ACTIVE',
    'Posting Test Admin'
  ),
  (
    '50000000-0000-0000-0000-000000000002',
    (select id from public.roles where code = 'ADMIN'),
    'ACTIVE',
    'Posting Test Other Admin'
  );

set local role authenticated;
set local request.jwt.claim.role = 'authenticated';
set local request.jwt.claim.sub = '50000000-0000-0000-0000-000000000001';

-- Shift start -----------------------------------------------------------

select lives_ok(
  $test$
    select public.start_shift(
      null, 100, '50000000-0000-0000-0000-0000000000a1'
    )
  $test$,
  'a shift starts with a request ID'
);

select is(
  (
    select (public.start_shift(
      null, 100, '50000000-0000-0000-0000-0000000000a1'
    )).id
  ),
  (
    select id from public.shifts
    where employee_id = '50000000-0000-0000-0000-000000000001'
  ),
  'repeating the start returns the same shift instead of failing'
);

-- Cash movement ---------------------------------------------------------

select lives_ok(
  $test$
    select public.record_shift_cash_movement(
      public.current_open_shift_id(), 'PAY_IN', 50, 'Request test float',
      '50000000-0000-0000-0000-0000000000a2'
    )
  $test$,
  'a cash movement is recorded'
);

select lives_ok(
  $test$
    select public.record_shift_cash_movement(
      public.current_open_shift_id(), 'PAY_IN', 50, 'Request test float',
      '50000000-0000-0000-0000-0000000000a2'
    )
  $test$,
  'the same cash movement request is accepted again'
);

select is(
  (
    select count(*) from public.shift_cash_movements
    where reason = 'Request test float'
  ),
  1::bigint,
  'the repeated cash movement is recorded once'
);

select lives_ok(
  $test$
    select public.record_shift_cash_movement(
      public.current_open_shift_id(), 'PAY_IN', 5, 'No request ID'
    );
    select public.record_shift_cash_movement(
      public.current_open_shift_id(), 'PAY_IN', 5, 'No request ID'
    );
  $test$,
  'calls without a request ID still work'
);

select is(
  (
    select count(*) from public.shift_cash_movements
    where reason = 'No request ID'
  ),
  2::bigint,
  'without a request ID each call posts, as before'
);

select throws_ok(
  $test$
    select public.record_shift_cash_movement(
      public.current_open_shift_id(), 'PAY_IN', 50, 'Wrong operation',
      '50000000-0000-0000-0000-0000000000a1'
    )
  $test$,
  'P0001',
  'This request ID is not available',
  'a request ID cannot be reused for a different operation'
);

-- Inventory -------------------------------------------------------------

select lives_ok(
  $test$
    select public.create_inventory_item_with_initial_stock(
      'Posting Request Test Item', null,
      (select id from public.units_of_measure where code = 'pc'),
      'REQ-TEST-ITEM', false, 0, 10, null, 0
    )
  $test$,
  'a test item with 10 pieces is created'
);

select lives_ok(
  $test$
    select public.create_and_post_stock_out(
      'Request test release',
      jsonb_build_array(jsonb_build_object(
        'inventory_item_id',
        (select id from public.inventory_items where sku = 'REQ-TEST-ITEM'),
        'issue_uom_id',
        (select id from public.units_of_measure where code = 'pc'),
        'issue_quantity', 2,
        'base_quantity_per_issue_unit', 1
      )),
      null, null, now(), '50000000-0000-0000-0000-0000000000a3'
    );
    select public.create_and_post_stock_out(
      'Request test release',
      jsonb_build_array(jsonb_build_object(
        'inventory_item_id',
        (select id from public.inventory_items where sku = 'REQ-TEST-ITEM'),
        'issue_uom_id',
        (select id from public.units_of_measure where code = 'pc'),
        'issue_quantity', 2,
        'base_quantity_per_issue_unit', 1
      )),
      null, null, now(), '50000000-0000-0000-0000-0000000000a3'
    );
  $test$,
  'a stock release is submitted twice with one request ID'
);

select is(
  (
    select count(*) from public.stock_out_transactions
    where purpose = 'Request test release'
  ),
  1::bigint,
  'the repeated release creates one document'
);

select is(
  (
    select usable_quantity from public.v_inventory_stock
    where sku = 'REQ-TEST-ITEM'
  ),
  8::numeric(14,4),
  'the repeated release deducts stock once'
);

select lives_ok(
  $test$
    select public.adjust_inventory_stock(
      (select id from public.inventory_items where sku = 'REQ-TEST-ITEM'),
      'MANUAL_OUT', 1, 'Request test adjustment', null, 0,
      '50000000-0000-0000-0000-0000000000a4'
    );
    select public.adjust_inventory_stock(
      (select id from public.inventory_items where sku = 'REQ-TEST-ITEM'),
      'MANUAL_OUT', 1, 'Request test adjustment', null, 0,
      '50000000-0000-0000-0000-0000000000a4'
    );
  $test$,
  'a stock adjustment is submitted twice with one request ID'
);

select is(
  (
    select usable_quantity from public.v_inventory_stock
    where sku = 'REQ-TEST-ITEM'
  ),
  7::numeric(14,4),
  'the repeated adjustment deducts stock once'
);

select lives_ok(
  $test$
    select public.dispose_inventory_lot(
      (
        select lot_id from public.v_inventory_lots
        where item_name = 'Posting Request Test Item'
        limit 1
      ),
      'DAMAGED', 1, 'Request test disposal',
      '50000000-0000-0000-0000-0000000000a5'
    );
    select public.dispose_inventory_lot(
      (
        select lot_id from public.v_inventory_lots
        where item_name = 'Posting Request Test Item'
        limit 1
      ),
      'DAMAGED', 1, 'Request test disposal',
      '50000000-0000-0000-0000-0000000000a5'
    );
  $test$,
  'a disposal is submitted twice with one request ID'
);

select is(
  (
    select usable_quantity from public.v_inventory_stock
    where sku = 'REQ-TEST-ITEM'
  ),
  6::numeric(14,4),
  'the repeated disposal deducts stock once'
);

select lives_ok(
  $test$
    select public.create_and_post_stock_count(
      jsonb_build_array(jsonb_build_object(
        'inventory_item_id',
        (select id from public.inventory_items where sku = 'REQ-TEST-ITEM'),
        'counted_quantity', 5
      )),
      'Request test count', now(), '50000000-0000-0000-0000-0000000000a6'
    );
    select public.create_and_post_stock_count(
      jsonb_build_array(jsonb_build_object(
        'inventory_item_id',
        (select id from public.inventory_items where sku = 'REQ-TEST-ITEM'),
        'counted_quantity', 5
      )),
      'Request test count', now(), '50000000-0000-0000-0000-0000000000a6'
    );
  $test$,
  'a physical count is submitted twice with one request ID'
);

select is(
  (
    select count(*) from public.stock_counts
    where notes = 'Request test count'
  ),
  1::bigint,
  'the repeated count creates one document'
);

-- Purchasing, payables and expenses --------------------------------------

select lives_ok(
  $test$ select public.create_supplier('Posting Request Test Supplier') $test$,
  'a test supplier is created'
);

select lives_ok(
  $test$
    select public.create_and_post_goods_receipt(
      (
        select id from public.suppliers
        where name = 'Posting Request Test Supplier'
      ),
      jsonb_build_array(jsonb_build_object(
        'inventory_item_id',
        (select id from public.inventory_items where sku = 'REQ-TEST-ITEM'),
        'purchase_uom_id',
        (select id from public.units_of_measure where code = 'pc'),
        'purchase_quantity', 1,
        'base_quantity_per_purchase_unit', 1,
        'unit_cost_purchase_uom', 10
      )),
      null, 'REQ-TEST-GR-1', public.business_today(), null, true, null,
      '50000000-0000-0000-0000-0000000000a7'
    )
  $test$,
  'a goods receipt is posted'
);

select is(
  (
    select (public.create_and_post_goods_receipt(
      (
        select id from public.suppliers
        where name = 'Posting Request Test Supplier'
      ),
      jsonb_build_array(jsonb_build_object(
        'inventory_item_id',
        (select id from public.inventory_items where sku = 'REQ-TEST-ITEM'),
        'purchase_uom_id',
        (select id from public.units_of_measure where code = 'pc'),
        'purchase_quantity', 1,
        'base_quantity_per_purchase_unit', 1,
        'unit_cost_purchase_uom', 10
      )),
      null, 'REQ-TEST-GR-1', public.business_today(), null, true, null,
      '50000000-0000-0000-0000-0000000000a7'
    )).id
  ),
  (
    select id from public.goods_receipts
    where supplier_invoice_number = 'REQ-TEST-GR-1'
  ),
  'repeating the receipt returns it instead of a duplicate-reference error'
);

select is(
  (
    select usable_quantity from public.v_inventory_stock
    where sku = 'REQ-TEST-ITEM'
  ),
  6::numeric(14,4),
  'the repeated receipt adds stock once'
);

select lives_ok(
  $test$
    select public.record_supplier_bill_payment(
      (
        select id from public.supplier_bills
        where supplier_invoice_number = 'REQ-TEST-GR-1'
      ),
      (select id from public.payment_methods where code = 'CASH'),
      4, null, null, '50000000-0000-0000-0000-0000000000a8'
    );
    select public.record_supplier_bill_payment(
      (
        select id from public.supplier_bills
        where supplier_invoice_number = 'REQ-TEST-GR-1'
      ),
      (select id from public.payment_methods where code = 'CASH'),
      4, null, null, '50000000-0000-0000-0000-0000000000a8'
    );
  $test$,
  'a supplier payment is submitted twice with one request ID'
);

select is(
  (
    select balance from public.v_supplier_balances
    where supplier_invoice_number = 'REQ-TEST-GR-1'
  ),
  6::numeric(14,2),
  'the repeated supplier payment is applied once'
);

select lives_ok(
  $test$
    select public.create_expense(
      (select id from public.expense_categories where code = 'INGREDIENTS'),
      'Request test expense', 100, null, null,
      (
        select id from public.suppliers
        where name = 'Posting Request Test Supplier'
      ),
      'REQ-TEST-EX-1', null, '50000000-0000-0000-0000-0000000000a9'
    )
  $test$,
  'an expense is recorded'
);

select is(
  (
    select (public.create_expense(
      (select id from public.expense_categories where code = 'INGREDIENTS'),
      'Request test expense', 100, null, null,
      (
        select id from public.suppliers
        where name = 'Posting Request Test Supplier'
      ),
      'REQ-TEST-EX-1', null, '50000000-0000-0000-0000-0000000000a9'
    )).id
  ),
  (select id from public.expenses where reference_number = 'REQ-TEST-EX-1'),
  'repeating the expense returns it instead of a duplicate-reference error'
);

-- Refund ----------------------------------------------------------------

select lives_ok(
  $test$
    select public.place_order_v2(
      p_order_type := 'TAKE_OUT',
      p_items := jsonb_build_array(jsonb_build_object(
        'menu_variant_id', (
          select variant_id from public.v_pos_menu
          where inventory_tracking_mode = 'UNTRACKED'
          order by sku limit 1
        ),
        'quantity', 2
      )),
      p_payment := jsonb_build_object(
        'payment_method_id',
        (select id from public.payment_methods where code = 'CASH'),
        'amount_tendered', 5000
      ),
      p_customer_name := 'Posting Request Refund Customer',
      p_client_request_id := '50000000-0000-0000-0000-0000000000b0'
    )
  $test$,
  'an order is placed for the refund test'
);

select lives_ok(
  $test$
    select public.process_refund_items(
      (
        select id from public.orders
        where customer_name = 'Posting Request Refund Customer'
      ),
      (
        select jsonb_build_array(jsonb_build_object(
          'order_item_id', oi.id, 'quantity', 1
        ))
        from public.order_items oi
        join public.orders o on o.id = oi.order_id
        where o.customer_name = 'Posting Request Refund Customer'
      ),
      'Request test refund', null, '50000000-0000-0000-0000-0000000000b1'
    );
    select public.process_refund_items(
      (
        select id from public.orders
        where customer_name = 'Posting Request Refund Customer'
      ),
      (
        select jsonb_build_array(jsonb_build_object(
          'order_item_id', oi.id, 'quantity', 1
        ))
        from public.order_items oi
        join public.orders o on o.id = oi.order_id
        where o.customer_name = 'Posting Request Refund Customer'
      ),
      'Request test refund', null, '50000000-0000-0000-0000-0000000000b1'
    );
  $test$,
  'a refund is submitted twice with one request ID'
);

select is(
  (
    select count(*) from public.refunds
    where reason = 'Request test refund'
  ),
  1::bigint,
  'the repeated refund is recorded once'
);

-- Shift end -------------------------------------------------------------

select lives_ok(
  $test$
    select public.end_shift(
      public.current_open_shift_id(), 0, 'Request test close',
      '50000000-0000-0000-0000-0000000000b2'
    )
  $test$,
  'the shift is closed'
);

select is(
  (
    select (public.end_shift(
      (
        select id from public.shifts
        where closing_notes = 'Request test close'
      ),
      0, 'Request test close', '50000000-0000-0000-0000-0000000000b2'
    )).status
  ),
  'CLOSED',
  'repeating the close returns the closed shift instead of failing'
);

-- Ownership -------------------------------------------------------------

set local request.jwt.claim.sub = '50000000-0000-0000-0000-000000000002';

select throws_ok(
  $test$
    select public.start_shift(
      null, 100, '50000000-0000-0000-0000-0000000000a1'
    )
  $test$,
  'P0001',
  'This request ID is not available',
  'another user cannot replay a request'
);

reset role;

select ok(
  not has_table_privilege('authenticated', 'public.client_requests', 'SELECT')
  and not has_function_privilege(
    'authenticated', 'public.claim_client_request(uuid,text)', 'EXECUTE'
  ),
  'clients cannot read the request log or call its helpers'
);

select * from finish();

rollback;
