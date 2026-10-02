-- POS-01 / S-06: make order placement safe to retry.
--
-- `orders.client_request_id` already existed, but:
--   * the lookup returned the stored order to any caller who supplied the ID,
--     not only to the user who created it;
--   * an order that had since been refunded was reported as "unfinished", so
--     a retry failed instead of returning the sale;
--   * two simultaneous submissions of one request raced to the unique index
--     and the loser failed with a constraint error.
--
-- Each function below is its current definition with only the request-ID
-- block changed. Signatures and grants are unchanged.

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
    perform pg_advisory_xact_lock(
      hashtextextended('order_request:' || p_client_request_id::text, 0)
    );

    select * into v_order
    from public.orders
    where client_request_id = p_client_request_id;

    if found then
      if v_order.created_by_user_id is distinct from auth.uid() then
        raise exception 'This request ID is not available';
      end if;
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

create or replace function public.place_order(
  p_order_type text,
  p_items jsonb,
  p_payments jsonb,
  p_table_number text default null,
  p_customer_name text default null,
  p_delivery_reference text default null,
  p_notes text default null,
  p_client_request_id uuid default null
)
returns public.orders
language plpgsql
security definer
set search_path = public
as $$
declare
  v_existing public.orders%rowtype;
  v_order public.orders%rowtype;
  v_item jsonb;
  v_modifier_ids uuid[];
begin
  if p_client_request_id is not null then
    -- A second submission of the same request waits here until the first
    -- one commits or rolls back, then sees its result.
    perform pg_advisory_xact_lock(
      hashtextextended('order_request:' || p_client_request_id::text, 0)
    );

    select * into v_existing
    from public.orders
    where client_request_id = p_client_request_id;

    if found then
      if v_existing.created_by_user_id is distinct from auth.uid() then
        raise exception 'This request ID is not available';
      end if;

      -- Placement is one transaction, so a stored order is a finished sale.
      -- It may have been refunded since; it is still the result of this
      -- request and must not be sold again.
      if v_existing.status in ('COMPLETED','PARTIALLY_REFUNDED','REFUNDED') then
        return v_existing;
      end if;

      raise exception 'An unfinished order already exists for this request';
    end if;
  end if;

  if jsonb_typeof(p_items) <> 'array'
     or jsonb_array_length(p_items) = 0 then
    raise exception 'At least one order item is required';
  end if;

  v_order := public.create_order(
    p_order_type := p_order_type,
    p_table_number := p_table_number,
    p_customer_name := p_customer_name,
    p_source_code := 'POS',
    p_delivery_reference := p_delivery_reference,
    p_notes := p_notes,
    p_client_request_id := p_client_request_id
  );

  for v_item in
    select value from jsonb_array_elements(p_items)
  loop
    if nullif(v_item ->> 'menu_variant_id','') is null then
      raise exception 'Menu variant is required';
    end if;

    select coalesce(array_agg(x.value::uuid), '{}'::uuid[])
    into v_modifier_ids
    from jsonb_array_elements_text(
      coalesce(v_item -> 'modifier_ids', '[]'::jsonb)
    ) as x(value);

    perform public.add_order_item(
      v_order.id,
      (v_item ->> 'menu_variant_id')::uuid,
      coalesce((v_item ->> 'quantity')::numeric, 0),
      v_modifier_ids,
      nullif(btrim(coalesce(v_item ->> 'special_instructions','')), '')
    );
  end loop;

  v_order := public.checkout_order(v_order.id, p_payments);

  return v_order;
end;
$$;

create or replace function public.place_order_v2(
  p_order_type text,
  p_items jsonb,
  p_payment jsonb,
  p_discount jsonb default null,
  p_table_number text default null,
  p_customer_name text default null,
  p_delivery_reference text default null,
  p_notes text default null,
  p_client_request_id uuid default null
)
returns public.orders
language plpgsql
security definer
set search_path = public
as $$
declare
  v_existing public.orders%rowtype;
  v_order public.orders%rowtype;
  v_item jsonb;
  v_added public.order_items%rowtype;
  v_item_ids uuid[] := '{}'::uuid[];
  v_modifier_ids uuid[];
  v_discount_type public.discount_types%rowtype;
  v_payment_method public.payment_methods%rowtype;
  v_payment_method_id uuid;
  v_tendered numeric(14,2);
  v_change numeric(14,2) := 0;
  v_payments jsonb;
begin
  if p_client_request_id is not null then
    -- A second submission of the same request waits here until the first
    -- one commits or rolls back, then sees its result.
    perform pg_advisory_xact_lock(
      hashtextextended('order_request:' || p_client_request_id::text, 0)
    );

    select * into v_existing
    from public.orders
    where client_request_id = p_client_request_id;

    if found then
      if v_existing.created_by_user_id is distinct from auth.uid() then
        raise exception 'This request ID is not available';
      end if;

      -- Placement is one transaction, so a stored order is a finished sale.
      -- It may have been refunded since; it is still the result of this
      -- request and must not be sold again.
      if v_existing.status in ('COMPLETED','PARTIALLY_REFUNDED','REFUNDED') then
        return v_existing;
      end if;

      raise exception 'An unfinished order already exists for this request';
    end if;
  end if;

  if jsonb_typeof(coalesce(p_items,'[]'::jsonb)) <> 'array'
     or jsonb_array_length(coalesce(p_items,'[]'::jsonb)) = 0 then
    raise exception 'At least one order item is required';
  end if;

  if jsonb_typeof(coalesce(p_payment,'{}'::jsonb)) <> 'object' then
    raise exception 'Payment details are required';
  end if;

  v_order := public.create_order(
    p_order_type := p_order_type,
    p_table_number := p_table_number,
    p_customer_name := p_customer_name,
    p_source_code := 'POS',
    p_delivery_reference := p_delivery_reference,
    p_notes := p_notes,
    p_client_request_id := p_client_request_id
  );

  for v_item in select value from jsonb_array_elements(p_items)
  loop
    if nullif(v_item ->> 'menu_variant_id','') is null then
      raise exception 'Menu variant is required';
    end if;

    select coalesce(array_agg(x.value::uuid), '{}'::uuid[])
    into v_modifier_ids
    from jsonb_array_elements_text(
      coalesce(v_item -> 'modifier_ids', '[]'::jsonb)
    ) as x(value);

    v_added := public.add_order_item(
      v_order.id,
      (v_item ->> 'menu_variant_id')::uuid,
      coalesce((v_item ->> 'quantity')::numeric, 0),
      v_modifier_ids,
      nullif(btrim(coalesce(v_item ->> 'special_instructions','')), '')
    );

    v_item_ids := array_append(v_item_ids,v_added.id);
  end loop;

  if p_discount is not null
     and jsonb_typeof(p_discount) <> 'null' then
    select * into v_discount_type
    from public.discount_types
    where id = nullif(p_discount ->> 'discount_type_id','')::uuid
      and is_active = true;

    if not found then
      raise exception 'Discount type not found or inactive';
    end if;

    if v_discount_type.code not in (
      'PROMO_PERCENT','PROMO_FIXED','MANUAL'
    ) then
      raise exception
        'This discount type is not enabled in POS until business rules are confirmed';
    end if;

    perform public.apply_order_discount(
      v_order.id,
      v_discount_type.id,
      v_item_ids,
      null,
      null,
      nullif(p_discount ->> 'manual_value','')::numeric,
      auth.uid(),
      nullif(btrim(coalesce(p_discount ->> 'notes','')), '')
    );
  end if;

  select * into v_order
  from public.orders
  where id = v_order.id;

  v_payment_method_id :=
    nullif(p_payment ->> 'payment_method_id','')::uuid;

  select * into v_payment_method
  from public.payment_methods
  where id = v_payment_method_id
    and is_active = true;

  if not found then
    raise exception 'Invalid or inactive payment method';
  end if;

  v_tendered :=
    nullif(p_payment ->> 'amount_tendered','')::numeric;

  if v_payment_method.is_cash then
    if v_tendered is null then
      raise exception 'Cash amount tendered is required';
    end if;
    v_change := round(v_tendered - v_order.total_amount,2);
  else
    v_change := 0;
  end if;

  v_payments := jsonb_build_array(
    jsonb_build_object(
      'payment_method_id',v_payment_method_id,
      'amount',v_order.total_amount,
      'amount_tendered',
        case when v_payment_method.is_cash then v_tendered else null end,
      'change_amount',v_change,
      'external_provider',
        nullif(btrim(coalesce(p_payment ->> 'external_provider','')), ''),
      'external_reference',
        nullif(btrim(coalesce(p_payment ->> 'external_reference','')), ''),
      'idempotency_key',
        nullif(p_payment ->> 'idempotency_key','')
    )
  );

  return public.checkout_order(v_order.id,v_payments);
end;
$$;
