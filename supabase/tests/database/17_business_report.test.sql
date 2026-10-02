begin;

create extension if not exists pgtap with schema extensions;

select plan(22);

insert into auth.users (id, email)
values
  ('a0000000-0000-0000-0000-000000000001', 'report-admin-db-test@example.com'),
  ('a0000000-0000-0000-0000-000000000002', 'report-cashier-db-test@example.com');

delete from public.profiles
where id in (
  'a0000000-0000-0000-0000-000000000001',
  'a0000000-0000-0000-0000-000000000002'
);

insert into public.profiles (id, role_id, status, display_name)
values
  (
    'a0000000-0000-0000-0000-000000000001',
    (select id from public.roles where code = 'ADMIN'),
    'ACTIVE',
    'Report Test Admin'
  ),
  (
    'a0000000-0000-0000-0000-000000000002',
    (select id from public.roles where code = 'CASHIER'),
    'ACTIVE',
    'Report Test Cashier'
  );

set local role authenticated;
set local request.jwt.claim.role = 'authenticated';
set local request.jwt.claim.sub = 'a0000000-0000-0000-0000-000000000001';

-- One discounted sale, later partly refunded, plus an expense.
select lives_ok(
  $test$
    select public.start_shift(null, 0);
    select public.create_discount_type('Report Test 10%', 'PERCENTAGE', 10);
    select public.place_order_v2(
      p_order_type := 'TAKE_OUT',
      p_items := jsonb_build_array(jsonb_build_object(
        'menu_variant_id',
        (select id from public.menu_variants where sku = 'PRD-004'),
        'quantity', 2
      )),
      p_payment := jsonb_build_object(
        'payment_method_id',
        (select id from public.payment_methods where code = 'CASH'),
        'amount_tendered', 5000
      ),
      p_discount := jsonb_build_object(
        'discount_type_id',
        (select id from public.discount_types where name = 'Report Test 10%')
      ),
      p_customer_name := 'Report Test Sale'
    );
    select public.process_refund_items(
      (select id from public.orders where customer_name = 'Report Test Sale'),
      (
        select jsonb_build_array(jsonb_build_object(
          'order_item_id', oi.id, 'quantity', 1
        ))
        from public.order_items oi
        join public.orders o on o.id = oi.order_id
        where o.customer_name = 'Report Test Sale'
      ),
      'Report test refund'
    );
    select public.create_supplier('Report Test Supplier');
    select public.create_expense(
      (select id from public.expense_categories where code = 'UTILITIES'),
      'Report test electricity', 300, date '2026-01-12', null,
      (select id from public.suppliers where name = 'Report Test Supplier'),
      'REPORT-TEST-EX-1'
    );
  $test$,
  'a discounted sale, a partial refund and an expense are recorded'
);

reset role;

-- Place them on known business days. The sale is at 00:30 Manila time on
-- 10 January, which is still 9 January in UTC.
update public.orders
set completed_at = timestamptz '2026-01-09 16:30:00+00'
where customer_name = 'Report Test Sale';

update public.payments p
set processed_at = case
  when p.transaction_type = 'PAYMENT' then timestamptz '2026-01-09 16:30:00+00'
  else timestamptz '2026-01-11 03:00:00+00'
end
from public.orders o
where o.id = p.order_id
  and o.customer_name = 'Report Test Sale';

update public.refunds r
set created_at = timestamptz '2026-01-11 03:00:00+00'
from public.orders o
where o.id = r.order_id
  and o.customer_name = 'Report Test Sale';

set local role authenticated;

create temp view report_all as
select public.get_business_report(date '2026-01-10', date '2026-01-12') as r;

create temp view report_day_one as
select public.get_business_report(date '2026-01-10', date '2026-01-10') as r;

create temp view report_day_two as
select public.get_business_report(date '2026-01-11', date '2026-01-11') as r;

create temp view report_before as
select public.get_business_report(date '2026-01-09', date '2026-01-09') as r;

select is(
  (select (r #>> '{summary,gross_sales}')::numeric from report_all),
  (
    select subtotal from public.orders
    where customer_name = 'Report Test Sale'
  ),
  'gross sales are the sale at menu prices, before the discount'
);

select is(
  (select (r #>> '{summary,discounts}')::numeric from report_all),
  (
    select round(subtotal * 0.10, 2) from public.orders
    where customer_name = 'Report Test Sale'
  ),
  'the discount is reported on its own line'
);

select is(
  (select (r #>> '{summary,refunds}')::numeric from report_all),
  (select total_amount from public.refunds where reason = 'Report test refund'),
  'the refund is reported on its own line'
);

select is(
  (select (r #>> '{summary,net_sales}')::numeric from report_all),
  (
    select o.subtotal - o.discount_amount - r.total_amount
    from public.orders o
    join public.refunds r on r.order_id = o.id
    where o.customer_name = 'Report Test Sale'
  ),
  'net sales are gross sales less discounts less refunds'
);

select is(
  (select (r #>> '{summary,orders}')::integer from report_before),
  0,
  'a sale at 00:30 Manila time is not counted on the previous day'
);

select is(
  (
    select row(
      (r #>> '{summary,orders}')::integer,
      (r #>> '{summary,refunds}')::numeric = 0
    )::text
    from report_day_one
  ),
  row(1, true)::text,
  'the sale belongs to its own business day, without the later refund'
);

select is(
  (
    select row(
      (r #>> '{summary,orders}')::integer,
      (r #>> '{summary,gross_sales}')::numeric = 0,
      (r #>> '{summary,refunds}')::numeric > 0,
      (r #>> '{summary,net_sales}')::numeric < 0
    )::text
    from report_day_two
  ),
  row(0, true, true, true)::text,
  'a day with only a refund shows the refund and a negative net'
);

select is(
  (
    select sum((d ->> 'net_sales')::numeric)
    from report_all, jsonb_array_elements(r -> 'by_day') d
  ),
  (select (r #>> '{summary,net_sales}')::numeric from report_all),
  'the daily rows add up to the summary'
);

select is(
  (select jsonb_array_length(r -> 'by_day') from report_all),
  3,
  'every day in the period has a row, including days with no sales'
);

select is(
  (
    select sum((i ->> 'net_sales')::numeric)
    from report_all, jsonb_array_elements(r -> 'by_item') i
  ),
  (select (r #>> '{summary,net_sales}')::numeric from report_all),
  'the item rows add up to the summary'
);

select is(
  (
    select sum((c ->> 'net_sales')::numeric)
    from report_all, jsonb_array_elements(r -> 'by_category') c
  ),
  (select (r #>> '{summary,net_sales}')::numeric from report_all),
  'the category rows add up to the summary'
);

select is(
  (
    select sum((p ->> 'net_collected')::numeric)
    from report_all, jsonb_array_elements(r -> 'by_payment_method') p
  ),
  (select (r #>> '{summary,net_sales}')::numeric from report_all),
  'money collected by payment method equals net sales'
);

select is(
  (
    select row(d ->> 'discount_name', (d ->> 'times_used')::integer)::text
    from report_all, jsonb_array_elements(r -> 'by_discount') d
  ),
  row('Report Test 10%', 1)::text,
  'the discount used is named'
);

select is(
  (
    select e ->> 'employee_name'
    from report_all, jsonb_array_elements(r -> 'by_employee') e
  ),
  'Report Test Admin',
  'sales are attributed to the employee who made them'
);

select is(
  (
    select row(
      (x ->> 'sold_on')::date, (x ->> 'reason')
    )::text
    from report_all, jsonb_array_elements(r -> 'refunds') x
  ),
  row(date '2026-01-10', 'Report test refund')::text,
  'the refund list shows the reason and the original sale day'
);

select is(
  (
    select row(
      (r #>> '{summary,expenses}')::numeric = 300,
      (r #>> '{summary,net_sales_less_expenses}')::numeric
        = (r #>> '{summary,net_sales}')::numeric - 300
    )::text
    from report_all
  ),
  row(true, true)::text,
  'expenses are shown and subtracted only in the clearly named line'
);

select is(
  (
    select row(
      (r #>> '{summary,orders}')::integer,
      (r #>> '{summary,expenses}')::numeric = 300
    )::text
    from public.get_business_report(date '2026-01-12', date '2026-01-12') as r
  ),
  row(0, true)::text,
  'a day with only an expense reports the expense and no sales'
);

select throws_ok(
  $test$
    select public.get_business_report(date '2026-01-12', date '2026-01-10')
  $test$,
  'P0001',
  'Choose a start date that is not after the end date',
  'a reversed period is rejected'
);

select throws_ok(
  $test$
    select public.get_business_report(date '2024-01-01', date '2026-01-10')
  $test$,
  'P0001',
  'A report can cover at most 366 days',
  'an overly long period is rejected'
);

select ok(
  (
    select bool_and(
      (m ->> 'closing')::numeric = (m ->> 'opening')::numeric
        + (m ->> 'received')::numeric - (m ->> 'sold')::numeric
        - (m ->> 'released')::numeric - (m ->> 'lost')::numeric
        + (m ->> 'other')::numeric
    )
    from public.get_business_report(
      public.business_today() - 30, public.business_today()
    ) as r,
    jsonb_array_elements(r -> 'stock_movement') m
  ) is not false,
  'for every stock item, opening plus movements equals closing'
);

set local request.jwt.claim.sub = 'a0000000-0000-0000-0000-000000000002';

select throws_ok(
  $test$
    select public.get_business_report(date '2026-01-10', date '2026-01-12')
  $test$,
  'P0001',
  'Permission denied',
  'a cashier cannot read the business report'
);

select * from finish();

rollback;
