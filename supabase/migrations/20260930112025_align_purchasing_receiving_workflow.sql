-- Phase 5: practical, traceable multi-item purchasing and receiving.

create or replace function public.guard_goods_receipt_reference()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.supplier_invoice_number :=
    nullif(btrim(coalesce(new.supplier_invoice_number, '')), '');

  if new.supplier_invoice_number is null then
    raise exception 'Supplier invoice or grocery receipt number is required';
  end if;

  if new.supplier_invoice_date is null then
    raise exception 'Supplier invoice or grocery receipt date is required';
  end if;

  if exists (
    select 1
    from public.goods_receipts gr
    where gr.supplier_id = new.supplier_id
      and lower(btrim(gr.supplier_invoice_number)) =
        lower(new.supplier_invoice_number)
      and gr.status <> 'CANCELLED'
      and gr.id is distinct from new.id
  ) then
    raise exception 'This supplier invoice or grocery receipt is already recorded';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_guard_goods_receipt_reference
on public.goods_receipts;

create trigger trg_guard_goods_receipt_reference
before insert or update of
  supplier_id, supplier_invoice_number, supplier_invoice_date
on public.goods_receipts
for each row execute function public.guard_goods_receipt_reference();

revoke all on function public.guard_goods_receipt_reference()
from public, anon, authenticated;

create index if not exists idx_goods_receipts_supplier_reference
on public.goods_receipts(
  supplier_id,
  lower(btrim(supplier_invoice_number))
)
where supplier_invoice_number is not null
  and status <> 'CANCELLED';

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
  coalesce(
    sum(gri.purchase_quantity * gri.unit_cost_purchase_uom),
    0
  )::numeric(14,2) as receipt_total,
  gr.received_by,
  coalesce(p.display_name, concat_ws(' ', p.first_name, p.last_name))
    as received_by_name
from public.goods_receipts gr
join public.suppliers s on s.id = gr.supplier_id
left join public.purchase_orders po on po.id = gr.purchase_order_id
left join public.goods_receipt_items gri on gri.goods_receipt_id = gr.id
left join public.profiles p on p.id = gr.received_by
group by
  gr.id,
  s.name,
  po.purchase_order_number,
  p.display_name,
  p.first_name,
  p.last_name;

grant select on public.v_goods_receipt_summary to authenticated;
revoke all on public.v_goods_receipt_summary from anon;

create or replace view public.v_goods_receipt_line_details
with (security_invoker = true)
as
select
  gri.id,
  gri.goods_receipt_id,
  gri.purchase_order_item_id,
  gri.inventory_item_id,
  ii.name as inventory_item_name,
  gri.purchase_uom_id,
  pu.code as purchase_uom_code,
  gri.purchase_quantity,
  gri.base_quantity_per_purchase_unit,
  gri.base_quantity,
  bu.code as base_uom_code,
  gri.unit_cost_purchase_uom,
  round(
    gri.purchase_quantity * gri.unit_cost_purchase_uom,
    2
  )::numeric(14,2) as line_total,
  gri.lot_code,
  gri.expiration_date,
  il.id as inventory_lot_id,
  il.remaining_quantity,
  il.status as lot_status
from public.goods_receipt_items gri
join public.inventory_items ii on ii.id = gri.inventory_item_id
join public.units_of_measure pu on pu.id = gri.purchase_uom_id
join public.units_of_measure bu on bu.id = ii.base_uom_id
left join public.inventory_lots il on il.goods_receipt_item_id = gri.id;

grant select on public.v_goods_receipt_line_details to authenticated;
revoke all on public.v_goods_receipt_line_details from anon;
