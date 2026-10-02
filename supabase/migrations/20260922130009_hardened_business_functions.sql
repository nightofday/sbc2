-- 0009_hardened_business_functions.sql
-- Trusted RPC entry points for pricing, checkout, inventory receiving, supplier payment and refunds.

-- ============================================================
-- Helpers
-- ============================================================

create or replace function public.assert_active_order_access(p_order_id uuid)
returns public.orders
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_order public.orders%rowtype;
begin
  select * into v_order
  from public.orders
  where id = p_order_id;

  if not found then
    raise exception 'Order not found';
  end if;

  if not (
    v_order.created_by_user_id = auth.uid()
    or public.has_permission('orders.manage_all')
  ) then
    raise exception 'Permission denied for this order';
  end if;

  return v_order;
end;
$$;

revoke all on function public.assert_active_order_access(uuid) from public;

-- ============================================================
-- Order creation and line-item pricing
-- ============================================================

create or replace function public.create_order(
  p_order_type text,
  p_table_number text default null,
  p_customer_name text default null,
  p_source_code text default 'POS',
  p_delivery_provider text default null,
  p_delivery_reference text default null,
  p_delivery_contact_name text default null,
  p_delivery_phone text default null,
  p_delivery_address text default null,
  p_notes text default null,
  p_device_id uuid default null,
  p_client_request_id uuid default null
)
returns public.orders
language plpgsql
security definer
set search_path = public
as $$
declare
  v_shift_id uuid;
  v_profile public.profiles%rowtype;
  v_order public.orders%rowtype;
begin
  if not public.has_permission('orders.create') then
    raise exception 'Permission denied';
  end if;

  select * into v_profile
  from public.profiles
  where id = auth.uid() and status = 'ACTIVE';

  if not found then
    raise exception 'Active employee profile required';
  end if;

  v_shift_id := public.current_open_shift_id();

  if v_shift_id is null then
    raise exception 'An active shift is required before creating an order';
  end if;

  p_order_type := upper(btrim(p_order_type));
  p_source_code := upper(btrim(coalesce(p_source_code,'POS')));

  if p_order_type not in ('DINE_IN','TAKE_OUT','DELIVERY') then
    raise exception 'Invalid order type';
  end if;

  if p_source_code not in ('POS','MANUAL_DELIVERY','PHONE','OTHER') then
    raise exception 'Invalid source code';
  end if;

  if p_order_type = 'DINE_IN'
     and nullif(btrim(coalesce(p_table_number,'')), '') is null then
    raise exception 'Table number is required for dine-in orders';
  end if;

  if p_client_request_id is not null then
    select * into v_order
    from public.orders
    where client_request_id = p_client_request_id;

    if found then
      return v_order;
    end if;
  end if;

  insert into public.orders(
    client_request_id,
    order_type,
    source_code,
    created_by_user_id,
    employee_name_snapshot,
    shift_id,
    device_id,
    customer_name,
    table_number,
    delivery_provider,
    delivery_reference,
    delivery_contact_name,
    delivery_phone,
    delivery_address,
    notes
  )
  values (
    p_client_request_id,
    p_order_type,
    p_source_code,
    auth.uid(),
    coalesce(v_profile.display_name, concat_ws(' ', v_profile.first_name, v_profile.last_name)),
    v_shift_id,
    p_device_id,
    nullif(btrim(coalesce(p_customer_name,'')), ''),
    nullif(btrim(coalesce(p_table_number,'')), ''),
    nullif(btrim(coalesce(p_delivery_provider,'')), ''),
    nullif(btrim(coalesce(p_delivery_reference,'')), ''),
    nullif(btrim(coalesce(p_delivery_contact_name,'')), ''),
    nullif(btrim(coalesce(p_delivery_phone,'')), ''),
    nullif(btrim(coalesce(p_delivery_address,'')), ''),
    nullif(btrim(coalesce(p_notes,'')), '')
  )
  returning * into v_order;

  insert into public.order_status_history(order_id, old_status, new_status, changed_by, reason)
  values (v_order.id, null, 'OPEN', auth.uid(), 'Order created');

  return v_order;
end;
$$;

revoke all on function public.create_order(text,text,text,text,text,text,text,text,text,text,uuid,uuid) from public;
grant execute on function public.create_order(text,text,text,text,text,text,text,text,text,text,uuid,uuid) to authenticated;

create or replace function public.reprice_order_item(p_order_item_id uuid)
returns public.order_items
language plpgsql
security definer
set search_path = public
as $$
declare
  v_item public.order_items%rowtype;
  v_modifier_per_unit numeric(14,2);
begin
  select * into v_item
  from public.order_items
  where id = p_order_item_id
  for update;

  if not found then
    raise exception 'Order item not found';
  end if;

  select coalesce(sum(oim.price_delta * oim.quantity),0)
  into v_modifier_per_unit
  from public.order_item_modifiers oim
  where oim.order_item_id = p_order_item_id;

  update public.order_items
  set
    modifier_total_per_unit = v_modifier_per_unit,
    line_subtotal = round((unit_price + v_modifier_per_unit) * quantity, 2),
    line_total = round(
      greatest(
        0,
        ((unit_price + v_modifier_per_unit) * quantity)
        - discount_amount
        + tax_amount
      ),
      2
    )
  where id = p_order_item_id
  returning * into v_item;

  return v_item;
end;
$$;

revoke all on function public.reprice_order_item(uuid) from public;

create or replace function public.add_order_item(
  p_order_id uuid,
  p_menu_variant_id uuid,
  p_quantity numeric,
  p_modifier_ids uuid[] default '{}'::uuid[],
  p_special_instructions text default null
)
returns public.order_items
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order public.orders%rowtype;
  v_variant record;
  v_item public.order_items%rowtype;
  v_modifier_id uuid;
  v_modifier record;
begin
  if not public.has_permission('orders.create') then
    raise exception 'Permission denied';
  end if;

  v_order := public.assert_active_order_access(p_order_id);

  if v_order.status not in ('OPEN','PENDING_PAYMENT') then
    raise exception 'Order cannot be edited in its current status';
  end if;

  if v_order.created_by_user_id = auth.uid()
     and public.current_open_shift_id() is null then
    raise exception 'An active shift is required';
  end if;

  if p_quantity is null or p_quantity <= 0 then
    raise exception 'Quantity must be greater than zero';
  end if;

  select
    mv.id as variant_id,
    mv.menu_item_id,
    mv.name as variant_name,
    mv.price,
    mi.name as item_name,
    mv.is_active as variant_active,
    mi.is_active as item_active
  into v_variant
  from public.menu_variants mv
  join public.menu_items mi on mi.id = mv.menu_item_id
  where mv.id = p_menu_variant_id;

  if not found or not v_variant.variant_active or not v_variant.item_active then
    raise exception 'Menu variant is unavailable';
  end if;

  insert into public.order_items(
    order_id,
    menu_item_id,
    menu_variant_id,
    item_name_snapshot,
    variant_name_snapshot,
    quantity,
    unit_price,
    line_subtotal,
    line_total,
    special_instructions
  )
  values (
    p_order_id,
    v_variant.menu_item_id,
    v_variant.variant_id,
    v_variant.item_name,
    v_variant.variant_name,
    p_quantity,
    v_variant.price,
    round(v_variant.price * p_quantity,2),
    round(v_variant.price * p_quantity,2),
    nullif(btrim(coalesce(p_special_instructions,'')), '')
  )
  returning * into v_item;

  foreach v_modifier_id in array coalesce(p_modifier_ids, '{}'::uuid[])
  loop
    select
      m.id,
      m.name,
      m.price_delta,
      m.modifier_group_id,
      mg.max_selections,
      mg.min_selections,
      mg.is_required
    into v_modifier
    from public.modifiers m
    join public.modifier_groups mg on mg.id = m.modifier_group_id
    join public.menu_item_modifier_groups mig
      on mig.modifier_group_id = mg.id
     and mig.menu_item_id = v_variant.menu_item_id
    where m.id = v_modifier_id
      and m.is_active = true
      and mg.is_active = true;

    if not found then
      raise exception 'Modifier % is unavailable for this menu item', v_modifier_id;
    end if;

    insert into public.order_item_modifiers(
      order_item_id,
      modifier_id,
      modifier_name_snapshot,
      quantity,
      price_delta,
      line_amount
    )
    values (
      v_item.id,
      v_modifier.id,
      v_modifier.name,
      1,
      v_modifier.price_delta,
      v_modifier.price_delta
    )
    on conflict (order_item_id, modifier_id)
    where modifier_id is not null
    do update set
      quantity = public.order_item_modifiers.quantity + 1,
      line_amount = public.order_item_modifiers.line_amount + excluded.price_delta;
  end loop;

  perform public.reprice_order_item(v_item.id);
  perform public.recalculate_order_totals(p_order_id);

  select * into v_item
  from public.order_items
  where id = v_item.id;

  return v_item;
end;
$$;

revoke all on function public.add_order_item(uuid,uuid,numeric,uuid[],text) from public;
grant execute on function public.add_order_item(uuid,uuid,numeric,uuid[],text) to authenticated;

create or replace function public.update_order_item_quantity(
  p_order_item_id uuid,
  p_quantity numeric
)
returns public.order_items
language plpgsql
security definer
set search_path = public
as $$
declare
  v_item public.order_items%rowtype;
  v_order public.orders%rowtype;
begin
  if p_quantity <= 0 then
    raise exception 'Quantity must be greater than zero';
  end if;

  select * into v_item
  from public.order_items
  where id = p_order_item_id
  for update;

  if not found then
    raise exception 'Order item not found';
  end if;

  v_order := public.assert_active_order_access(v_item.order_id);

  if v_order.status not in ('OPEN','PENDING_PAYMENT') then
    raise exception 'Order cannot be edited';
  end if;

  update public.order_items
  set quantity = p_quantity
  where id = p_order_item_id;

  perform public.reprice_order_item(p_order_item_id);
  perform public.recalculate_order_totals(v_item.order_id);

  select * into v_item
  from public.order_items
  where id = p_order_item_id;

  return v_item;
end;
$$;

revoke all on function public.update_order_item_quantity(uuid,numeric) from public;
grant execute on function public.update_order_item_quantity(uuid,numeric) to authenticated;

create or replace function public.remove_order_item(p_order_item_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_item public.order_items%rowtype;
  v_order public.orders%rowtype;
begin
  select * into v_item
  from public.order_items
  where id = p_order_item_id
  for update;

  if not found then
    raise exception 'Order item not found';
  end if;

  v_order := public.assert_active_order_access(v_item.order_id);

  if v_order.status not in ('OPEN','PENDING_PAYMENT') then
    raise exception 'Order cannot be edited';
  end if;

  delete from public.order_items where id = p_order_item_id;

  perform public.recalculate_order_totals(v_item.order_id);
end;
$$;

revoke all on function public.remove_order_item(uuid) from public;
grant execute on function public.remove_order_item(uuid) to authenticated;

-- ============================================================
-- Discounts
-- ============================================================

create or replace function public.apply_order_discount(
  p_order_id uuid,
  p_discount_type_id uuid,
  p_order_item_ids uuid[],
  p_reference_name text default null,
  p_reference_number text default null,
  p_manual_value numeric default null,
  p_authorized_by uuid default null,
  p_notes text default null
)
returns public.order_discounts
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order public.orders%rowtype;
  v_type public.discount_types%rowtype;
  v_discount public.order_discounts%rowtype;
  v_item record;
  v_eligible numeric(14,2) := 0;
  v_total_discount numeric(14,2) := 0;
  v_rate numeric(14,4);
  v_alloc numeric(14,2);
begin
  if not public.has_permission('discounts.apply') then
    raise exception 'Permission denied';
  end if;

  v_order := public.assert_active_order_access(p_order_id);

  if v_order.status not in ('OPEN','PENDING_PAYMENT') then
    raise exception 'Discount cannot be applied to this order';
  end if;

  select * into v_type
  from public.discount_types
  where id = p_discount_type_id and is_active = true;

  if not found then
    raise exception 'Discount type not found or inactive';
  end if;

  if v_type.requires_id
     and nullif(btrim(coalesce(p_reference_number,'')), '') is null then
    raise exception 'Discount reference/ID number is required';
  end if;

  if v_type.requires_authorization and p_authorized_by is null then
    raise exception 'Manager authorization is required';
  end if;

  if p_order_item_ids is null or cardinality(p_order_item_ids) = 0 then
    raise exception 'At least one eligible order item is required';
  end if;

  select coalesce(sum(oi.line_subtotal),0)
  into v_eligible
  from public.order_items oi
  where oi.order_id = p_order_id
    and oi.id = any(p_order_item_ids);

  if v_eligible <= 0 then
    raise exception 'No eligible amount found';
  end if;

  if v_type.calculation_method = 'PERCENTAGE' then
    v_rate := coalesce(p_manual_value, v_type.default_value);
    if v_rate is null or v_rate < 0 or v_rate > 100 then
      raise exception 'Invalid percentage discount';
    end if;
    v_total_discount := round(v_eligible * v_rate / 100.0,2);
  elsif v_type.calculation_method = 'FIXED_AMOUNT' then
    v_total_discount := round(coalesce(p_manual_value, v_type.default_value),2);
  else
    v_total_discount := round(coalesce(p_manual_value,0),2);
  end if;

  if v_total_discount <= 0 or v_total_discount > v_eligible then
    raise exception 'Invalid discount amount';
  end if;

  insert into public.order_discounts(
    order_id,
    discount_type_id,
    discount_name_snapshot,
    discount_amount,
    reference_name,
    reference_number,
    authorized_by,
    notes
  )
  values (
    p_order_id,
    p_discount_type_id,
    v_type.name,
    v_total_discount,
    nullif(btrim(coalesce(p_reference_name,'')), ''),
    nullif(btrim(coalesce(p_reference_number,'')), ''),
    p_authorized_by,
    nullif(btrim(coalesce(p_notes,'')), '')
  )
  returning * into v_discount;

  -- Allocate proportionally to the selected eligible lines.
  for v_item in
    select oi.id, oi.line_subtotal
    from public.order_items oi
    where oi.order_id = p_order_id
      and oi.id = any(p_order_item_ids)
  loop
    v_alloc := round(v_total_discount * (v_item.line_subtotal / v_eligible),2);

    insert into public.order_discount_items(
      order_discount_id,
      order_item_id,
      eligible_amount,
      discount_amount
    )
    values (
      v_discount.id,
      v_item.id,
      v_item.line_subtotal,
      least(v_alloc, v_item.line_subtotal)
    );
  end loop;

  -- Correct any rounding remainder on the first allocation.
  update public.order_discount_items odi
  set discount_amount = discount_amount + (
    v_total_discount - (
      select coalesce(sum(discount_amount),0)
      from public.order_discount_items
      where order_discount_id = v_discount.id
    )
  )
  where odi.id = (
    select id
    from public.order_discount_items
    where order_discount_id = v_discount.id
    order by created_at, id
    limit 1
  );

  perform public.recalculate_order_totals(p_order_id);

  return v_discount;
end;
$$;

revoke all on function public.apply_order_discount(uuid,uuid,uuid[],text,text,numeric,uuid,text) from public;
grant execute on function public.apply_order_discount(uuid,uuid,uuid[],text,text,numeric,uuid,text) to authenticated;

-- ============================================================
-- Checkout hardened payment validation
-- ============================================================

create or replace function public.checkout_order(
  p_order_id uuid,
  p_payments jsonb
)
returns public.orders
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order public.orders%rowtype;
  v_item public.order_items%rowtype;
  v_component record;
  v_modifier_component record;
  v_payment jsonb;
  v_method public.payment_methods%rowtype;
  v_payment_total numeric(14,2) := 0;
  v_amount numeric(14,2);
  v_tendered numeric(14,2);
  v_change numeric(14,2);
  v_shift_id uuid;
  v_split_allowed boolean := false;
begin
  if not public.has_permission('orders.checkout') then
    raise exception 'Permission denied';
  end if;

  select * into v_order
  from public.orders
  where id = p_order_id
  for update;

  if not found then
    raise exception 'Order not found';
  end if;

  if not (
    v_order.created_by_user_id = auth.uid()
    or public.has_permission('orders.manage_all')
  ) then
    raise exception 'Permission denied for this order';
  end if;

  if v_order.status not in ('OPEN','PENDING_PAYMENT') then
    raise exception 'Order is not available for checkout';
  end if;

  if not exists (select 1 from public.order_items where order_id = p_order_id) then
    raise exception 'Order has no items';
  end if;

  v_shift_id := public.current_open_shift_id();
  if v_shift_id is null then
    raise exception 'An active shift is required';
  end if;

  if jsonb_typeof(p_payments) <> 'array' or jsonb_array_length(p_payments) = 0 then
    raise exception 'At least one payment is required';
  end if;

  select coalesce((value #>> '{}')::boolean,false)
  into v_split_allowed
  from public.system_settings
  where key = 'allow_split_payments';

  if not coalesce(v_split_allowed,false) and jsonb_array_length(p_payments) > 1 then
    raise exception 'Split payments are currently disabled';
  end if;

  perform public.recalculate_order_totals(p_order_id);

  select * into v_order
  from public.orders
  where id = p_order_id
  for update;

  for v_payment in select value from jsonb_array_elements(p_payments)
  loop
    select * into v_method
    from public.payment_methods
    where id = (v_payment ->> 'payment_method_id')::uuid
      and is_active = true;

    if not found then
      raise exception 'Invalid or inactive payment method';
    end if;

    v_amount := round((v_payment ->> 'amount')::numeric,2);
    v_tendered := nullif(v_payment ->> 'amount_tendered','')::numeric;
    v_change := coalesce(nullif(v_payment ->> 'change_amount','')::numeric,0);

    if v_amount <= 0 then
      raise exception 'Payment amount must be greater than zero';
    end if;

    if v_method.requires_reference
       and nullif(btrim(coalesce(v_payment ->> 'external_reference','')), '') is null then
      raise exception 'A transaction reference is required for %', v_method.name;
    end if;

    if v_method.is_cash then
      if v_tendered is null then
        raise exception 'Cash amount tendered is required';
      end if;

      if v_tendered < v_amount then
        raise exception 'Cash tendered cannot be less than payment amount';
      end if;

      if round(v_change,2) <> round(v_tendered - v_amount,2) then
        raise exception 'Incorrect cash change amount';
      end if;
    else
      if coalesce(v_change,0) <> 0 then
        raise exception 'Non-cash payment cannot have change';
      end if;
    end if;

    v_payment_total := v_payment_total + v_amount;
  end loop;

  if round(v_payment_total,2) <> round(v_order.total_amount,2) then
    raise exception 'Payment total must equal order total';
  end if;

  -- Consume inventory only after all validations pass.
  for v_item in
    select * from public.order_items where order_id = p_order_id
  loop
    -- Finished-good mode.
    for v_component in
      select
        mv.finished_inventory_item_id as inventory_item_id,
        v_item.quantity as quantity_needed
      from public.menu_variants mv
      where mv.id = v_item.menu_variant_id
        and mv.track_finished_inventory = true
        and mv.finished_inventory_item_id is not null
    loop
      perform public.consume_inventory_fefo(
        v_component.inventory_item_id,
        v_component.quantity_needed,
        p_order_id,
        v_item.id,
        auth.uid()
      );
    end loop;

    -- Recipe mode.
    for v_component in
      select
        rc.inventory_item_id,
        (
          rc.quantity_base_uom
          * (1 + rc.wastage_percent / 100.0)
          * v_item.quantity
        ) as quantity_needed
      from public.variant_recipe_components rc
      where rc.menu_variant_id = v_item.menu_variant_id
    loop
      perform public.consume_inventory_fefo(
        v_component.inventory_item_id,
        v_component.quantity_needed,
        p_order_id,
        v_item.id,
        auth.uid()
      );
    end loop;

    -- Modifier recipes.
    for v_modifier_component in
      select
        mrc.inventory_item_id,
        sum(
          mrc.quantity_base_uom
          * (1 + mrc.wastage_percent / 100.0)
          * oim.quantity
          * v_item.quantity
        ) as quantity_needed
      from public.order_item_modifiers oim
      join public.modifier_recipe_components mrc
        on mrc.modifier_id = oim.modifier_id
      where oim.order_item_id = v_item.id
      group by mrc.inventory_item_id
    loop
      perform public.consume_inventory_fefo(
        v_modifier_component.inventory_item_id,
        v_modifier_component.quantity_needed,
        p_order_id,
        v_item.id,
        auth.uid()
      );
    end loop;
  end loop;

  for v_payment in select value from jsonb_array_elements(p_payments)
  loop
    insert into public.payments(
      order_id,
      payment_method_id,
      transaction_type,
      status,
      amount,
      amount_tendered,
      change_amount,
      external_provider,
      external_reference,
      idempotency_key,
      processed_by,
      shift_id,
      device_id
    )
    values (
      p_order_id,
      (v_payment ->> 'payment_method_id')::uuid,
      'PAYMENT',
      'COMPLETED',
      round((v_payment ->> 'amount')::numeric,2),
      nullif(v_payment ->> 'amount_tendered','')::numeric,
      coalesce(nullif(v_payment ->> 'change_amount','')::numeric,0),
      nullif(btrim(coalesce(v_payment ->> 'external_provider','')), ''),
      nullif(btrim(coalesce(v_payment ->> 'external_reference','')), ''),
      nullif(v_payment ->> 'idempotency_key','')::uuid,
      auth.uid(),
      v_shift_id,
      v_order.device_id
    );
  end loop;

  update public.orders
  set
    status = 'COMPLETED',
    payment_status = 'PAID',
    shift_id = coalesce(shift_id, v_shift_id),
    completed_at = now()
  where id = p_order_id
  returning * into v_order;

  insert into public.order_status_history(order_id, old_status, new_status, changed_by)
  values (p_order_id, 'PENDING_PAYMENT', 'COMPLETED', auth.uid());

  perform public.issue_sales_invoice(p_order_id);

  insert into public.audit_logs(
    actor_user_id,
    action_code,
    entity_type,
    entity_id,
    device_id,
    new_data
  )
  values (
    auth.uid(),
    'ORDER_CHECKOUT',
    'order',
    p_order_id::text,
    v_order.device_id,
    jsonb_build_object(
      'total_amount', v_order.total_amount,
      'payment_total', v_payment_total
    )
  );

  return v_order;
end;
$$;

revoke all on function public.checkout_order(uuid,jsonb) from public;
grant execute on function public.checkout_order(uuid,jsonb) to authenticated;

-- ============================================================
-- Purchase receiving with automatic PO status
-- ============================================================

create or replace function public.post_goods_receipt(p_goods_receipt_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_receipt public.goods_receipts%rowtype;
  v_line public.goods_receipt_items%rowtype;
  v_item public.inventory_items%rowtype;
  v_lot_id uuid;
  v_expected numeric(14,4);
  v_received numeric(14,4);
begin
  if not public.has_permission('purchases.receive') then
    raise exception 'Permission denied';
  end if;

  select * into v_receipt
  from public.goods_receipts
  where id = p_goods_receipt_id
  for update;

  if not found then
    raise exception 'Goods receipt not found';
  end if;

  if v_receipt.status <> 'DRAFT' then
    raise exception 'Only DRAFT goods receipts can be posted';
  end if;

  if not exists (
    select 1 from public.goods_receipt_items
    where goods_receipt_id = p_goods_receipt_id
  ) then
    raise exception 'Goods receipt has no items';
  end if;

  for v_line in
    select * from public.goods_receipt_items
    where goods_receipt_id = p_goods_receipt_id
  loop
    select * into v_item
    from public.inventory_items
    where id = v_line.inventory_item_id;

    if not found then
      raise exception 'Inventory item not found';
    end if;

    if v_item.track_expiry and v_line.expiration_date is null then
      raise exception 'Expiration date is required for %', v_item.name;
    end if;

    insert into public.inventory_lots(
      inventory_item_id,
      goods_receipt_item_id,
      lot_code,
      received_at,
      expiration_date,
      received_quantity,
      remaining_quantity,
      unit_cost_base
    )
    values (
      v_line.inventory_item_id,
      v_line.id,
      v_line.lot_code,
      v_receipt.received_at,
      v_line.expiration_date,
      v_line.base_quantity,
      v_line.base_quantity,
      v_line.unit_cost_base
    )
    returning id into v_lot_id;

    insert into public.stock_movements(
      inventory_item_id,
      inventory_lot_id,
      movement_type,
      quantity_delta,
      unit_cost_base,
      reference_type,
      reference_id,
      recorded_by
    )
    values (
      v_line.inventory_item_id,
      v_lot_id,
      'PURCHASE_RECEIPT',
      v_line.base_quantity,
      v_line.unit_cost_base,
      'GOODS_RECEIPT',
      p_goods_receipt_id,
      auth.uid()
    );
  end loop;

  update public.goods_receipts
  set status = 'POSTED', posted_at = now()
  where id = p_goods_receipt_id;

  if v_receipt.purchase_order_id is not null then
    select
      coalesce(sum(poi.ordered_quantity * poi.base_quantity_per_purchase_unit),0),
      coalesce(sum(gri.base_quantity),0)
    into v_expected, v_received
    from public.purchase_order_items poi
    left join public.goods_receipt_items gri
      on gri.purchase_order_item_id = poi.id
    left join public.goods_receipts gr
      on gr.id = gri.goods_receipt_id
     and gr.status = 'POSTED'
    where poi.purchase_order_id = v_receipt.purchase_order_id;

    update public.purchase_orders
    set status = case
      when v_received <= 0 then status
      when v_received < v_expected then 'PARTIALLY_RECEIVED'
      else 'RECEIVED'
    end
    where id = v_receipt.purchase_order_id
      and status <> 'CANCELLED';
  end if;

  insert into public.audit_logs(
    actor_user_id,
    action_code,
    entity_type,
    entity_id,
    new_data
  )
  values (
    auth.uid(),
    'GOODS_RECEIPT_POSTED',
    'goods_receipt',
    p_goods_receipt_id::text,
    jsonb_build_object('receipt_number', v_receipt.receipt_number)
  );
end;
$$;

revoke all on function public.post_goods_receipt(uuid) from public;
grant execute on function public.post_goods_receipt(uuid) to authenticated;

-- ============================================================
-- Manual stock adjustment uses the stock ledger and FEFO lots
-- ============================================================

create or replace function public.adjust_inventory_stock(
  p_inventory_item_id uuid,
  p_movement_type text,
  p_quantity numeric,
  p_reason text,
  p_expiration_date date default null,
  p_unit_cost_base numeric default 0
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_item public.inventory_items%rowtype;
  v_remaining numeric(14,4);
  v_lot public.inventory_lots%rowtype;
  v_take numeric(14,4);
  v_new_lot uuid;
begin
  if not public.has_permission('inventory.adjust') then
    raise exception 'Permission denied';
  end if;

  if p_quantity is null or p_quantity <= 0 then
    raise exception 'Quantity must be greater than zero';
  end if;

  select * into v_item
  from public.inventory_items
  where id = p_inventory_item_id
  for update;

  if not found or not v_item.track_inventory then
    raise exception 'Tracked inventory item not found';
  end if;

  p_movement_type := upper(btrim(p_movement_type));

  if p_movement_type = 'MANUAL_IN' then
    if v_item.track_expiry and p_expiration_date is null then
      raise exception 'Expiration date is required for this item';
    end if;

    insert into public.inventory_lots(
      inventory_item_id,
      lot_code,
      received_at,
      expiration_date,
      received_quantity,
      remaining_quantity,
      unit_cost_base
    )
    values (
      p_inventory_item_id,
      'MANUAL-' || to_char(now(),'YYYYMMDDHH24MISS'),
      now(),
      p_expiration_date,
      p_quantity,
      p_quantity,
      greatest(coalesce(p_unit_cost_base,0),0)
    )
    returning id into v_new_lot;

    insert into public.stock_movements(
      inventory_item_id,
      inventory_lot_id,
      movement_type,
      quantity_delta,
      unit_cost_base,
      reference_type,
      reason,
      recorded_by
    )
    values (
      p_inventory_item_id,
      v_new_lot,
      'MANUAL_IN',
      p_quantity,
      greatest(coalesce(p_unit_cost_base,0),0),
      'MANUAL_ADJUSTMENT',
      p_reason,
      auth.uid()
    );

    return;
  end if;

  if p_movement_type not in (
    'MANUAL_OUT','WASTE','DAMAGED','EXPIRED','COMPLIMENTARY','STAFF_MEAL','STOCK_COUNT_ADJUSTMENT'
  ) then
    raise exception 'Unsupported stock-out movement type';
  end if;

  v_remaining := p_quantity;

  for v_lot in
    select *
    from public.inventory_lots
    where inventory_item_id = p_inventory_item_id
      and remaining_quantity > 0
      and status = 'AVAILABLE'
    order by expiration_date asc nulls last, received_at asc
    for update
  loop
    exit when v_remaining <= 0;
    v_take := least(v_remaining, v_lot.remaining_quantity);

    update public.inventory_lots
    set
      remaining_quantity = remaining_quantity - v_take,
      status = case
        when remaining_quantity - v_take <= 0 then 'DEPLETED'
        else status
      end
    where id = v_lot.id;

    insert into public.stock_movements(
      inventory_item_id,
      inventory_lot_id,
      movement_type,
      quantity_delta,
      unit_cost_base,
      reference_type,
      reason,
      recorded_by
    )
    values (
      p_inventory_item_id,
      v_lot.id,
      p_movement_type,
      -v_take,
      v_lot.unit_cost_base,
      'MANUAL_ADJUSTMENT',
      p_reason,
      auth.uid()
    );

    v_remaining := v_remaining - v_take;
  end loop;

  if v_remaining > 0 then
    raise exception 'Insufficient stock for adjustment';
  end if;
end;
$$;

revoke all on function public.adjust_inventory_stock(uuid,text,numeric,text,date,numeric) from public;
grant execute on function public.adjust_inventory_stock(uuid,text,numeric,text,date,numeric) to authenticated;

-- ============================================================
-- Supplier bill payment
-- ============================================================

create or replace function public.record_supplier_bill_payment(
  p_supplier_bill_id uuid,
  p_payment_method_id uuid,
  p_amount numeric,
  p_reference_number text default null,
  p_notes text default null
)
returns public.supplier_bill_payments
language plpgsql
security definer
set search_path = public
as $$
declare
  v_bill public.supplier_bills%rowtype;
  v_paid numeric(14,2);
  v_payment public.supplier_bill_payments%rowtype;
begin
  if not public.has_permission('finance.manage') then
    raise exception 'Permission denied';
  end if;

  select * into v_bill
  from public.supplier_bills
  where id = p_supplier_bill_id
  for update;

  if not found or v_bill.status = 'VOID' then
    raise exception 'Supplier bill not available';
  end if;

  select coalesce(sum(amount),0)
  into v_paid
  from public.supplier_bill_payments
  where supplier_bill_id = p_supplier_bill_id;

  if p_amount <= 0 or round(v_paid + p_amount,2) > round(v_bill.amount,2) then
    raise exception 'Payment exceeds supplier bill balance';
  end if;

  if exists (
    select 1
    from public.payment_methods pm
    where pm.id = p_payment_method_id
      and pm.requires_reference = true
      and nullif(btrim(coalesce(p_reference_number,'')), '') is null
  ) then
    raise exception 'Payment reference is required';
  end if;

  insert into public.supplier_bill_payments(
    supplier_bill_id,
    payment_method_id,
    amount,
    reference_number,
    recorded_by,
    notes
  )
  values (
    p_supplier_bill_id,
    p_payment_method_id,
    round(p_amount,2),
    nullif(btrim(coalesce(p_reference_number,'')), ''),
    auth.uid(),
    nullif(btrim(coalesce(p_notes,'')), '')
  )
  returning * into v_payment;

  perform public.sync_supplier_bill_status(p_supplier_bill_id);

  return v_payment;
end;
$$;

revoke all on function public.record_supplier_bill_payment(uuid,uuid,numeric,text,text) from public;
grant execute on function public.record_supplier_bill_payment(uuid,uuid,numeric,text,text) to authenticated;

-- ============================================================
-- Refund calculation is derived server-side from original sale
-- ============================================================

create or replace function public.process_refund(
  p_order_id uuid,
  p_items jsonb,
  p_payment_returns jsonb,
  p_reason text,
  p_authorized_by uuid
)
returns public.refunds
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order public.orders%rowtype;
  v_refund public.refunds%rowtype;
  v_item_json jsonb;
  v_payment jsonb;
  v_order_item public.order_items%rowtype;
  v_qty numeric(14,4);
  v_already_qty numeric(14,4);
  v_already_amount numeric(14,2);
  v_allocated_order_discount numeric(14,2);
  v_net_line numeric(14,2);
  v_unit_refundable numeric(14,6);
  v_line_refund numeric(14,2);
  v_refund_total numeric(14,2) := 0;
  v_return_total numeric(14,2) := 0;
  v_previous_refunds numeric(14,2);
  v_refund_type text;
  v_method public.payment_methods%rowtype;
begin
  if not public.has_permission('orders.refund') then
    raise exception 'Permission denied';
  end if;

  if nullif(btrim(coalesce(p_reason,'')), '') is null then
    raise exception 'Refund reason is required';
  end if;

  if p_authorized_by is null then
    raise exception 'Manager authorization is required';
  end if;

  select * into v_order
  from public.orders
  where id = p_order_id
  for update;

  if not found or v_order.status not in ('COMPLETED','PARTIALLY_REFUNDED') then
    raise exception 'Order is not refundable';
  end if;

  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'Refund items are required';
  end if;

  -- First pass validates and calculates the refund from stored sale values.
  for v_item_json in select value from jsonb_array_elements(p_items)
  loop
    select * into v_order_item
    from public.order_items
    where id = (v_item_json ->> 'order_item_id')::uuid
      and order_id = p_order_id;

    if not found then
      raise exception 'Refund item does not belong to order';
    end if;

    v_qty := (v_item_json ->> 'quantity')::numeric;

    select
      coalesce(sum(ri.quantity),0),
      coalesce(sum(ri.refund_amount),0)
    into v_already_qty, v_already_amount
    from public.refund_items ri
    join public.refunds r on r.id = ri.refund_id
    where ri.order_item_id = v_order_item.id
      and r.status = 'COMPLETED';

    if v_qty <= 0 or v_qty + v_already_qty > v_order_item.quantity then
      raise exception 'Invalid refund quantity for order item %', v_order_item.id;
    end if;

    select coalesce(sum(odi.discount_amount),0)
    into v_allocated_order_discount
    from public.order_discount_items odi
    join public.order_discounts od on od.id = odi.order_discount_id
    where odi.order_item_id = v_order_item.id
      and od.order_id = p_order_id;

    v_net_line := greatest(
      0,
      v_order_item.line_total - v_allocated_order_discount
    );

    v_unit_refundable := v_net_line / v_order_item.quantity;
    v_line_refund := round(v_unit_refundable * v_qty,2);

    if v_line_refund <= 0 then
      raise exception 'Calculated refundable amount is zero';
    end if;

    if v_already_amount + v_line_refund > v_net_line + 0.01 then
      raise exception 'Refund exceeds remaining refundable amount';
    end if;

    v_refund_total := v_refund_total + v_line_refund;
  end loop;

  select coalesce(sum(total_amount),0)
  into v_previous_refunds
  from public.refunds
  where order_id = p_order_id
    and status = 'COMPLETED';

  if v_refund_total <= 0
     or round(v_previous_refunds + v_refund_total,2) > round(v_order.total_amount,2) then
    raise exception 'Refund exceeds order total';
  end if;

  v_refund_type := case
    when round(v_previous_refunds + v_refund_total,2) >= round(v_order.total_amount,2)
      then 'FULL'
    else 'PARTIAL'
  end;

  insert into public.refunds(
    order_id,
    refund_type,
    status,
    reason,
    total_amount,
    requested_by,
    authorized_by,
    shift_id
  )
  values (
    p_order_id,
    v_refund_type,
    'COMPLETED',
    p_reason,
    v_refund_total,
    auth.uid(),
    p_authorized_by,
    public.current_open_shift_id()
  )
  returning * into v_refund;

  -- Second pass stores exactly the server-calculated refund amounts.
  for v_item_json in select value from jsonb_array_elements(p_items)
  loop
    select * into v_order_item
    from public.order_items
    where id = (v_item_json ->> 'order_item_id')::uuid
      and order_id = p_order_id;

    v_qty := (v_item_json ->> 'quantity')::numeric;

    select coalesce(sum(odi.discount_amount),0)
    into v_allocated_order_discount
    from public.order_discount_items odi
    join public.order_discounts od on od.id = odi.order_discount_id
    where odi.order_item_id = v_order_item.id
      and od.order_id = p_order_id;

    v_net_line := greatest(0, v_order_item.line_total - v_allocated_order_discount);
    v_unit_refundable := v_net_line / v_order_item.quantity;
    v_line_refund := round(v_unit_refundable * v_qty,2);

    insert into public.refund_items(
      refund_id,
      order_item_id,
      quantity,
      refund_amount,
      restock_approved,
      notes
    )
    values (
      v_refund.id,
      v_order_item.id,
      v_qty,
      v_line_refund,
      false,
      nullif(btrim(coalesce(v_item_json ->> 'notes','')), '')
    );
  end loop;

  if jsonb_typeof(p_payment_returns) <> 'array'
     or jsonb_array_length(p_payment_returns) = 0 then
    raise exception 'Refund payment method is required';
  end if;

  for v_payment in select value from jsonb_array_elements(p_payment_returns)
  loop
    select * into v_method
    from public.payment_methods
    where id = (v_payment ->> 'payment_method_id')::uuid
      and is_active = true;

    if not found then
      raise exception 'Invalid refund payment method';
    end if;

    if v_method.requires_reference
       and nullif(btrim(coalesce(v_payment ->> 'external_reference','')), '') is null then
      raise exception 'Refund reference is required for %', v_method.name;
    end if;

    v_return_total := v_return_total + round((v_payment ->> 'amount')::numeric,2);
  end loop;

  if round(v_return_total,2) <> round(v_refund_total,2) then
    raise exception 'Refund payment total must equal calculated refund total %', v_refund_total;
  end if;

  for v_payment in select value from jsonb_array_elements(p_payment_returns)
  loop
    insert into public.payments(
      order_id,
      refund_id,
      payment_method_id,
      transaction_type,
      status,
      amount,
      external_provider,
      external_reference,
      idempotency_key,
      processed_by,
      shift_id,
      device_id
    )
    values (
      p_order_id,
      v_refund.id,
      (v_payment ->> 'payment_method_id')::uuid,
      'REFUND',
      'COMPLETED',
      round((v_payment ->> 'amount')::numeric,2),
      nullif(btrim(coalesce(v_payment ->> 'external_provider','')), ''),
      nullif(btrim(coalesce(v_payment ->> 'external_reference','')), ''),
      nullif(v_payment ->> 'idempotency_key','')::uuid,
      auth.uid(),
      public.current_open_shift_id(),
      v_order.device_id
    );
  end loop;

  update public.orders
  set
    status = case when v_refund_type = 'FULL' then 'REFUNDED' else 'PARTIALLY_REFUNDED' end,
    payment_status = case when v_refund_type = 'FULL' then 'REFUNDED' else 'PARTIALLY_REFUNDED' end
  where id = p_order_id;

  insert into public.order_actions(order_id, action_type, reason, performed_by, authorized_by)
  values (p_order_id, 'REFUND', p_reason, auth.uid(), p_authorized_by);

  insert into public.order_status_history(order_id, old_status, new_status, changed_by, reason)
  values (
    p_order_id,
    v_order.status,
    case when v_refund_type = 'FULL' then 'REFUNDED' else 'PARTIALLY_REFUNDED' end,
    auth.uid(),
    p_reason
  );

  insert into public.credit_notes(
    sales_invoice_id,
    refund_id,
    amount,
    reason,
    issued_by
  )
  select
    si.id,
    v_refund.id,
    v_refund_total,
    p_reason,
    auth.uid()
  from public.sales_invoices si
  where si.order_id = p_order_id;

  insert into public.audit_logs(
    actor_user_id,
    action_code,
    entity_type,
    entity_id,
    device_id,
    new_data
  )
  values (
    auth.uid(),
    'ORDER_REFUND',
    'order',
    p_order_id::text,
    v_order.device_id,
    jsonb_build_object(
      'refund_id', v_refund.id,
      'refund_total', v_refund_total,
      'refund_type', v_refund_type
    )
  );

  return v_refund;
end;
$$;

revoke all on function public.process_refund(uuid,jsonb,jsonb,text,uuid) from public;
grant execute on function public.process_refund(uuid,jsonb,jsonb,text,uuid) to authenticated;
