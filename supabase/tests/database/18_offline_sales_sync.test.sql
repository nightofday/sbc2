begin;

create extension if not exists pgtap with schema extensions;

select plan(16);

insert into auth.users (id, email)
values
  ('b0000000-0000-0000-0000-000000000001', 'offline-admin-db-test@example.com'),
  ('b0000000-0000-0000-0000-000000000002', 'offline-cashier-db-test@example.com');

delete from public.profiles
where id in (
  'b0000000-0000-0000-0000-000000000001',
  'b0000000-0000-0000-0000-000000000002'
);

insert into public.profiles (id, role_id, status, display_name)
values
  (
    'b0000000-0000-0000-0000-000000000001',
    (select id from public.roles where code = 'ADMIN'),
    'ACTIVE',
    'Offline Test Admin'
  ),
  (
    'b0000000-0000-0000-0000-000000000002',
    (select id from public.roles where code = 'CASHIER'),
    'ACTIVE',
    'Offline Test Cashier'
  );

set local role authenticated;
set local request.jwt.claim.role = 'authenticated';
set local request.jwt.claim.sub = 'b0000000-0000-0000-0000-000000000001';

-- A countable product with one piece in stock.
select lives_ok(
  $test$
    select public.create_inventory_item_with_initial_stock(
      'Offline Test Bar', null,
      (select id from public.units_of_measure where code = 'pc'),
      'OFFLINE-TEST-INV', false, 0, 1, null, 10
    );
    select public.create_menu_item_with_variant(
      'Offline Test Bar',
      (select id from public.menu_categories where name = 'Snacks'),
      'Regular', 'OFFLINE-TEST-SKU', 80, 'FINISHED_GOOD',
      (select id from public.inventory_items where sku = 'OFFLINE-TEST-INV')
    );
  $test$,
  'a stocked product is set up'
);

set local request.jwt.claim.sub = 'b0000000-0000-0000-0000-000000000002';

select lives_ok(
  $test$ select public.start_shift(null, 0) $test$,
  'the cashier opens a shift'
);

-- Three were sold while offline, 26 hours ago, with only one in stock.
select lives_ok(
  $test$
    select public.sync_offline_order(
      p_order_type := 'TAKE_OUT',
      p_items := jsonb_build_array(jsonb_build_object(
        'menu_variant_id',
        (select id from public.menu_variants where sku = 'OFFLINE-TEST-SKU'),
        'quantity', 3
      )),
      p_payment := jsonb_build_object(
        'payment_method_id',
        (select id from public.payment_methods where code = 'CASH'),
        'amount_tendered', 1000
      ),
      p_client_request_id := 'b0000000-0000-0000-0000-0000000000a1',
      p_sold_at := date_trunc('minute', now()) - interval '26 hours',
      p_client_total := 240,
      p_customer_name := 'Offline Test Sale'
    )
  $test$,
  'a sale made offline beyond the recorded stock is accepted'
);

select is(
  (
    select row(
      o.completed_at, o.created_at, p.processed_at, o.total_amount
    )::text
    from public.orders o
    join public.payments p on p.order_id = o.id
    where o.customer_name = 'Offline Test Sale'
  ),
  row(
    date_trunc('minute', now()) - interval '26 hours',
    date_trunc('minute', now()) - interval '26 hours',
    date_trunc('minute', now()) - interval '26 hours',
    240.00::numeric(14,2)
  )::text,
  'the order and its payment carry the time of the sale, not of the sync'
);

select is(
  (
    select row(current_quantity, usable_quantity)::text
    from public.v_inventory_stock
    where sku = 'OFFLINE-TEST-INV'
  ),
  row(-2::numeric(14,4), 0::numeric(14,4))::text,
  'the item goes negative so the shortfall is visible'
);

select is(
  (
    select bool_and(
      sm.created_at = date_trunc('minute', now()) - interval '26 hours'
    )
    from public.stock_movements sm
    join public.orders o on o.id = sm.order_id
    where o.customer_name = 'Offline Test Sale'
  ),
  true,
  'the stock movements carry the time of the sale'
);

select is(
  (
    select (public.sync_offline_order(
      p_order_type := 'TAKE_OUT',
      p_items := jsonb_build_array(jsonb_build_object(
        'menu_variant_id',
        (select id from public.menu_variants where sku = 'OFFLINE-TEST-SKU'),
        'quantity', 3
      )),
      p_payment := jsonb_build_object(
        'payment_method_id',
        (select id from public.payment_methods where code = 'CASH'),
        'amount_tendered', 1000
      ),
      p_client_request_id := 'b0000000-0000-0000-0000-0000000000a1',
      p_sold_at := date_trunc('minute', now()) - interval '26 hours',
      p_client_total := 240,
      p_customer_name := 'Offline Test Sale'
    )).id
  ),
  (select id from public.orders where customer_name = 'Offline Test Sale'),
  'sending the same sale again returns the stored order'
);

select is(
  (
    select row(
      (select count(*) from public.orders
        where customer_name = 'Offline Test Sale'),
      (select current_quantity from public.v_inventory_stock
        where sku = 'OFFLINE-TEST-INV')
    )::text
  ),
  row(1::bigint, -2::numeric(14,4))::text,
  'the repeated sync adds no order and deducts no more stock'
);

select throws_ok(
  $test$
    select public.place_order_v2(
      p_order_type := 'TAKE_OUT',
      p_items := jsonb_build_array(jsonb_build_object(
        'menu_variant_id',
        (select id from public.menu_variants where sku = 'OFFLINE-TEST-SKU'),
        'quantity', 1
      )),
      p_payment := jsonb_build_object(
        'payment_method_id',
        (select id from public.payment_methods where code = 'CASH'),
        'amount_tendered', 1000
      ),
      p_customer_name := 'Offline Test Live'
    )
  $test$,
  'P0001',
  null,
  'a live sale is still refused when there is no stock'
);

select throws_ok(
  $test$
    select public.sync_offline_order(
      p_order_type := 'TAKE_OUT',
      p_items := jsonb_build_array(jsonb_build_object(
        'menu_variant_id',
        (select id from public.menu_variants where sku = 'PRD-004'),
        'quantity', 1
      )),
      p_payment := jsonb_build_object(
        'payment_method_id',
        (select id from public.payment_methods where code = 'CASH'),
        'amount_tendered', 1000
      ),
      p_client_request_id := 'b0000000-0000-0000-0000-0000000000a2',
      p_sold_at := now() + interval '2 hours',
      p_customer_name := 'Offline Test Future'
    )
  $test$,
  'P0001',
  'The sale time is in the future. Check the device clock.',
  'a sale dated in the future is rejected'
);

select throws_ok(
  $test$
    select public.sync_offline_order(
      p_order_type := 'TAKE_OUT',
      p_items := jsonb_build_array(jsonb_build_object(
        'menu_variant_id',
        (select id from public.menu_variants where sku = 'PRD-004'),
        'quantity', 1
      )),
      p_payment := jsonb_build_object(
        'payment_method_id',
        (select id from public.payment_methods where code = 'CASH'),
        'amount_tendered', 1000
      ),
      p_client_request_id := 'b0000000-0000-0000-0000-0000000000a3',
      p_sold_at := now() - interval '8 days',
      p_customer_name := 'Offline Test Old'
    )
  $test$,
  'P0001',
  'This sale is more than 7 days old and must be entered by a manager.',
  'a sale more than 7 days old is rejected'
);

select throws_ok(
  $test$
    select public.sync_offline_order(
      p_order_type := 'TAKE_OUT',
      p_items := '[]'::jsonb,
      p_payment := '{}'::jsonb,
      p_client_request_id := null,
      p_sold_at := now()
    )
  $test$,
  'P0001',
  'An offline sale needs its request ID',
  'an offline sale without a request ID is rejected'
);

-- The till charged 100 from an old cached price; the menu now says more.
select lives_ok(
  $test$
    select public.sync_offline_order(
      p_order_type := 'TAKE_OUT',
      p_items := jsonb_build_array(jsonb_build_object(
        'menu_variant_id',
        (select id from public.menu_variants where sku = 'PRD-004'),
        'quantity', 1
      )),
      p_payment := jsonb_build_object(
        'payment_method_id',
        (select id from public.payment_methods where code = 'CASH'),
        'amount_tendered', 1000
      ),
      p_client_request_id := 'b0000000-0000-0000-0000-0000000000a4',
      p_sold_at := now() - interval '1 hour',
      p_client_total := 100,
      p_customer_name := 'Offline Test Price Change'
    )
  $test$,
  'a sale charged at an out-of-date price is still recorded'
);

reset role;

select is(
  (
    select (new_data ->> 'charged_at_till')::numeric
    from public.audit_logs
    where action_code = 'OFFLINE_SALE_TOTAL_DIFFERENCE'
      and actor_user_id = 'b0000000-0000-0000-0000-000000000002'
  ),
  100.00::numeric,
  'the difference between the till and the recorded total is audited'
);

select is(
  (
    select count(*) from public.audit_logs
    where action_code = 'OFFLINE_SALE_SYNCED'
      and actor_user_id = 'b0000000-0000-0000-0000-000000000002'
  ),
  2::bigint,
  'each offline sale is audited once, not on the repeated sync'
);

select ok(
  coalesce(current_setting('app.offline_sync', true), '') <> 'on',
  'the oversell allowance does not outlive the sync call'
);

select * from finish();

rollback;
