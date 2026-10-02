begin;

create extension if not exists pgtap with schema extensions;

select plan(39);

insert into auth.users (id, email)
values
  ('70000000-0000-0000-0000-000000000001', 'voids-admin-db-test@example.com'),
  ('70000000-0000-0000-0000-000000000002', 'voids-cashier-db-test@example.com');

delete from public.profiles
where id in (
  '70000000-0000-0000-0000-000000000001',
  '70000000-0000-0000-0000-000000000002'
);

insert into public.profiles (id, role_id, status, display_name)
values
  (
    '70000000-0000-0000-0000-000000000001',
    (select id from public.roles where code = 'ADMIN'),
    'ACTIVE',
    'Voids Test Admin'
  ),
  (
    '70000000-0000-0000-0000-000000000002',
    (select id from public.roles where code = 'CASHIER'),
    'ACTIVE',
    'Voids Test Cashier'
  );

set local role authenticated;
set local request.jwt.claim.role = 'authenticated';
set local request.jwt.claim.sub = '70000000-0000-0000-0000-000000000001';

-- Suppliers (SUP-01) ------------------------------------------------------

select lives_ok(
  $test$
    select public.create_supplier(
      'Voids Test Supplier', 'Ana Cruz', '0917-000-1111', 'ana@example.com',
      '12 Bajada Road', 15, 'Delivers on Tuesdays'
    )
  $test$,
  'a supplier with full details is created'
);

select lives_ok(
  $test$
    select public.update_supplier(
      (select id from public.suppliers where name = 'Voids Test Supplier'),
      'Voids Test Supplier Renamed'
    )
  $test$,
  'only the supplier name is changed'
);

select is(
  (
    select row(
      contact_person, phone, email, address, payment_terms_days, notes,
      is_active
    )::text
    from public.suppliers
    where name = 'Voids Test Supplier Renamed'
  ),
  row(
    'Ana Cruz', '0917-000-1111', 'ana@example.com', '12 Bajada Road', 15,
    'Delivers on Tuesdays', true
  )::text,
  'renaming keeps the contact, email, address, terms and notes'
);

select lives_ok(
  $test$
    select public.update_supplier(
      (
        select id from public.suppliers
        where name = 'Voids Test Supplier Renamed'
      ),
      null,
      p_is_active := false
    )
  $test$,
  'the supplier is archived'
);

select is(
  (
    select row(
      contact_person, phone, email, address, payment_terms_days, notes,
      is_active, archived_at is not null
    )::text
    from public.suppliers
    where name = 'Voids Test Supplier Renamed'
  ),
  row(
    'Ana Cruz', '0917-000-1111', 'ana@example.com', '12 Bajada Road', 15,
    'Delivers on Tuesdays', false, true
  )::text,
  'archiving keeps every detail and records when it happened'
);

select lives_ok(
  $test$
    select public.update_supplier(
      (
        select id from public.suppliers
        where name = 'Voids Test Supplier Renamed'
      ),
      null,
      p_email := '',
      p_is_active := true
    )
  $test$,
  'an empty string clears a field and the supplier is restored'
);

select is(
  (
    select row(email, phone, is_active, archived_at)::text
    from public.suppliers
    where name = 'Voids Test Supplier Renamed'
  ),
  row(null::text, '0917-000-1111', true, null::timestamptz)::text,
  'only the cleared field changed'
);

-- Expenses ----------------------------------------------------------------

select lives_ok(
  $test$
    select public.create_expense(
      (select id from public.expense_categories where code = 'INGREDIENTS'),
      'Voids test expense', 100, null, null,
      (
        select id from public.suppliers
        where name = 'Voids Test Supplier Renamed'
      ),
      'VOIDS-EX-1'
    )
  $test$,
  'an expense is recorded'
);

select lives_ok(
  $test$
    select public.update_expense(
      (select id from public.expenses where reference_number = 'VOIDS-EX-1'),
      (select id from public.expense_categories where code = 'INGREDIENTS'),
      'Voids test expense', 150, public.business_today(), null,
      (
        select id from public.suppliers
        where name = 'Voids Test Supplier Renamed'
      ),
      'VOIDS-EX-1'
    )
  $test$,
  'the posted expense amount is corrected'
);

select throws_ok(
  $test$
    select public.void_expense(
      (select id from public.expenses where reference_number = 'VOIDS-EX-1')
    )
  $test$,
  'P0001',
  'A reason is required to void an expense',
  'an expense cannot be voided without a reason'
);

select lives_ok(
  $test$
    select public.void_expense(
      (select id from public.expenses where reference_number = 'VOIDS-EX-1'),
      'Entered twice'
    )
  $test$,
  'the expense is voided with a reason'
);

select is(
  (
    select row(status, void_reason, voided_by, voided_at is not null)::text
    from public.expenses
    where reference_number = 'VOIDS-EX-1'
  ),
  row(
    'VOIDED', 'Entered twice',
    '70000000-0000-0000-0000-000000000001'::uuid, true
  )::text,
  'the void records its reason, who did it and when'
);

-- Stock release -----------------------------------------------------------

select lives_ok(
  $test$
    select public.create_inventory_item_with_initial_stock(
      'Voids Test Item', null,
      (select id from public.units_of_measure where code = 'pc'),
      'VOIDS-ITEM', false, 0, 10, null, 2
    )
  $test$,
  'a test item with 10 pieces is created'
);

select lives_ok(
  $test$
    select public.create_and_post_stock_out(
      'Voids test release',
      jsonb_build_array(jsonb_build_object(
        'inventory_item_id',
        (select id from public.inventory_items where sku = 'VOIDS-ITEM'),
        'issue_uom_id',
        (select id from public.units_of_measure where code = 'pc'),
        'issue_quantity', 4,
        'base_quantity_per_issue_unit', 1
      ))
    )
  $test$,
  'four pieces are released'
);

select throws_ok(
  $test$
    select public.void_stock_out(
      (
        select id from public.stock_out_transactions
        where purpose = 'Voids test release'
      ),
      '  '
    )
  $test$,
  'P0001',
  'A reason is required to void a stock release',
  'a release cannot be voided without a reason'
);

select lives_ok(
  $test$
    select public.void_stock_out(
      (
        select id from public.stock_out_transactions
        where purpose = 'Voids test release'
      ),
      'Released the wrong item'
    )
  $test$,
  'the release is voided'
);

select is(
  (
    select row(usable_quantity, current_quantity)::text
    from public.v_inventory_stock
    where sku = 'VOIDS-ITEM'
  ),
  row(10::numeric(14,4), 10::numeric(14,4))::text,
  'voiding the release returns the stock to its lot and to the ledger'
);

select is(
  (
    select row(status, void_reason)::text
    from public.stock_out_transactions
    where purpose = 'Voids test release'
  ),
  row('VOIDED', 'Released the wrong item')::text,
  'the release is kept and marked voided'
);

select is(
  (
    select count(*)
    from public.v_inventory_movement_history
    where inventory_item_id =
      (select id from public.inventory_items where sku = 'VOIDS-ITEM')
      and source_document_number is not null
  ),
  2::bigint,
  'the original movement and its reversal both remain in the history'
);

select throws_ok(
  $test$
    select public.void_stock_out(
      (
        select id from public.stock_out_transactions
        where purpose = 'Voids test release'
      ),
      'Again'
    )
  $test$,
  'P0001',
  'Only a posted stock release can be voided',
  'a release cannot be voided twice'
);

-- Inventory count ---------------------------------------------------------

select lives_ok(
  $test$
    select public.create_and_post_stock_count(
      jsonb_build_array(jsonb_build_object(
        'inventory_item_id',
        (select id from public.inventory_items where sku = 'VOIDS-ITEM'),
        'counted_quantity', 7
      )),
      'Voids test count down'
    )
  $test$,
  'a count finds 7, three fewer than the system'
);

select lives_ok(
  $test$
    select public.void_stock_count(
      (
        select id from public.stock_counts
        where notes = 'Voids test count down'
      ),
      'Counted the wrong shelf'
    )
  $test$,
  'the count is voided'
);

select is(
  (
    select usable_quantity from public.v_inventory_stock
    where sku = 'VOIDS-ITEM'
  ),
  10::numeric(14,4),
  'voiding a count that removed stock puts it back'
);

select is(
  (
    select status from public.stock_counts
    where notes = 'Voids test count down'
  ),
  'CANCELLED',
  'the count is kept and marked cancelled'
);

select lives_ok(
  $test$
    select public.create_and_post_stock_count(
      jsonb_build_array(jsonb_build_object(
        'inventory_item_id',
        (select id from public.inventory_items where sku = 'VOIDS-ITEM'),
        'counted_quantity', 12
      )),
      'Voids test count up'
    );
    select public.create_and_post_stock_out(
      'Voids test release after count',
      jsonb_build_array(jsonb_build_object(
        'inventory_item_id',
        (select id from public.inventory_items where sku = 'VOIDS-ITEM'),
        'issue_uom_id',
        (select id from public.units_of_measure where code = 'pc'),
        'issue_quantity', 11,
        'base_quantity_per_issue_unit', 1
      ))
    );
  $test$,
  'a count adds two pieces and eleven are then released'
);

select throws_ok(
  $test$
    select public.void_stock_count(
      (select id from public.stock_counts where notes = 'Voids test count up'),
      'Too late'
    )
  $test$,
  'P0001',
  'Stock added by this count has already been used. Post a new count instead of voiding this one.',
  'a count cannot be voided once the stock it added has been used'
);

-- Goods receipt -----------------------------------------------------------

select lives_ok(
  $test$
    select public.create_inventory_item_with_initial_stock(
      'Voids Test Received Item', null,
      (select id from public.units_of_measure where code = 'pc'),
      'VOIDS-ITEM-2', false, 0, 0, null, 0
    );
    select public.create_and_post_goods_receipt(
      (
        select id from public.suppliers
        where name = 'Voids Test Supplier Renamed'
      ),
      jsonb_build_array(jsonb_build_object(
        'inventory_item_id',
        (select id from public.inventory_items where sku = 'VOIDS-ITEM-2'),
        'purchase_uom_id',
        (select id from public.units_of_measure where code = 'pc'),
        'purchase_quantity', 5,
        'base_quantity_per_purchase_unit', 1,
        'unit_cost_purchase_uom', 10
      )),
      null, 'VOIDS-GR-1', public.business_today()
    );
  $test$,
  'five pieces are received on invoice VOIDS-GR-1'
);

select lives_ok(
  $test$
    select public.void_goods_receipt(
      (
        select id from public.goods_receipts
        where supplier_invoice_number = 'VOIDS-GR-1'
      ),
      'Wrong supplier invoice'
    )
  $test$,
  'the untouched receipt is voided'
);

select is(
  (
    select row(usable_quantity, current_quantity)::text
    from public.v_inventory_stock
    where sku = 'VOIDS-ITEM-2'
  ),
  row(0::numeric(14,4), 0::numeric(14,4))::text,
  'voiding the receipt removes its stock from the lot and the ledger'
);

select is(
  (
    select row(gr.status, gr.void_reason, sb.status)::text
    from public.goods_receipts gr
    join public.supplier_bills sb on sb.goods_receipt_id = gr.id
    where gr.supplier_invoice_number = 'VOIDS-GR-1'
  ),
  row('CANCELLED', 'Wrong supplier invoice', 'VOID')::text,
  'the receipt is kept as cancelled and its unpaid bill is voided'
);

select lives_ok(
  $test$
    select public.create_and_post_goods_receipt(
      (
        select id from public.suppliers
        where name = 'Voids Test Supplier Renamed'
      ),
      jsonb_build_array(jsonb_build_object(
        'inventory_item_id',
        (select id from public.inventory_items where sku = 'VOIDS-ITEM-2'),
        'purchase_uom_id',
        (select id from public.units_of_measure where code = 'pc'),
        'purchase_quantity', 5,
        'base_quantity_per_purchase_unit', 1,
        'unit_cost_purchase_uom', 10
      )),
      null, 'VOIDS-GR-1', public.business_today()
    )
  $test$,
  'the same supplier invoice can be received again after the void'
);

select lives_ok(
  $test$
    select public.record_supplier_bill_payment(
      (
        select sb.id
        from public.supplier_bills sb
        join public.goods_receipts gr on gr.id = sb.goods_receipt_id
        where gr.supplier_invoice_number = 'VOIDS-GR-1'
          and gr.status = 'POSTED'
      ),
      (select id from public.payment_methods where code = 'CASH'),
      10
    )
  $test$,
  'part of the new bill is paid'
);

select throws_ok(
  $test$
    select public.void_goods_receipt(
      (
        select id from public.goods_receipts
        where supplier_invoice_number = 'VOIDS-GR-1'
          and status = 'POSTED'
      ),
      'Too late'
    )
  $test$,
  'P0001',
  'The supplier bill for this receipt has payments recorded, so the receipt cannot be voided. Reverse the payments first.',
  'a receipt with a paid bill cannot be voided'
);

select lives_ok(
  $test$
    select public.create_and_post_goods_receipt(
      (
        select id from public.suppliers
        where name = 'Voids Test Supplier Renamed'
      ),
      jsonb_build_array(jsonb_build_object(
        'inventory_item_id',
        (select id from public.inventory_items where sku = 'VOIDS-ITEM-2'),
        'purchase_uom_id',
        (select id from public.units_of_measure where code = 'pc'),
        'purchase_quantity', 5,
        'base_quantity_per_purchase_unit', 1,
        'unit_cost_purchase_uom', 10
      )),
      null, 'VOIDS-GR-2', public.business_today()
    );
    select public.create_and_post_stock_out(
      'Voids test release across receipts',
      jsonb_build_array(jsonb_build_object(
        'inventory_item_id',
        (select id from public.inventory_items where sku = 'VOIDS-ITEM-2'),
        'issue_uom_id',
        (select id from public.units_of_measure where code = 'pc'),
        'issue_quantity', 6,
        'base_quantity_per_issue_unit', 1
      ))
    );
  $test$,
  'a second receipt is posted and partly released'
);

select throws_ok(
  $test$
    select public.void_goods_receipt(
      (
        select id from public.goods_receipts
        where supplier_invoice_number = 'VOIDS-GR-2'
      ),
      'Too late'
    )
  $test$,
  'P0001',
  'Some of this stock has already been sold, released or disposed. Correct the remainder by disposal or adjustment instead of voiding the receipt.',
  'a receipt cannot be voided once part of its stock has left'
);

-- Permissions -------------------------------------------------------------

set local request.jwt.claim.sub = '70000000-0000-0000-0000-000000000002';

select throws_ok(
  $test$
    select public.void_stock_out(
      '70000000-0000-0000-0000-0000000000ff', 'Not allowed'
    )
  $test$,
  'P0001',
  'Permission denied',
  'a cashier cannot void a stock release'
);

select throws_ok(
  $test$
    select public.void_goods_receipt(
      '70000000-0000-0000-0000-0000000000ff', 'Not allowed'
    )
  $test$,
  'P0001',
  'Permission denied',
  'a cashier cannot void a goods receipt'
);

-- Audit trail -------------------------------------------------------------

reset role;

select is(
  (
    select array_agg(action_code order by action_code)::text
    from (
      select distinct action_code
      from public.audit_logs
      where actor_user_id = '70000000-0000-0000-0000-000000000001'
        and action_code in (
          'SUPPLIER_UPDATED', 'EXPENSE_UPDATED', 'EXPENSE_VOIDED',
          'STOCK_OUT_VOIDED', 'STOCK_COUNT_VOIDED', 'GOODS_RECEIPT_VOIDED'
        )
    ) a
  ),
  '{EXPENSE_UPDATED,EXPENSE_VOIDED,GOODS_RECEIPT_VOIDED,STOCK_COUNT_VOIDED,STOCK_OUT_VOIDED,SUPPLIER_UPDATED}',
  'every correction left an audit record'
);

select is(
  (
    select row(old_data ->> 'amount', new_data ->> 'amount')::text
    from public.audit_logs
    where action_code = 'EXPENSE_UPDATED'
      and actor_user_id = '70000000-0000-0000-0000-000000000001'
  ),
  row('100.00', '150.00')::text,
  'the expense edit records the amount before and after'
);

select * from finish();

rollback;
