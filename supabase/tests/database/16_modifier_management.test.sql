begin;

create extension if not exists pgtap with schema extensions;

select plan(23);

insert into auth.users (id, email)
values
  ('90000000-0000-0000-0000-000000000001', 'modifier-admin-db-test@example.com'),
  ('90000000-0000-0000-0000-000000000002', 'modifier-cashier-db-test@example.com');

delete from public.profiles
where id in (
  '90000000-0000-0000-0000-000000000001',
  '90000000-0000-0000-0000-000000000002'
);

insert into public.profiles (id, role_id, status, display_name)
values
  (
    '90000000-0000-0000-0000-000000000001',
    (select id from public.roles where code = 'ADMIN'),
    'ACTIVE',
    'Modifier Test Admin'
  ),
  (
    '90000000-0000-0000-0000-000000000002',
    (select id from public.roles where code = 'CASHIER'),
    'ACTIVE',
    'Modifier Test Cashier'
  );

set local role authenticated;
set local request.jwt.claim.role = 'authenticated';
set local request.jwt.claim.sub = '90000000-0000-0000-0000-000000000001';

select lives_ok(
  $test$
    select public.start_shift(null, 0)
  $test$,
  'a shift is opened'
);

select lives_ok(
  $test$
    select public.create_modifier_group_for_menu_item(
      (select menu_item_id from public.menu_variants where sku = 'PRD-003'), 'Mod Test Size', 1, 1, true
    )
  $test$,
  'a required group is created for one product'
);

select lives_ok(
  $test$
    select public.create_modifier_group_for_menu_item(
      (select menu_item_id from public.menu_variants where sku = 'PRD-004'), 'Mod Test Size', 1, 1, true
    )
  $test$,
  'a second product can have its own group with the same name'
);

select lives_ok(
  $test$
    select public.create_modifier((
        select mig.modifier_group_id
        from public.menu_item_modifier_groups mig
        join public.modifier_groups mg on mg.id = mig.modifier_group_id
        where mig.menu_item_id = (select menu_item_id from public.menu_variants where sku = 'PRD-003')
          and mg.name = 'Mod Test Size'
      ), 'Mod Test Large', 20);
    select public.create_modifier((
        select mig.modifier_group_id
        from public.menu_item_modifier_groups mig
        join public.modifier_groups mg on mg.id = mig.modifier_group_id
        where mig.menu_item_id = (select menu_item_id from public.menu_variants where sku = 'PRD-003')
          and mg.name = 'Mod Test Size'
      ), 'Mod Test Regular', 0);
  $test$,
  'a priced and a free option are added'
);

select throws_ok(
  $test$
    select public.place_order_v2(
      p_order_type := 'TAKE_OUT',
      p_items := jsonb_build_array(jsonb_build_object(
        'menu_variant_id',
        (select id from public.menu_variants where sku = 'PRD-003'),
        'quantity', 1,
        'modifier_ids', jsonb_build_array()
      )),
      p_payment := jsonb_build_object(
        'payment_method_id',
        (select id from public.payment_methods where code = 'CASH'),
        'amount_tendered', 5000
      ),
      p_customer_name := 'Mod Test None'
    )
  $test$,
  'P0001',
  'Modifier group "Mod Test Size" requires at least 1 selection(s)',
  'checkout is refused when a required choice is missing'
);

select throws_ok(
  $test$
    select public.place_order_v2(
      p_order_type := 'TAKE_OUT',
      p_items := jsonb_build_array(jsonb_build_object(
        'menu_variant_id',
        (select id from public.menu_variants where sku = 'PRD-003'),
        'quantity', 1,
        'modifier_ids', jsonb_build_array((
            select m.id from public.modifiers m
            where m.name = 'Mod Test Large' and m.modifier_group_id = (
        select mig.modifier_group_id
        from public.menu_item_modifier_groups mig
        join public.modifier_groups mg on mg.id = mig.modifier_group_id
        where mig.menu_item_id = (select menu_item_id from public.menu_variants where sku = 'PRD-003')
          and mg.name = 'Mod Test Size'
      )
          ), (
            select m.id from public.modifiers m
            where m.name = 'Mod Test Regular' and m.modifier_group_id = (
        select mig.modifier_group_id
        from public.menu_item_modifier_groups mig
        join public.modifier_groups mg on mg.id = mig.modifier_group_id
        where mig.menu_item_id = (select menu_item_id from public.menu_variants where sku = 'PRD-003')
          and mg.name = 'Mod Test Size'
      )
          ))
      )),
      p_payment := jsonb_build_object(
        'payment_method_id',
        (select id from public.payment_methods where code = 'CASH'),
        'amount_tendered', 5000
      ),
      p_customer_name := 'Mod Test Both'
    )
  $test$,
  'P0001',
  'Modifier group "Mod Test Size" allows at most 1 selection(s)',
  'checkout is refused when more than the limit is chosen'
);

select lives_ok(
  $test$
    select public.place_order_v2(
      p_order_type := 'TAKE_OUT',
      p_items := jsonb_build_array(jsonb_build_object(
        'menu_variant_id',
        (select id from public.menu_variants where sku = 'PRD-003'),
        'quantity', 1,
        'modifier_ids', jsonb_build_array((
            select m.id from public.modifiers m
            where m.name = 'Mod Test Large' and m.modifier_group_id = (
        select mig.modifier_group_id
        from public.menu_item_modifier_groups mig
        join public.modifier_groups mg on mg.id = mig.modifier_group_id
        where mig.menu_item_id = (select menu_item_id from public.menu_variants where sku = 'PRD-003')
          and mg.name = 'Mod Test Size'
      )
          ))
      )),
      p_payment := jsonb_build_object(
        'payment_method_id',
        (select id from public.payment_methods where code = 'CASH'),
        'amount_tendered', 5000
      ),
      p_customer_name := 'Mod Test One'
    )
  $test$,
  'checkout succeeds with one choice'
);

select is(
  (
    select row(oim.modifier_name_snapshot, oim.price_delta)::text
    from public.order_item_modifiers oim
    join public.order_items oi on oi.id = oim.order_item_id
    join public.orders o on o.id = oi.order_id
    where o.customer_name = 'Mod Test One'
  ),
  row('Mod Test Large', 20.00::numeric(14,2))::text,
  'the order line records the option name and price'
);

select lives_ok(
  $test$
    select public.place_order_v2(
      p_order_type := 'TAKE_OUT',
      p_items := jsonb_build_array(jsonb_build_object(
        'menu_variant_id',
        (select id from public.menu_variants where sku = 'PRD-004'),
        'quantity', 1,
        'modifier_ids', jsonb_build_array()
      )),
      p_payment := jsonb_build_object(
        'payment_method_id',
        (select id from public.payment_methods where code = 'CASH'),
        'amount_tendered', 5000
      ),
      p_customer_name := 'Mod Test Empty Group'
    )
  $test$,
  'a required group with no options does not block the sale'
);

select lives_ok(
  $test$
    select public.attach_modifier_group(
      (select menu_item_id from public.menu_variants where sku = 'PRD-007'),
      (
        select mig.modifier_group_id
        from public.menu_item_modifier_groups mig
        join public.modifier_groups mg on mg.id = mig.modifier_group_id
        where mig.menu_item_id = (select menu_item_id from public.menu_variants where sku = 'PRD-003')
          and mg.name = 'Mod Test Size'
      )
    )
  $test$,
  'the group is used on another product'
);

select is(
  (
    select count(*) from public.v_pos_modifiers
    where menu_item_id = (select menu_item_id from public.menu_variants where sku = 'PRD-007')
  ),
  2::bigint,
  'the other product now offers the same two options'
);

select is(
  (
    select row(product_count, product_names like '%Cookie%')::text
    from public.v_modifier_group_library
    where modifier_group_id = (
        select mig.modifier_group_id
        from public.menu_item_modifier_groups mig
        join public.modifier_groups mg on mg.id = mig.modifier_group_id
        where mig.menu_item_id = (select menu_item_id from public.menu_variants where sku = 'PRD-003')
          and mg.name = 'Mod Test Size'
      )
  ),
  row(2, true)::text,
  'the library shows which products share the group'
);

select is(
  (
    select distinct group_product_count
    from public.v_menu_modifier_management
    where modifier_group_id = (
        select mig.modifier_group_id
        from public.menu_item_modifier_groups mig
        join public.modifier_groups mg on mg.id = mig.modifier_group_id
        where mig.menu_item_id = (select menu_item_id from public.menu_variants where sku = 'PRD-003')
          and mg.name = 'Mod Test Size'
      )
  ),
  2,
  'the management view reports the group as shared'
);

select lives_ok(
  $test$
    select public.update_modifier(
      (
            select m.id from public.modifiers m
            where m.name = 'Mod Test Large' and m.modifier_group_id = (
        select mig.modifier_group_id
        from public.menu_item_modifier_groups mig
        join public.modifier_groups mg on mg.id = mig.modifier_group_id
        where mig.menu_item_id = (select menu_item_id from public.menu_variants where sku = 'PRD-003')
          and mg.name = 'Mod Test Size'
      )
          ),
      'Mod Test Large', 25, true
    )
  $test$,
  'the shared option price is changed'
);

select is(
  (
    select oim.price_delta
    from public.order_item_modifiers oim
    join public.order_items oi on oi.id = oim.order_item_id
    join public.orders o on o.id = oi.order_id
    where o.customer_name = 'Mod Test One'
  ),
  20.00::numeric(14,2),
  'the earlier order keeps the price it was sold at'
);

select lives_ok(
  $test$
    select public.reorder_modifiers(
      (
        select mig.modifier_group_id
        from public.menu_item_modifier_groups mig
        join public.modifier_groups mg on mg.id = mig.modifier_group_id
        where mig.menu_item_id = (select menu_item_id from public.menu_variants where sku = 'PRD-003')
          and mg.name = 'Mod Test Size'
      ),
      array[
        (
            select m.id from public.modifiers m
            where m.name = 'Mod Test Regular' and m.modifier_group_id = (
        select mig.modifier_group_id
        from public.menu_item_modifier_groups mig
        join public.modifier_groups mg on mg.id = mig.modifier_group_id
        where mig.menu_item_id = (select menu_item_id from public.menu_variants where sku = 'PRD-003')
          and mg.name = 'Mod Test Size'
      )
          ),
        (
            select m.id from public.modifiers m
            where m.name = 'Mod Test Large' and m.modifier_group_id = (
        select mig.modifier_group_id
        from public.menu_item_modifier_groups mig
        join public.modifier_groups mg on mg.id = mig.modifier_group_id
        where mig.menu_item_id = (select menu_item_id from public.menu_variants where sku = 'PRD-003')
          and mg.name = 'Mod Test Size'
      )
          )
      ]
    )
  $test$,
  'the options are reordered'
);

select is(
  (
    select modifier_name from public.v_pos_modifiers
    where menu_item_id = (select menu_item_id from public.menu_variants where sku = 'PRD-003')
    order by modifier_sort_order
    limit 1
  ),
  'Mod Test Regular',
  'the till offers the options in the new order'
);

select lives_ok(
  $test$
    select public.detach_modifier_group(
      (select menu_item_id from public.menu_variants where sku = 'PRD-007'),
      (
        select mig.modifier_group_id
        from public.menu_item_modifier_groups mig
        join public.modifier_groups mg on mg.id = mig.modifier_group_id
        where mig.menu_item_id = (select menu_item_id from public.menu_variants where sku = 'PRD-003')
          and mg.name = 'Mod Test Size'
      )
    )
  $test$,
  'the group is taken off the other product'
);

select is(
  (
    select count(*) from public.v_pos_modifiers
    where menu_item_id = (select menu_item_id from public.menu_variants where sku = 'PRD-007')
  ),
  0::bigint,
  'that product no longer offers the options'
);

select throws_ok(
  $test$
    select public.detach_modifier_group(
      (select menu_item_id from public.menu_variants where sku = 'PRD-007'),
      (
        select mig.modifier_group_id
        from public.menu_item_modifier_groups mig
        join public.modifier_groups mg on mg.id = mig.modifier_group_id
        where mig.menu_item_id = (select menu_item_id from public.menu_variants where sku = 'PRD-003')
          and mg.name = 'Mod Test Size'
      )
    )
  $test$,
  'P0001',
  'This product does not use that modifier group',
  'a group that is not attached cannot be detached'
);

select lives_ok(
  $test$
    select public.update_modifier(
      (
            select m.id from public.modifiers m
            where m.name = 'Mod Test Regular' and m.modifier_group_id = (
        select mig.modifier_group_id
        from public.menu_item_modifier_groups mig
        join public.modifier_groups mg on mg.id = mig.modifier_group_id
        where mig.menu_item_id = (select menu_item_id from public.menu_variants where sku = 'PRD-003')
          and mg.name = 'Mod Test Size'
      )
          ),
      'Mod Test Regular', 0, false
    )
  $test$,
  'an option is switched off'
);

select is(
  (
    select count(*) from public.v_pos_modifiers
    where menu_item_id = (select menu_item_id from public.menu_variants where sku = 'PRD-003')
  ),
  1::bigint,
  'a switched-off option is not offered at the till'
);

set local request.jwt.claim.sub = '90000000-0000-0000-0000-000000000002';

select throws_ok(
  $test$
    select public.attach_modifier_group(
      (select menu_item_id from public.menu_variants where sku = 'PRD-007'),
      '90000000-0000-0000-0000-0000000000ff'
    )
  $test$,
  'P0001',
  'Permission denied',
  'a cashier cannot change modifier groups'
);

select * from finish();

rollback;
