begin;

create extension if not exists pgtap with schema extensions;

select plan(12);

insert into auth.users (id, email)
values
  (
    '70000000-0000-0000-0000-000000000001',
    'phase-seven-manager@example.com'
  ),
  (
    '70000000-0000-0000-0000-000000000002',
    'phase-seven-cashier@example.com'
  );

delete from public.profiles
where id in (
  '70000000-0000-0000-0000-000000000001',
  '70000000-0000-0000-0000-000000000002'
);

insert into public.profiles (id, role_id, status, display_name)
values
  (
    '70000000-0000-0000-0000-000000000001',
    (select id from public.roles where code = 'MANAGER'),
    'ACTIVE',
    'Phase Seven Manager'
  ),
  (
    '70000000-0000-0000-0000-000000000002',
    (select id from public.roles where code = 'CASHIER'),
    'ACTIVE',
    'Phase Seven Cashier'
  );

insert into public.menu_categories (id, name, sort_order)
values (
  '70000000-0000-0000-0000-000000000010',
  'Phase Seven Products',
  997
);

insert into public.menu_items (id, name, category_id)
values (
  '70000000-0000-0000-0000-000000000011',
  'Phase Seven Bowl',
  '70000000-0000-0000-0000-000000000010'
);

insert into public.menu_variants (
  id, menu_item_id, sku, name, price, is_default
)
values (
  '70000000-0000-0000-0000-000000000012',
  '70000000-0000-0000-0000-000000000011',
  'PHASE7-BOWL',
  'Regular',
  100,
  true
);

insert into public.orders (
  id, order_number, order_type, status, payment_status,
  created_by_user_id, employee_name_snapshot, customer_name,
  subtotal, total_amount, completed_at
)
values (
  '70000000-0000-0000-0000-000000000020',
  7001,
  'TAKE_OUT',
  'PARTIALLY_REFUNDED',
  'PARTIALLY_REFUNDED',
  '70000000-0000-0000-0000-000000000001',
  'Phase Seven Manager',
  'Trace Customer',
  200,
  200,
  now()
);

insert into public.order_items (
  id, order_id, menu_item_id, menu_variant_id,
  item_name_snapshot, variant_name_snapshot, quantity, unit_price,
  line_subtotal, line_total
)
values (
  '70000000-0000-0000-0000-000000000021',
  '70000000-0000-0000-0000-000000000020',
  '70000000-0000-0000-0000-000000000011',
  '70000000-0000-0000-0000-000000000012',
  'Phase Seven Bowl',
  'Regular',
  2,
  100,
  200,
  200
);

insert into public.payments (
  id, order_id, payment_method_id, transaction_type, status,
  amount, external_reference, processed_by
)
values (
  '70000000-0000-0000-0000-000000000022',
  '70000000-0000-0000-0000-000000000020',
  (select id from public.payment_methods where code = 'GCASH'),
  'PAYMENT',
  'COMPLETED',
  200,
  'SALE-TRACE-7001',
  '70000000-0000-0000-0000-000000000001'
);

insert into public.refunds (
  id, refund_number, order_id, refund_type, status, reason,
  total_amount, requested_by, authorized_by
)
values (
  '70000000-0000-0000-0000-000000000023',
  7001,
  '70000000-0000-0000-0000-000000000020',
  'PARTIAL',
  'COMPLETED',
  'Customer returned part of the order',
  50,
  '70000000-0000-0000-0000-000000000001',
  '70000000-0000-0000-0000-000000000001'
);

insert into public.refund_items (
  id, refund_id, order_item_id, quantity, refund_amount
)
values (
  '70000000-0000-0000-0000-000000000024',
  '70000000-0000-0000-0000-000000000023',
  '70000000-0000-0000-0000-000000000021',
  0.5,
  50
);

insert into public.suppliers (id, supplier_code, name)
values (
  '70000000-0000-0000-0000-000000000030',
  'PHASE7-GROCERY',
  'Phase Seven Grocery'
);

insert into public.expenses (
  id, expense_number, expense_date, expense_category_id, expense_type,
  description, amount, supplier_id, reference_number, status, recorded_by
)
values (
  '70000000-0000-0000-0000-000000000031',
  7001,
  current_date,
  (select id from public.expense_categories where code = 'OTHER'),
  'OPERATING',
  'Phase Seven traceable expense',
  75,
  '70000000-0000-0000-0000-000000000030',
  'EXP-TRACE-7001',
  'POSTED',
  '70000000-0000-0000-0000-000000000001'
);

set local role authenticated;
set local request.jwt.claim.role = 'authenticated';
set local request.jwt.claim.sub = '70000000-0000-0000-0000-000000000001';

-- The period report is the one place product sales are defined.
create temporary table phase_seven_item on commit drop as
select item.value as row
from jsonb_array_elements(
  public.get_business_report(
    public.business_today(), public.business_today()
  ) -> 'by_item'
) as item
where item.value ->> 'item_name' = 'Phase Seven Bowl';

select is(
  (select (row ->> 'quantity_sold')::numeric from phase_seven_item),
  2.0000::numeric,
  'period product reporting preserves gross quantity sold'
);

select is(
  (select (row ->> 'quantity_refunded')::numeric from phase_seven_item),
  0.5000::numeric,
  'period product reporting exposes refunded quantity'
);

select is(
  (
    select (row ->> 'quantity_sold')::numeric
      - (row ->> 'quantity_refunded')::numeric
    from phase_seven_item
  ),
  1.5000::numeric,
  'period product reporting calculates net quantity sold'
);

select is(
  (select (row ->> 'net_sales')::numeric from phase_seven_item),
  150.00::numeric,
  'period product reporting subtracts line refunds'
);

select is(
  (
    select count(*)
    from public.v_business_transaction_trace
    where event_key in (
      'SALE:70000000-0000-0000-0000-000000000020',
      'REFUND:70000000-0000-0000-0000-000000000023',
      'EXPENSE:70000000-0000-0000-0000-000000000031'
    )
  ),
  3::bigint,
  'management sees the linked sale, refund and expense trace records'
);

select is(
  (
    select document_number
    from public.v_business_transaction_trace
    where event_key = 'SALE:70000000-0000-0000-0000-000000000020'
  ),
  'ORD-7001',
  'sale trace uses a readable order document number'
);

select is(
  (
    select external_reference
    from public.v_business_transaction_trace
    where event_key = 'SALE:70000000-0000-0000-0000-000000000020'
  ),
  'SALE-TRACE-7001',
  'sale trace preserves the payment reference'
);

select is(
  (
    select amount
    from public.v_business_transaction_trace
    where event_key = 'REFUND:70000000-0000-0000-0000-000000000023'
  ),
  (-50.00)::numeric,
  'refund trace exposes a negative amount'
);

select is(
  (
    select document_number
    from public.v_business_transaction_trace
    where event_key = 'EXPENSE:70000000-0000-0000-0000-000000000031'
  ),
  'EX-7001',
  'expense trace uses a readable expense number'
);

select is(
  (
    select external_reference
    from public.v_business_transaction_trace
    where event_key = 'EXPENSE:70000000-0000-0000-0000-000000000031'
  ),
  'EXP-TRACE-7001',
  'expense trace preserves the grocery receipt reference'
);

select is(
  (
    select actor_name
    from public.v_business_transaction_trace
    where event_key = 'EXPENSE:70000000-0000-0000-0000-000000000031'
  ),
  'Phase Seven Manager',
  'trace records identify the responsible employee'
);

set local request.jwt.claim.sub = '70000000-0000-0000-0000-000000000002';

select is(
  (
    select count(*)
    from public.v_business_transaction_trace
    where event_key in (
      'SALE:70000000-0000-0000-0000-000000000020',
      'REFUND:70000000-0000-0000-0000-000000000023',
      'EXPENSE:70000000-0000-0000-0000-000000000031'
    )
  ),
  0::bigint,
  'cashiers cannot read the management traceability report'
);

select * from finish();
rollback;
