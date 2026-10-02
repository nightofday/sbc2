begin;

create extension if not exists pgtap with schema extensions;

select plan(9);

insert into auth.users (id, email)
values
  ('40000000-0000-0000-0000-000000000001', 'request-a-db-test@example.com'),
  ('40000000-0000-0000-0000-000000000002', 'request-b-db-test@example.com');

delete from public.profiles
where id in (
  '40000000-0000-0000-0000-000000000001',
  '40000000-0000-0000-0000-000000000002'
);

insert into public.profiles (id, role_id, status, display_name)
values
  (
    '40000000-0000-0000-0000-000000000001',
    (select id from public.roles where code = 'CASHIER'),
    'ACTIVE',
    'Request Test Cashier A'
  ),
  (
    '40000000-0000-0000-0000-000000000002',
    (select id from public.roles where code = 'CASHIER'),
    'ACTIVE',
    'Request Test Cashier B'
  );

set local role authenticated;
set local request.jwt.claim.role = 'authenticated';
set local request.jwt.claim.sub = '40000000-0000-0000-0000-000000000001';

select lives_ok(
  $test$ select public.start_shift(null, 0) $test$,
  'cashier A opens a shift'
);

select lives_ok(
  $test$
    select public.place_order_v2(
      p_order_type := 'TAKE_OUT',
      p_items := jsonb_build_array(
        jsonb_build_object(
          'menu_variant_id', (
            select variant_id
            from public.v_pos_menu
            where inventory_tracking_mode = 'UNTRACKED'
            order by sku
            limit 1
          ),
          'quantity', 1
        )
      ),
      p_payment := jsonb_build_object(
        'payment_method_id',
        (select id from public.payment_methods where code = 'CASH'),
        'amount_tendered', 1000
      ),
      p_customer_name := 'Request Test Customer',
      p_client_request_id := '40000000-0000-0000-0000-0000000000aa'
    )
  $test$,
  'the first submission places the order'
);

select is(
  (
    select (public.place_order_v2(
      p_order_type := 'TAKE_OUT',
      p_items := jsonb_build_array(
        jsonb_build_object(
          'menu_variant_id', (
            select variant_id
            from public.v_pos_menu
            where inventory_tracking_mode = 'UNTRACKED'
            order by sku
            limit 1
          ),
          'quantity', 1
        )
      ),
      p_payment := jsonb_build_object(
        'payment_method_id',
        (select id from public.payment_methods where code = 'CASH'),
        'amount_tendered', 1000
      ),
      p_customer_name := 'Request Test Customer',
      p_client_request_id := '40000000-0000-0000-0000-0000000000aa'
    )).id
  ),
  (
    select id
    from public.orders
    where client_request_id = '40000000-0000-0000-0000-0000000000aa'
  ),
  'a repeated submission returns the stored order'
);

select is(
  (
    select count(*)
    from public.orders
    where client_request_id = '40000000-0000-0000-0000-0000000000aa'
  ),
  1::bigint,
  'the retry does not create a second order'
);

select is(
  (
    select count(*)
    from public.payments p
    join public.orders o on o.id = p.order_id
    where o.client_request_id = '40000000-0000-0000-0000-0000000000aa'
  ),
  1::bigint,
  'the retry does not take a second payment'
);

reset role;

update public.orders
set status = 'REFUNDED', payment_status = 'REFUNDED'
where client_request_id = '40000000-0000-0000-0000-0000000000aa';

set local role authenticated;

select is(
  (
    select (public.place_order_v2(
      p_order_type := 'TAKE_OUT',
      p_items := jsonb_build_array(
        jsonb_build_object(
          'menu_variant_id', (
            select variant_id
            from public.v_pos_menu
            where inventory_tracking_mode = 'UNTRACKED'
            order by sku
            limit 1
          ),
          'quantity', 1
        )
      ),
      p_payment := jsonb_build_object(
        'payment_method_id',
        (select id from public.payment_methods where code = 'CASH'),
        'amount_tendered', 1000
      ),
      p_customer_name := 'Request Test Customer',
      p_client_request_id := '40000000-0000-0000-0000-0000000000aa'
    )).status
  ),
  'REFUNDED',
  'a sale refunded since is returned, not sold again'
);

set local request.jwt.claim.sub = '40000000-0000-0000-0000-000000000002';

-- create_order checks for an open shift before it looks at the request ID,
-- so cashier B needs one for the ownership check to be what is exercised.
select lives_ok(
  $test$ select public.start_shift(null, 0) $test$,
  'cashier B opens a shift'
);

select throws_ok(
  $test$
    select public.place_order_v2(
      p_order_type := 'TAKE_OUT',
      p_items := jsonb_build_array(
        jsonb_build_object(
          'menu_variant_id', (
            select variant_id
            from public.v_pos_menu
            where inventory_tracking_mode = 'UNTRACKED'
            order by sku
            limit 1
          ),
          'quantity', 1
        )
      ),
      p_payment := jsonb_build_object(
        'payment_method_id',
        (select id from public.payment_methods where code = 'CASH'),
        'amount_tendered', 1000
      ),
      p_customer_name := 'Someone Else',
      p_client_request_id := '40000000-0000-0000-0000-0000000000aa'
    )
  $test$,
  'P0001',
  'This request ID is not available',
  'another user cannot read or reuse the request through place_order_v2'
);

select throws_ok(
  $test$
    select public.create_order(
      p_order_type := 'TAKE_OUT',
      p_customer_name := 'Someone Else',
      p_client_request_id := '40000000-0000-0000-0000-0000000000aa'
    )
  $test$,
  'P0001',
  'This request ID is not available',
  'another user cannot read the order through create_order'
);

select * from finish();

rollback;
