begin;

create extension if not exists pgtap with schema extensions;

select plan(10);

insert into auth.users (id, email)
values
  (
    '50000000-0000-0000-0000-000000000001',
    'receiving-manager@example.com'
  ),
  (
    '50000000-0000-0000-0000-000000000002',
    'receiving-cashier@example.com'
  );

delete from public.profiles
where id in (
  '50000000-0000-0000-0000-000000000001',
  '50000000-0000-0000-0000-000000000002'
);

insert into public.profiles (id, role_id, status, display_name)
values
  (
    '50000000-0000-0000-0000-000000000001',
    (select id from public.roles where code = 'MANAGER'),
    'ACTIVE',
    'Receiving Test Manager'
  ),
  (
    '50000000-0000-0000-0000-000000000002',
    (select id from public.roles where code = 'CASHIER'),
    'ACTIVE',
    'Receiving Test Cashier'
  );

insert into public.units_of_measure (id, code, name, dimension)
values
  (
    '50000000-0000-0000-0000-000000000010',
    'test_receive_pc',
    'Test Receive Piece',
    'COUNT'
  ),
  (
    '50000000-0000-0000-0000-000000000011',
    'test_receive_box',
    'Test Receive Box',
    'COUNT'
  );

insert into public.inventory_categories (id, name)
values (
  '50000000-0000-0000-0000-000000000020',
  'Receiving Test Supplies'
);

insert into public.inventory_items (
  id, sku, name, category_id, base_uom_id, track_inventory,
  track_expiry, allow_negative_stock, reorder_level
)
values
  (
    '50000000-0000-0000-0000-000000000021',
    'RECEIVE-CUPS',
    'Receiving Test Cups',
    '50000000-0000-0000-0000-000000000020',
    '50000000-0000-0000-0000-000000000010',
    true, false, false, 10
  ),
  (
    '50000000-0000-0000-0000-000000000022',
    'RECEIVE-CAKES',
    'Receiving Test Cakes',
    '50000000-0000-0000-0000-000000000020',
    '50000000-0000-0000-0000-000000000010',
    true, true, false, 1
  );

insert into public.suppliers (id, supplier_code, name)
values (
  '50000000-0000-0000-0000-000000000030',
  'RECEIVE-GROCERY',
  'Receiving Test Grocery'
);

set local role authenticated;
set local request.jwt.claim.role = 'authenticated';
set local request.jwt.claim.sub = '50000000-0000-0000-0000-000000000001';

select lives_ok(
  $test$
    select public.create_and_post_goods_receipt(
      '50000000-0000-0000-0000-000000000030',
      jsonb_build_array(
        jsonb_build_object(
          'inventory_item_id', '50000000-0000-0000-0000-000000000021',
          'purchase_uom_id', '50000000-0000-0000-0000-000000000011',
          'purchase_quantity', 2,
          'base_quantity_per_purchase_unit', 50,
          'unit_cost_purchase_uom', 125,
          'lot_code', 'CUPS-BOX-TEST'
        ),
        jsonb_build_object(
          'inventory_item_id', '50000000-0000-0000-0000-000000000022',
          'purchase_uom_id', '50000000-0000-0000-0000-000000000010',
          'purchase_quantity', 3,
          'base_quantity_per_purchase_unit', 1,
          'unit_cost_purchase_uom', 80,
          'expiration_date', (current_date + 3)::text,
          'lot_code', 'CAKES-BATCH-TEST'
        )
      ),
      null,
      'GROCERY-OR-001',
      current_date,
      'Two supplies received together',
      false,
      null
    )
  $test$,
  'one direct receipt accepts multiple inventory items'
);

select is(
  (
    select count(*)
    from public.goods_receipt_items gri
    join public.goods_receipts gr on gr.id = gri.goods_receipt_id
    where gr.supplier_invoice_number = 'GROCERY-OR-001'
  ),
  2::bigint,
  'the posted receipt stores both received lines'
);

select is(
  (
    select received_quantity
    from public.inventory_lots
    where inventory_item_id = '50000000-0000-0000-0000-000000000021'
  ),
  100::numeric,
  'two boxes of fifty cups add one hundred base pieces'
);

select is(
  (
    select supplier_invoice_number
    from public.v_goods_receipt_summary
    where supplier_id = '50000000-0000-0000-0000-000000000030'
  ),
  'GROCERY-OR-001',
  'the goods receipt summary exposes the external receipt reference'
);

select is(
  (
    select base_quantity_per_purchase_unit
    from public.v_goods_receipt_line_details
    where inventory_item_id = '50000000-0000-0000-0000-000000000021'
  ),
  50::numeric,
  'receipt details preserve the entered package conversion'
);

select is(
  (
    select sum(quantity_delta)
    from public.stock_movements
    where reference_type = 'GOODS_RECEIPT'
      and recorded_by = '50000000-0000-0000-0000-000000000001'
  ),
  103::numeric,
  'both received items are added to the inventory ledger'
);

select is(
  (
    select external_reference_number
    from public.v_inventory_movement_history
    where reference_type = 'GOODS_RECEIPT'
      and inventory_item_id = '50000000-0000-0000-0000-000000000021'
    limit 1
  ),
  'GROCERY-OR-001',
  'inventory history traces received stock to the external receipt number'
);

select throws_ok(
  $test$
    select public.create_and_post_goods_receipt(
      '50000000-0000-0000-0000-000000000030',
      jsonb_build_array(
        jsonb_build_object(
          'inventory_item_id', '50000000-0000-0000-0000-000000000021',
          'purchase_uom_id', '50000000-0000-0000-0000-000000000010',
          'purchase_quantity', 1,
          'base_quantity_per_purchase_unit', 1,
          'unit_cost_purchase_uom', 2
        )
      ),
      null, null, current_date, 'Missing reference', false, null
    )
  $test$,
  'P0001',
  'Supplier invoice or grocery receipt number is required',
  'receiving requires an external invoice or grocery receipt number'
);

select throws_ok(
  $test$
    select public.create_and_post_goods_receipt(
      '50000000-0000-0000-0000-000000000030',
      jsonb_build_array(
        jsonb_build_object(
          'inventory_item_id', '50000000-0000-0000-0000-000000000021',
          'purchase_uom_id', '50000000-0000-0000-0000-000000000010',
          'purchase_quantity', 1,
          'base_quantity_per_purchase_unit', 1,
          'unit_cost_purchase_uom', 2
        )
      ),
      null, 'grocery-or-001', current_date,
      'Duplicate reference', false, null
    )
  $test$,
  'P0001',
  'This supplier invoice or grocery receipt is already recorded',
  'the same supplier reference cannot be recorded twice'
);

set local request.jwt.claim.sub = '50000000-0000-0000-0000-000000000002';

select throws_ok(
  $test$
    select public.create_and_post_goods_receipt(
      '50000000-0000-0000-0000-000000000030',
      jsonb_build_array(
        jsonb_build_object(
          'inventory_item_id', '50000000-0000-0000-0000-000000000021',
          'purchase_uom_id', '50000000-0000-0000-0000-000000000010',
          'purchase_quantity', 1,
          'base_quantity_per_purchase_unit', 1,
          'unit_cost_purchase_uom', 2
        )
      ),
      null, 'CASHIER-OR-001', current_date,
      'Unauthorized receipt', false, null
    )
  $test$,
  'P0001',
  'Permission denied',
  'cashiers cannot receive inventory stock'
);

select * from finish();
rollback;
