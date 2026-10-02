-- Purchasing workflows for Flutter: purchase orders and posted goods receipts.

create or replace view public.v_purchase_order_summary
with (security_invoker = true)
as
select
  po.id,
  po.purchase_order_number,
  po.supplier_id,
  s.name as supplier_name,
  po.status,
  po.ordered_at,
  po.expected_date,
  po.subtotal,
  po.discount_amount,
  po.tax_amount,
  po.shipping_amount,
  po.total_amount,
  po.notes,
  po.created_at,
  count(poi.id)::integer as line_count
from public.purchase_orders po
join public.suppliers s on s.id = po.supplier_id
left join public.purchase_order_items poi on poi.purchase_order_id = po.id
group by po.id, s.name;

grant select on public.v_purchase_order_summary to authenticated;
revoke all on public.v_purchase_order_summary from anon;

create or replace view public.v_goods_receipt_summary
with (security_invoker = true)
as
select
  gr.id,
  gr.receipt_number,
  gr.supplier_id,
  s.name as supplier_name,
  gr.purchase_order_id,
  po.purchase_order_number,
  gr.supplier_invoice_number,
  gr.supplier_invoice_date,
  gr.received_at,
  gr.status,
  gr.notes,
  count(gri.id)::integer as line_count,
  coalesce(sum(gri.purchase_quantity * gri.unit_cost_purchase_uom),0)::numeric(14,2)
    as receipt_total
from public.goods_receipts gr
join public.suppliers s on s.id = gr.supplier_id
left join public.purchase_orders po on po.id = gr.purchase_order_id
left join public.goods_receipt_items gri on gri.goods_receipt_id = gr.id
group by gr.id, s.name, po.purchase_order_number;

grant select on public.v_goods_receipt_summary to authenticated;
revoke all on public.v_goods_receipt_summary from anon;

create or replace function public.create_purchase_order(
  p_supplier_id uuid,
  p_items jsonb,
  p_expected_date date default null,
  p_notes text default null
)
returns public.purchase_orders
language plpgsql
security definer
set search_path = public
as $$
declare
  v_po public.purchase_orders%rowtype;
  v_line jsonb;
  v_inventory_item_id uuid;
  v_purchase_uom_id uuid;
  v_qty numeric;
  v_base_per_unit numeric;
  v_unit_cost numeric;
  v_subtotal numeric(14,2) := 0;
begin
  if not public.has_permission('purchases.manage') then
    raise exception 'Permission denied';
  end if;

  if not exists (
    select 1 from public.suppliers
    where id = p_supplier_id and is_active = true
  ) then
    raise exception 'Supplier is unavailable';
  end if;

  if jsonb_typeof(coalesce(p_items,'[]'::jsonb)) <> 'array'
     or jsonb_array_length(coalesce(p_items,'[]'::jsonb)) = 0 then
    raise exception 'At least one purchase item is required';
  end if;

  insert into public.purchase_orders(
    supplier_id,status,expected_date,notes,created_by
  )
  values (
    p_supplier_id,'DRAFT',p_expected_date,
    nullif(btrim(coalesce(p_notes,'')), ''),auth.uid()
  )
  returning * into v_po;

  for v_line in select value from jsonb_array_elements(p_items)
  loop
    v_inventory_item_id := nullif(v_line ->> 'inventory_item_id','')::uuid;
    v_purchase_uom_id := nullif(v_line ->> 'purchase_uom_id','')::uuid;
    v_qty := nullif(v_line ->> 'ordered_quantity','')::numeric;
    v_base_per_unit := nullif(v_line ->> 'base_quantity_per_purchase_unit','')::numeric;
    v_unit_cost := nullif(v_line ->> 'unit_cost','')::numeric;

    if v_qty is null or v_qty <= 0
       or v_base_per_unit is null or v_base_per_unit <= 0
       or v_unit_cost is null or v_unit_cost < 0 then
      raise exception 'Invalid purchase order item values';
    end if;

    if not exists (
      select 1 from public.inventory_items
      where id = v_inventory_item_id and is_active = true
    ) then
      raise exception 'Inventory item is unavailable';
    end if;

    if not exists (
      select 1 from public.units_of_measure
      where id = v_purchase_uom_id and is_active = true
    ) then
      raise exception 'Purchase unit is unavailable';
    end if;

    insert into public.purchase_order_items(
      purchase_order_id,inventory_item_id,purchase_uom_id,ordered_quantity,
      base_quantity_per_purchase_unit,unit_cost,line_total
    )
    values (
      v_po.id,v_inventory_item_id,v_purchase_uom_id,v_qty,v_base_per_unit,
      v_unit_cost,round(v_qty * v_unit_cost,2)
    );

    v_subtotal := v_subtotal + round(v_qty * v_unit_cost,2);
  end loop;

  update public.purchase_orders
  set subtotal = v_subtotal, total_amount = v_subtotal
  where id = v_po.id
  returning * into v_po;

  return v_po;
end;
$$;

revoke all on function public.create_purchase_order(uuid,jsonb,date,text)
from public, anon;
grant execute on function public.create_purchase_order(uuid,jsonb,date,text)
to authenticated;

create or replace function public.approve_purchase_order(
  p_purchase_order_id uuid
)
returns public.purchase_orders
language plpgsql
security definer
set search_path = public
as $$
declare
  v_po public.purchase_orders%rowtype;
begin
  if not public.has_permission('purchases.manage') then
    raise exception 'Permission denied';
  end if;

  update public.purchase_orders
  set status = 'APPROVED',
      approved_by = auth.uid(),
      approved_at = now(),
      ordered_at = coalesce(ordered_at, now())
  where id = p_purchase_order_id
    and status = 'DRAFT'
  returning * into v_po;

  if not found then
    raise exception 'Only DRAFT purchase orders can be approved';
  end if;

  return v_po;
end;
$$;

revoke all on function public.approve_purchase_order(uuid)
from public, anon;
grant execute on function public.approve_purchase_order(uuid)
to authenticated;

create or replace function public.create_and_post_goods_receipt(
  p_supplier_id uuid,
  p_items jsonb,
  p_purchase_order_id uuid default null,
  p_supplier_invoice_number text default null,
  p_supplier_invoice_date date default null,
  p_notes text default null,
  p_create_supplier_bill boolean default true,
  p_due_date date default null
)
returns public.goods_receipts
language plpgsql
security definer
set search_path = public
as $$
declare
  v_receipt public.goods_receipts%rowtype;
  v_line jsonb;
  v_inventory_item_id uuid;
  v_purchase_uom_id uuid;
  v_po_item_id uuid;
  v_purchase_qty numeric;
  v_base_per_unit numeric;
  v_base_qty numeric;
  v_unit_cost_purchase numeric;
  v_unit_cost_base numeric;
  v_expiration date;
  v_lot_code text;
  v_total numeric(14,2) := 0;
begin
  if not public.has_permission('purchases.receive') then
    raise exception 'Permission denied';
  end if;

  if not exists (
    select 1 from public.suppliers
    where id = p_supplier_id and is_active = true
  ) then
    raise exception 'Supplier is unavailable';
  end if;

  if p_purchase_order_id is not null and not exists (
    select 1
    from public.purchase_orders
    where id = p_purchase_order_id
      and supplier_id = p_supplier_id
      and status in ('APPROVED','SENT','PARTIALLY_RECEIVED')
  ) then
    raise exception 'Purchase order is unavailable for receiving';
  end if;

  if jsonb_typeof(coalesce(p_items,'[]'::jsonb)) <> 'array'
     or jsonb_array_length(coalesce(p_items,'[]'::jsonb)) = 0 then
    raise exception 'At least one received item is required';
  end if;

  insert into public.goods_receipts(
    supplier_id,purchase_order_id,supplier_invoice_number,
    supplier_invoice_date,received_by,status,notes
  )
  values (
    p_supplier_id,p_purchase_order_id,
    nullif(btrim(coalesce(p_supplier_invoice_number,'')), ''),
    p_supplier_invoice_date,auth.uid(),'DRAFT',
    nullif(btrim(coalesce(p_notes,'')), '')
  )
  returning * into v_receipt;

  for v_line in select value from jsonb_array_elements(p_items)
  loop
    v_inventory_item_id := nullif(v_line ->> 'inventory_item_id','')::uuid;
    v_purchase_uom_id := nullif(v_line ->> 'purchase_uom_id','')::uuid;
    v_po_item_id := nullif(v_line ->> 'purchase_order_item_id','')::uuid;
    v_purchase_qty := nullif(v_line ->> 'purchase_quantity','')::numeric;
    v_base_per_unit := nullif(v_line ->> 'base_quantity_per_purchase_unit','')::numeric;
    v_unit_cost_purchase := nullif(v_line ->> 'unit_cost_purchase_uom','')::numeric;
    v_expiration := nullif(v_line ->> 'expiration_date','')::date;
    v_lot_code := nullif(btrim(coalesce(v_line ->> 'lot_code','')), '');

    if v_purchase_qty is null or v_purchase_qty <= 0
       or v_base_per_unit is null or v_base_per_unit <= 0
       or v_unit_cost_purchase is null or v_unit_cost_purchase < 0 then
      raise exception 'Invalid received item values';
    end if;

    if not exists (
      select 1 from public.inventory_items
      where id = v_inventory_item_id and is_active = true
    ) then
      raise exception 'Inventory item is unavailable';
    end if;

    v_base_qty := v_purchase_qty * v_base_per_unit;
    v_unit_cost_base := case
      when v_base_per_unit = 0 then 0
      else v_unit_cost_purchase / v_base_per_unit
    end;

    insert into public.goods_receipt_items(
      goods_receipt_id,purchase_order_item_id,inventory_item_id,purchase_uom_id,
      purchase_quantity,base_quantity_per_purchase_unit,base_quantity,
      unit_cost_purchase_uom,unit_cost_base,lot_code,expiration_date
    )
    values (
      v_receipt.id,v_po_item_id,v_inventory_item_id,v_purchase_uom_id,
      v_purchase_qty,v_base_per_unit,v_base_qty,v_unit_cost_purchase,
      v_unit_cost_base,v_lot_code,v_expiration
    );

    v_total := v_total + round(v_purchase_qty * v_unit_cost_purchase,2);
  end loop;

  perform public.post_goods_receipt(v_receipt.id);

  if coalesce(p_create_supplier_bill,true) then
    insert into public.supplier_bills(
      supplier_id,goods_receipt_id,supplier_invoice_number,invoice_date,
      due_date,amount,status,created_by,notes
    )
    values (
      p_supplier_id,v_receipt.id,
      nullif(btrim(coalesce(p_supplier_invoice_number,'')), ''),
      coalesce(p_supplier_invoice_date,current_date),p_due_date,v_total,
      case when v_total = 0 then 'PAID' else 'UNPAID' end,
      auth.uid(),'Created from posted goods receipt'
    );
  end if;

  select * into v_receipt
  from public.goods_receipts
  where id = v_receipt.id;

  return v_receipt;
end;
$$;

revoke all on function public.create_and_post_goods_receipt(
  uuid,jsonb,uuid,text,date,text,boolean,date
) from public, anon;
grant execute on function public.create_and_post_goods_receipt(
  uuid,jsonb,uuid,text,date,text,boolean,date
) to authenticated;
