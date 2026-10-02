-- Atomic POS order placement and a simple read model for the Flutter client.

create or replace view public.v_pos_menu
with (security_invoker = true)
as
select
  mv.id as variant_id,
  mi.id as menu_item_id,
  mv.sku,
  mi.name as item_name,
  mv.name as variant_name,
  mc.name as category_name,
  mv.price,
  mv.sort_order as variant_sort_order,
  coalesce(mc.sort_order, 999) as category_sort_order
from public.menu_variants mv
join public.menu_items mi on mi.id = mv.menu_item_id
left join public.menu_categories mc on mc.id = mi.category_id
where mv.is_active = true
  and mi.is_active = true
order by coalesce(mc.sort_order, 999), mv.sort_order, mi.name, mv.name;

grant select on public.v_pos_menu to authenticated;
revoke all on public.v_pos_menu from anon;

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
    select *
    into v_existing
    from public.orders
    where client_request_id = p_client_request_id;

    if found then
      if v_existing.status = 'COMPLETED' then
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

revoke all on function public.place_order(text,jsonb,jsonb,text,text,text,text,uuid)
from public, anon;

grant execute on function public.place_order(text,jsonb,jsonb,text,text,text,text,uuid)
to authenticated;
