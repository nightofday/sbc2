begin;

create extension if not exists pgtap with schema extensions;

select plan(27);

insert into auth.users (id, email)
values
  ('e0000000-0000-0000-0000-000000000001', 'reversal-admin-db-test@example.com'),
  ('e0000000-0000-0000-0000-000000000002', 'reversal-cashier-db-test@example.com');

delete from public.profiles
where id in (
  'e0000000-0000-0000-0000-000000000001',
  'e0000000-0000-0000-0000-000000000002'
);

insert into public.profiles (id, role_id, status, display_name)
values
  (
    'e0000000-0000-0000-0000-000000000001',
    (select id from public.roles where code = 'ADMIN'),
    'ACTIVE',
    'Reversal Test Admin'
  ),
  (
    'e0000000-0000-0000-0000-000000000002',
    (select id from public.roles where code = 'CASHIER'),
    'ACTIVE',
    'Reversal Test Cashier'
  );

insert into public.suppliers (id, supplier_code, name)
values (
  'e0000000-0000-0000-0000-000000000010',
  'REVERSAL-TEST',
  'Reversal Test Supplier'
);

set local role authenticated;
set local request.jwt.claim.role = 'authenticated';
set local request.jwt.claim.sub = 'e0000000-0000-0000-0000-000000000001';

-- Receiving teaches the package size -----------------------------------------

select lives_ok(
  $test$
    select public.create_inventory_item_with_initial_stock(
      'Reversal Test Cups', null,
      (select id from public.units_of_measure where code = 'pc'),
      'REVERSAL-TEST-INV', false, 0, 0, null, 0
    );
  $test$,
  'a stock item is set up'
);

select lives_ok(
  $test$
    select public.create_and_post_goods_receipt(
      'e0000000-0000-0000-0000-000000000010',
      jsonb_build_array(jsonb_build_object(
        'inventory_item_id',
        (select id from public.inventory_items where sku = 'REVERSAL-TEST-INV'),
        'purchase_uom_id',
        (select id from public.units_of_measure where code = 'box'),
        'purchase_quantity', 2,
        'base_quantity_per_purchase_unit', 50,
        'unit_cost_purchase_uom', 100
      )),
      null, 'REVERSAL-INV-1', public.business_today()
    )
  $test$,
  'two boxes of 50 are received'
);

select is(
  (
    select base_quantity_per_purchase_unit::text || ' at ' || last_unit_cost::text
    from public.supplier_items
    where supplier_id = 'e0000000-0000-0000-0000-000000000010'
  ),
  '50.0000 at 100.0000',
  'the package size and cost are remembered for the supplier'
);

select is(
  (select count(*) from public.check_stock_consistency()),
  0::bigint,
  'every lot agrees with its movements after receiving'
);

-- Write-off and its reversal -----------------------------------------------------

select lives_ok(
  $test$
    select public.dispose_inventory_lot(
      (
        select l.id from public.inventory_lots l
        join public.inventory_items ii on ii.id = l.inventory_item_id
        where ii.sku = 'REVERSAL-TEST-INV' and l.remaining_quantity > 0
      ),
      'DAMAGED', 30, 'Reversal test damage'
    )
  $test$,
  '30 are written off as damaged'
);

select is(
  (
    select (loss ->> 'quantity')::numeric
    from jsonb_array_elements(
      public.get_business_report(public.business_today(), public.business_today())
        -> 'stock_losses'
    ) loss
    where loss ->> 'item_name' = 'Reversal Test Cups'
  ),
  30::numeric,
  'the report lists the loss'
);

select throws_ok(
  $test$
    select public.void_lot_disposal(
      (select id from public.stock_movements where reason = 'Reversal test damage'),
      '  '
    )
  $test$,
  'P0001',
  'A reason is required to reverse a stock write-off',
  'a reversal needs a reason'
);

select lives_ok(
  $test$
    select public.void_lot_disposal(
      (select id from public.stock_movements where reason = 'Reversal test damage'),
      'Counted again, not damaged'
    )
  $test$,
  'the write-off is reversed'
);

select is(
  (
    select l.remaining_quantity
    from public.inventory_lots l
    join public.inventory_items ii on ii.id = l.inventory_item_id
    where ii.sku = 'REVERSAL-TEST-INV'
  ),
  100.0000::numeric,
  'the quantity is back in its lot'
);

select is(
  (
    select count(*) from public.stock_movements sm
    join public.inventory_items ii on ii.id = sm.inventory_item_id
    where ii.sku = 'REVERSAL-TEST-INV'
      and sm.movement_type in ('DAMAGED', 'REVERSAL')
  ),
  2::bigint,
  'the write-off and its reversal both stay in the history'
);

select is(
  (
    select count(*)
    from jsonb_array_elements(
      public.get_business_report(public.business_today(), public.business_today())
        -> 'stock_losses'
    ) loss
    where loss ->> 'item_name' = 'Reversal Test Cups'
  ),
  0::bigint,
  'the report no longer counts it as a loss'
);

select is(
  (
    select (row ->> 'opening')::numeric + (row ->> 'received')::numeric
      - (row ->> 'sold')::numeric - (row ->> 'released')::numeric
      - (row ->> 'lost')::numeric + (row ->> 'other')::numeric
      - (row ->> 'closing')::numeric
    from jsonb_array_elements(
      public.get_business_report(public.business_today(), public.business_today())
        -> 'stock_movement'
    ) row
    where row ->> 'item_name' = 'Reversal Test Cups'
  ),
  0::numeric,
  'the stock movement row still adds up'
);

select ok(
  (
    select is_reversed
    from public.v_inventory_movement_history
    where reason = 'Reversal test damage'
  ),
  'the stock history marks the write-off as reversed'
);

select throws_ok(
  $test$
    select public.void_lot_disposal(
      (select id from public.stock_movements where reason = 'Reversal test damage'),
      'Again'
    )
  $test$,
  'P0001',
  'This write-off has already been reversed',
  'a write-off is reversed once'
);

select is(
  (select count(*) from public.check_stock_consistency()),
  0::bigint,
  'every lot still agrees with its movements'
);

-- Supplier payment and its reversal -------------------------------------------------

select lives_ok(
  $test$
    select public.record_supplier_bill_payment(
      (
        select id from public.supplier_bills
        where supplier_id = 'e0000000-0000-0000-0000-000000000010'
      ),
      (select id from public.payment_methods where code = 'CASH'),
      200, null, 'Reversal test payment'
    )
  $test$,
  'the bill of 200 is paid in full'
);

select is(
  (
    select status from public.supplier_bills
    where supplier_id = 'e0000000-0000-0000-0000-000000000010'
  ),
  'PAID',
  'the bill is marked paid'
);

select lives_ok(
  $test$
    select public.void_supplier_bill_payment(
      (
        select id from public.supplier_bill_payments
        where notes = 'Reversal test payment'
      ),
      'Paid the wrong supplier',
      'e0000000-0000-0000-0000-0000000000a1'
    );
    select public.void_supplier_bill_payment(
      (
        select id from public.supplier_bill_payments
        where notes = 'Reversal test payment'
      ),
      'Paid the wrong supplier',
      'e0000000-0000-0000-0000-0000000000a1'
    );
  $test$,
  'the payment is reversed, and repeating the same request is accepted'
);

select is(
  (
    select count(*) || ' rows totalling ' || sum(amount)
    from public.supplier_bill_payments
    where supplier_bill_id = (
      select id from public.supplier_bills
      where supplier_id = 'e0000000-0000-0000-0000-000000000010'
    )
  ),
  '2 rows totalling 0.00',
  'one reversal is stored beside the payment, and they cancel out'
);

select is(
  (
    select status || ' with ' || balance::text || ' owed'
    from public.supplier_bills sb
    join public.v_supplier_balances b on b.supplier_bill_id = sb.id
    where sb.supplier_id = 'e0000000-0000-0000-0000-000000000010'
  ),
  'UNPAID with 200.00 owed',
  'the bill is unpaid again with its full balance'
);

select throws_ok(
  $test$
    select public.void_supplier_bill_payment(
      (
        select id from public.supplier_bill_payments
        where notes = 'Reversal test payment'
      ),
      'Again'
    )
  $test$,
  'P0001',
  'This payment has already been reversed',
  'a payment is reversed once'
);

select throws_ok(
  $test$
    select public.void_supplier_bill_payment(
      (
        select id from public.supplier_bill_payments
        where notes = 'Paid the wrong supplier'
      ),
      'Undo the undo'
    )
  $test$,
  'P0001',
  'Only a payment can be reversed',
  'a reversal cannot itself be reversed'
);

select is(
  (
    select string_agg(status, ', ' order by status)
    from public.v_business_transaction_trace
    where event_type = 'SUPPLIER_PAYMENT'
      and party_name = 'Reversal Test Supplier'
  ),
  'REVERSAL, REVERSED',
  'the trace shows the payment as reversed and the reversal beside it'
);

-- Voided documents stay in the trace ---------------------------------------------------

select lives_ok(
  $test$
    select public.void_goods_receipt(
      (
        select id from public.goods_receipts
        where supplier_id = 'e0000000-0000-0000-0000-000000000010'
      ),
      'Reversal test: delivered to the wrong branch'
    )
  $test$,
  'the receipt is voided'
);

select is(
  (
    select status || ': ' || void_reason
    from public.v_business_transaction_trace
    where event_type = 'STOCK_IN'
      and party_name = 'Reversal Test Supplier'
  ),
  'VOIDED: Reversal test: delivered to the wrong branch',
  'the voided receipt stays in the trace with its reason'
);

-- Permissions -------------------------------------------------------------------------

set local request.jwt.claim.sub = 'e0000000-0000-0000-0000-000000000002';

select throws_ok(
  $test$
    select public.void_lot_disposal(gen_random_uuid(), 'No permission')
  $test$,
  'P0001',
  'Permission denied',
  'a cashier cannot reverse a write-off'
);

select throws_ok(
  $test$
    select public.void_supplier_bill_payment(gen_random_uuid(), 'No permission')
  $test$,
  'P0001',
  'Permission denied',
  'a cashier cannot reverse a supplier payment'
);

select * from finish();
rollback;
