-- Promotional discounts for POS checkout.
-- Only generic promo/manual discounts are exposed here. Senior/PWD stays disabled
-- until the café's tax and registration rules are confirmed.

create or replace function public.get_pos_discount_types()
returns table(
  id uuid,
  code text,
  name text,
  calculation_method text,
  default_value numeric,
  requires_authorization boolean
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.has_permission('discounts.apply') then
    return;
  end if;

  return query
  select
    dt.id,
    dt.code,
    dt.name,
    dt.calculation_method,
    dt.default_value,
    dt.requires_authorization
  from public.discount_types dt
  where dt.is_active = true
    and dt.code in ('PROMO_PERCENT','PROMO_FIXED','MANUAL')
  order by dt.name;
end;
$$;

revoke all on function public.get_pos_discount_types()
from public, anon;
grant execute on function public.get_pos_discount_types()
to authenticated;

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
    select * into v_existing
    from public.orders
    where client_request_id = p_client_request_id;

    if found then
      if v_existing.status = 'COMPLETED' then
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

revoke all on function public.place_order_v2(
  text,jsonb,jsonb,jsonb,text,text,text,text,uuid
) from public, anon;
grant execute on function public.place_order_v2(
  text,jsonb,jsonb,jsonb,text,text,text,text,uuid
) to authenticated;
