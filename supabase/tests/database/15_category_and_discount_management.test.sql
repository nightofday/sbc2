begin;

create extension if not exists pgtap with schema extensions;

select plan(41);

insert into auth.users (id, email)
values
  ('80000000-0000-0000-0000-000000000001', 'catalog-admin-db-test@example.com'),
  ('80000000-0000-0000-0000-000000000002', 'catalog-cashier-db-test@example.com');

delete from public.profiles
where id in (
  '80000000-0000-0000-0000-000000000001',
  '80000000-0000-0000-0000-000000000002'
);

insert into public.profiles (id, role_id, status, display_name)
values
  (
    '80000000-0000-0000-0000-000000000001',
    (select id from public.roles where code = 'ADMIN'),
    'ACTIVE',
    'Catalog Test Admin'
  ),
  (
    '80000000-0000-0000-0000-000000000002',
    (select id from public.roles where code = 'CASHIER'),
    'ACTIVE',
    'Catalog Test Cashier'
  );

set local role authenticated;
set local request.jwt.claim.role = 'authenticated';
set local request.jwt.claim.sub = '80000000-0000-0000-0000-000000000001';

-- Categories --------------------------------------------------------------

select lives_ok(
  $test$ select public.create_category('MENU', 'Catalog Test Drinks') $test$,
  'a menu category is created'
);

select throws_ok(
  $test$ select public.create_category('MENU', '  catalog test DRINKS ') $test$,
  'P0001',
  'A category with this name already exists',
  'a name that differs only by case and spaces is a duplicate'
);

select throws_ok(
  $test$ select public.create_category('MENU', '   ') $test$,
  'P0001',
  'Category name is required',
  'a blank category name is rejected'
);

select throws_ok(
  $test$ select public.create_category('RECIPES', 'Anything') $test$,
  'P0001',
  'Unknown category type',
  'an unknown category type is rejected'
);

select lives_ok(
  $test$
    select public.update_category(
      'MENU',
      (select id from public.menu_categories where name = 'Catalog Test Drinks'),
      'Catalog Test Specials'
    )
  $test$,
  'a category is renamed'
);

select is(
  (
    select count(*) from public.menu_categories
    where name in ('Catalog Test Drinks', 'Catalog Test Specials')
  ),
  1::bigint,
  'renaming keeps one row with the same identity'
);

select lives_ok(
  $test$
    select public.update_category(
      'MENU',
      (
        select id from public.menu_categories
        where name = 'Catalog Test Specials'
      ),
      p_is_active := false
    )
  $test$,
  'a category is archived'
);

select throws_ok(
  $test$ select public.create_category('MENU', 'Catalog Test Specials') $test$,
  'P0001',
  'An archived category has this name. Reactivate it instead.',
  'an archived name is not created again'
);

select is(
  (
    select row(name, is_active)::text
    from public.list_categories('MENU')
    where name = 'Catalog Test Specials'
  ),
  row('Catalog Test Specials', false)::text,
  'the management list still shows the archived category'
);

select lives_ok(
  $test$
    select public.update_category(
      'MENU',
      (select id from public.menu_categories where name = 'Coffee'),
      p_is_active := false
    )
  $test$,
  'a category that has products can be archived'
);

select ok(
  (
    select count(*) from public.menu_items mi
    join public.menu_categories mc on mc.id = mi.category_id
    where mc.name = 'Coffee'
  ) > 0
  and (
    select usage_count from public.list_categories('MENU')
    where name = 'Coffee'
  ) > 0,
  'its products keep their category and the list reports them in use'
);

select lives_ok(
  $test$
    select public.update_category(
      'MENU',
      (select id from public.menu_categories where name = 'Coffee'),
      p_is_active := true
    );
    select public.reorder_categories(
      'MENU',
      array[
        (
          select id from public.menu_categories
          where name = 'Catalog Test Specials'
        ),
        (select id from public.menu_categories where name = 'Coffee')
      ]
    );
  $test$,
  'the category is reactivated and two categories are reordered'
);

select is(
  (
    select array_agg(name order by sort_order)::text
    from public.menu_categories
    where name in ('Coffee', 'Catalog Test Specials')
  ),
  '{"Catalog Test Specials",Coffee}',
  'the display order follows the order given'
);

select lives_ok(
  $test$
    select public.create_category('INVENTORY', 'Catalog Test Cleaning');
    select public.create_category('EXPENSE', 'Catalog Test Staff Meals');
    select public.create_category('EXPENSE', 'Catalog Test / Staff-Meals');
  $test$,
  'inventory and expense categories are created'
);

select is(
  (
    select count(*) from public.inventory_categories
    where name = 'Catalog Test Cleaning' and is_active
  ),
  1::bigint,
  'the inventory category is available to the inventory module'
);

select is(
  (
    select array_agg(code order by code)::text
    from public.expense_categories
    where name like 'Catalog Test%'
  ),
  '{CATALOG_TEST_STAFF_MEALS,CATALOG_TEST_STAFF_MEALS_2}',
  'expense categories receive distinct stable codes'
);

select is(
  (
    select count(*) from public.audit_logs
    where actor_user_id = '80000000-0000-0000-0000-000000000001'
      and action_code in ('CATEGORY_CREATED', 'CATEGORY_UPDATED')
  ),
  8::bigint,
  'category changes are audited'
);

-- Promotional discounts ---------------------------------------------------

select is(
  (
    select count(*) from public.get_pos_discount_types()
    where code in ('PROMO_PERCENT', 'PROMO_FIXED', 'MANUAL')
      and allow_custom_value
  ),
  3::bigint,
  'the three discounts the till already offered are still offered'
);

select lives_ok(
  $test$
    select public.create_discount_type(
      'Catalog Test Opening Week', 'PERCENTAGE', 10
    )
  $test$,
  'a fixed 10% promotion is created'
);

select throws_ok(
  $test$
    select public.create_discount_type(
      ' catalog test opening WEEK', 'PERCENTAGE', 5
    )
  $test$,
  'P0001',
  'A discount with this name already exists',
  'a duplicate discount name is rejected'
);

select throws_ok(
  $test$
    select public.create_discount_type('Catalog Test Too Big', 'PERCENTAGE', 120)
  $test$,
  'P0001',
  'A percentage discount cannot be more than 100',
  'a percentage above 100 is rejected'
);

select throws_ok(
  $test$
    select public.create_discount_type('Catalog Test Zero', 'FIXED_AMOUNT', 0)
  $test$,
  'P0001',
  'Discount value must be greater than zero',
  'a zero discount is rejected'
);

select is(
  (
    select allow_custom_value = false and default_value = 10
    from public.get_pos_discount_types()
    where name = 'Catalog Test Opening Week'
  ),
  true,
  'the new promotion is offered at the till with its fixed value'
);

select lives_ok(
  $test$ select public.start_shift(null, 0) $test$,
  'a shift is opened'
);

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
        'quantity', 1
      )),
      p_payment := jsonb_build_object(
        'payment_method_id',
        (select id from public.payment_methods where code = 'CASH'),
        'amount_tendered', 5000
      ),
      p_discount := jsonb_build_object(
        'discount_type_id', (
          select id from public.discount_types
          where name = 'Catalog Test Opening Week'
        ),
        'manual_value', 90
      ),
      p_customer_name := 'Catalog Test Fixed Promo'
    )
  $test$,
  'an order uses the promotion while the client sends a different value'
);

select is(
  (
    select discount_amount
    from public.orders
    where customer_name = 'Catalog Test Fixed Promo'
  ),
  (
    select round(subtotal * 0.10, 2)
    from public.orders
    where customer_name = 'Catalog Test Fixed Promo'
  ),
  'the server applies the defined 10%, not the value the client sent'
);

select lives_ok(
  $test$
    select public.create_discount_type(
      'Catalog Test Goodwill', 'FIXED_AMOUNT', 20, true, 50
    )
  $test$,
  'a promotion with an adjustable value and a maximum is created'
);

select throws_ok(
  $test$
    select public.place_order_v2(
      p_order_type := 'TAKE_OUT',
      p_items := jsonb_build_array(jsonb_build_object(
        'menu_variant_id', (
          select variant_id from public.v_pos_menu
          where inventory_tracking_mode = 'UNTRACKED'
          order by sku limit 1
        ),
        'quantity', 1
      )),
      p_payment := jsonb_build_object(
        'payment_method_id',
        (select id from public.payment_methods where code = 'CASH'),
        'amount_tendered', 5000
      ),
      p_discount := jsonb_build_object(
        'discount_type_id', (
          select id from public.discount_types
          where name = 'Catalog Test Goodwill'
        ),
        'manual_value', 80
      ),
      p_customer_name := 'Catalog Test Over Max'
    )
  $test$,
  'P0001',
  'This discount cannot be more than 50',
  'a value above the promotion maximum is rejected at checkout'
);

select lives_ok(
  $test$
    select public.create_discount_type(
      'Catalog Test Next Month', 'PERCENTAGE', 5, false, null,
      public.business_today() + 10, public.business_today() + 40
    )
  $test$,
  'a promotion that starts later is created'
);

select is(
  (
    select count(*) from public.get_pos_discount_types()
    where name = 'Catalog Test Next Month'
  ),
  0::bigint,
  'a promotion outside its dates is not offered at the till'
);

select throws_ok(
  $test$
    select public.place_order_v2(
      p_order_type := 'TAKE_OUT',
      p_items := jsonb_build_array(jsonb_build_object(
        'menu_variant_id', (
          select variant_id from public.v_pos_menu
          where inventory_tracking_mode = 'UNTRACKED'
          order by sku limit 1
        ),
        'quantity', 1
      )),
      p_payment := jsonb_build_object(
        'payment_method_id',
        (select id from public.payment_methods where code = 'CASH'),
        'amount_tendered', 5000
      ),
      p_discount := jsonb_build_object(
        'discount_type_id', (
          select id from public.discount_types
          where name = 'Catalog Test Next Month'
        )
      ),
      p_customer_name := 'Catalog Test Not Yet Valid'
    )
  $test$,
  'P0001',
  'This discount is not valid today',
  'checkout rejects a promotion outside its dates'
);

select lives_ok(
  $test$
    select public.update_discount_type(
      (
        select id from public.discount_types
        where name = 'Catalog Test Opening Week'
      ),
      'Catalog Test Opening Week', 10, false, null, null, null, false
    )
  $test$,
  'the promotion is deactivated'
);

select is(
  (
    select count(*) from public.get_pos_discount_types()
    where name = 'Catalog Test Opening Week'
  ),
  0::bigint,
  'a deactivated promotion is no longer offered'
);

select is(
  (
    select discount_amount > 0
    from public.orders
    where customer_name = 'Catalog Test Fixed Promo'
  ),
  true,
  'the order that used it keeps its discount'
);

select throws_ok(
  $test$
    select public.update_discount_type(
      (select id from public.discount_types where code = 'SENIOR'),
      'Senior Citizen', 20, false, null, null, null, true
    )
  $test$,
  'P0001',
  'Statutory discounts are not managed here until their rules are confirmed',
  'statutory discounts cannot be edited here'
);

select throws_ok(
  $test$
    select public.place_order_v2(
      p_order_type := 'TAKE_OUT',
      p_items := jsonb_build_array(jsonb_build_object(
        'menu_variant_id', (
          select variant_id from public.v_pos_menu
          where inventory_tracking_mode = 'UNTRACKED'
          order by sku limit 1
        ),
        'quantity', 1
      )),
      p_payment := jsonb_build_object(
        'payment_method_id',
        (select id from public.payment_methods where code = 'CASH'),
        'amount_tendered', 5000
      ),
      p_discount := jsonb_build_object(
        'discount_type_id',
        (select id from public.discount_types where code = 'SENIOR')
      ),
      p_customer_name := 'Catalog Test Senior'
    )
  $test$,
  'P0001',
  'This discount type is not enabled in POS until business rules are confirmed',
  'statutory discounts still cannot be used at the till'
);

-- Permissions -------------------------------------------------------------

set local request.jwt.claim.sub = '80000000-0000-0000-0000-000000000002';

select throws_ok(
  $test$ select public.create_category('MENU', 'Cashier Category') $test$,
  'P0001',
  'Permission denied',
  'a cashier cannot create a category'
);

select throws_ok(
  $test$ select * from public.list_categories('EXPENSE') $test$,
  'P0001',
  'Permission denied',
  'a cashier cannot open expense category management'
);

select throws_ok(
  $test$
    select public.create_discount_type('Cashier Promo', 'PERCENTAGE', 50)
  $test$,
  'P0001',
  'Permission denied',
  'a cashier cannot create a discount'
);

select is(
  (select count(*) from public.get_pos_discount_types()),
  0::bigint,
  'a cashier is still offered no discounts: that policy is unchanged'
);

reset role;

select ok(
  not exists (
    select 1 from public.discount_types
    where is_pos_enabled and (requires_id or is_tax_exempt_related)
  ),
  'no statutory discount is enabled for the till'
);

select * from finish();

rollback;
