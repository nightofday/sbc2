-- Partial refund workflow for Flutter: preview remaining refundable quantities
-- and process selected refund items using the original payment method.

create or replace function public.get_refund_preview(
  p_order_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order public.orders%rowtype;
  v_payment record;
  v_items jsonb;
begin
  if not public.has_permission('orders.refund') then
    raise exception 'Permission denied';
  end if;

  select *
  into v_order
  from public.orders
  where id = p_order_id;

  if not found or v_order.status not in ('COMPLETED','PARTIALLY_REFUNDED') then
    raise exception 'Order is not refundable';
  end if;

  select
    p.payment_method_id,
    pm.name as payment_method_name,
    pm.code as payment_method_code,
    pm.requires_reference
  into v_payment
  from public.payments p
  join public.payment_methods pm on pm.id = p.payment_method_id
  where p.order_id = p_order_id
    and p.transaction_type = 'PAYMENT'
    and p.status = 'COMPLETED'
  order by p.processed_at
  limit 1;

  if not found then
    raise exception 'Original payment method not found';
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'order_item_id',x.order_item_id,
        'item_name',x.item_name,
        'variant_name',x.variant_name,
        'sold_quantity',x.sold_quantity,
        'refunded_quantity',x.refunded_quantity,
        'remaining_quantity',x.remaining_quantity,
        'unit_refundable',x.unit_refundable,
        'remaining_refundable_amount',
          round(x.unit_refundable * x.remaining_quantity,2)
      )
      order by x.created_at,x.order_item_id
    ),
    '[]'::jsonb
  )
  into v_items
  from (
    select
      oi.id as order_item_id,
      oi.item_name_snapshot as item_name,
      coalesce(oi.variant_name_snapshot,'') as variant_name,
      oi.quantity as sold_quantity,
      coalesce(refunded.refunded_quantity,0) as refunded_quantity,
      oi.quantity - coalesce(refunded.refunded_quantity,0) as remaining_quantity,
      (
        greatest(
          0,
          oi.line_total - coalesce(discounts.allocated_discount,0)
        )
        / oi.quantity
      )::numeric(14,6) as unit_refundable,
      oi.created_at
    from public.order_items oi
    left join (
      select
        ri.order_item_id,
        sum(ri.quantity) as refunded_quantity
      from public.refund_items ri
      join public.refunds r on r.id = ri.refund_id
      where r.status = 'COMPLETED'
      group by ri.order_item_id
    ) refunded on refunded.order_item_id = oi.id
    left join (
      select
        odi.order_item_id,
        sum(odi.discount_amount) as allocated_discount
      from public.order_discount_items odi
      join public.order_discounts od on od.id = odi.order_discount_id
      where od.order_id = p_order_id
      group by odi.order_item_id
    ) discounts on discounts.order_item_id = oi.id
    where oi.order_id = p_order_id
  ) x
  where x.remaining_quantity > 0;

  return jsonb_build_object(
    'order_id',v_order.id,
    'order_number',v_order.order_number,
    'status',v_order.status,
    'total_amount',v_order.total_amount,
    'payment_method_id',v_payment.payment_method_id,
    'payment_method_name',v_payment.payment_method_name,
    'payment_method_code',v_payment.payment_method_code,
    'requires_reference',v_payment.requires_reference,
    'items',v_items
  );
end;
$$;

revoke all on function public.get_refund_preview(uuid)
from public, anon;
grant execute on function public.get_refund_preview(uuid)
to authenticated;

create or replace function public.process_refund_items(
  p_order_id uuid,
  p_items jsonb,
  p_reason text,
  p_external_reference text default null
)
returns public.refunds
language plpgsql
security definer
set search_path = public
as $$
declare
  v_preview jsonb;
  v_item jsonb;
  v_requested jsonb;
  v_request_qty numeric(14,4);
  v_remaining_qty numeric(14,4);
  v_unit_refundable numeric(14,6);
  v_total numeric(14,2) := 0;
  v_payment_method_id uuid;
  v_requires_reference boolean;
  v_returns jsonb;
begin
  if not public.has_permission('orders.refund') then
    raise exception 'Permission denied';
  end if;

  if jsonb_typeof(coalesce(p_items,'[]'::jsonb)) <> 'array'
     or jsonb_array_length(coalesce(p_items,'[]'::jsonb)) = 0 then
    raise exception 'Select at least one item to refund';
  end if;

  v_preview := public.get_refund_preview(p_order_id);
  v_payment_method_id :=
    nullif(v_preview ->> 'payment_method_id','')::uuid;
  v_requires_reference :=
    coalesce((v_preview ->> 'requires_reference')::boolean,false);

  if v_requires_reference
     and nullif(btrim(coalesce(p_external_reference,'')), '') is null then
    raise exception 'Refund transaction reference is required';
  end if;

  for v_requested in
    select value from jsonb_array_elements(p_items)
  loop
    v_request_qty :=
      nullif(v_requested ->> 'quantity','')::numeric;

    if v_request_qty is null or v_request_qty <= 0 then
      raise exception 'Refund quantity must be greater than zero';
    end if;

    select value
    into v_item
    from jsonb_array_elements(v_preview -> 'items')
    where value ->> 'order_item_id' =
      v_requested ->> 'order_item_id'
    limit 1;

    if v_item is null then
      raise exception 'Order item is not refundable';
    end if;

    v_remaining_qty :=
      (v_item ->> 'remaining_quantity')::numeric;
    v_unit_refundable :=
      (v_item ->> 'unit_refundable')::numeric;

    if v_request_qty > v_remaining_qty then
      raise exception 'Refund quantity exceeds remaining refundable quantity';
    end if;

    v_total := v_total
      + round(v_request_qty * v_unit_refundable,2);
  end loop;

  if v_total <= 0 then
    raise exception 'Calculated refund amount is zero';
  end if;

  v_returns := jsonb_build_array(
    jsonb_build_object(
      'payment_method_id',v_payment_method_id,
      'amount',v_total,
      'external_reference',
        nullif(btrim(coalesce(p_external_reference,'')), '')
    )
  );

  return public.process_refund(
    p_order_id,
    p_items,
    v_returns,
    p_reason,
    auth.uid()
  );
end;
$$;

revoke all on function public.process_refund_items(uuid,jsonb,text,text)
from public, anon;
grant execute on function public.process_refund_items(uuid,jsonb,text,text)
to authenticated;
