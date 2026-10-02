-- Phase 7: make report periods consistent and provide one management-only
-- transaction trace across sales, refunds, inventory, purchasing and expenses.

create index if not exists idx_orders_completed_at
on public.orders(completed_at desc)
where completed_at is not null;

create index if not exists idx_refunds_completed_created_at
on public.refunds(created_at desc)
where status = 'COMPLETED';

create index if not exists idx_refund_items_order_item
on public.refund_items(order_item_id);

create index if not exists idx_payments_refund
on public.payments(refund_id, processed_at desc)
where refund_id is not null;

create index if not exists idx_expenses_posted_date
on public.expenses(expense_date desc)
where status = 'POSTED';

create index if not exists idx_goods_receipts_posted_at
on public.goods_receipts(posted_at desc)
where status = 'POSTED';

create index if not exists idx_stock_counts_posted_at
on public.stock_counts(posted_at desc)
where status = 'POSTED';

create index if not exists idx_supplier_bill_payments_paid_at
on public.supplier_bill_payments(paid_at desc);

create or replace view public.v_product_sales_daily
with (security_invoker = true)
as
with refunded as (
  select
    ri.order_item_id,
    sum(ri.quantity)::numeric(14,4) as refunded_quantity,
    sum(ri.refund_amount)::numeric(14,2) as refunded_amount
  from public.refund_items ri
  join public.refunds r on r.id = ri.refund_id
  where r.status = 'COMPLETED'
  group by ri.order_item_id
)
select
  (o.completed_at at time zone 'Asia/Manila')::date as sales_date,
  oi.menu_item_id,
  oi.menu_variant_id,
  oi.item_name_snapshot,
  oi.variant_name_snapshot,
  sum(oi.quantity)::numeric(14,4) as quantity_sold,
  coalesce(sum(refunded.refunded_quantity), 0)::numeric(14,4)
    as quantity_refunded,
  (
    sum(oi.quantity) - coalesce(sum(refunded.refunded_quantity), 0)
  )::numeric(14,4) as net_quantity_sold,
  round(sum(oi.line_total), 2)::numeric(14,2) as gross_line_sales,
  round(coalesce(sum(refunded.refunded_amount), 0), 2)::numeric(14,2)
    as refunded_line_amount,
  round(
    sum(oi.line_total) - coalesce(sum(refunded.refunded_amount), 0),
    2
  )::numeric(14,2) as net_line_sales
from public.order_items oi
join public.orders o on o.id = oi.order_id
left join refunded on refunded.order_item_id = oi.id
where o.completed_at is not null
  and o.status in ('COMPLETED', 'PARTIALLY_REFUNDED', 'REFUNDED')
  and (
    public.has_permission('reports.view')
    or public.has_permission('finance.view')
  )
group by
  (o.completed_at at time zone 'Asia/Manila')::date,
  oi.menu_item_id,
  oi.menu_variant_id,
  oi.item_name_snapshot,
  oi.variant_name_snapshot;

grant select on public.v_product_sales_daily to authenticated;
revoke all on public.v_product_sales_daily from anon;

create or replace view public.v_business_transaction_trace
with (security_invoker = true)
as
with order_payment_references as (
  select
    p.order_id,
    max(nullif(btrim(p.external_reference), '')) as external_reference
  from public.payments p
  where p.transaction_type = 'PAYMENT'
    and p.status = 'COMPLETED'
  group by p.order_id
),
refund_payment_references as (
  select
    p.refund_id,
    max(nullif(btrim(p.external_reference), '')) as external_reference
  from public.payments p
  where p.transaction_type = 'REFUND'
    and p.status = 'COMPLETED'
  group by p.refund_id
),
goods_receipt_totals as (
  select
    gri.goods_receipt_id,
    count(*)::integer as line_count,
    round(
      sum(gri.purchase_quantity * gri.unit_cost_purchase_uom),
      2
    )::numeric(14,2) as receipt_total
  from public.goods_receipt_items gri
  group by gri.goods_receipt_id
),
stock_out_totals as (
  select
    soi.stock_out_id,
    count(*)::integer as line_count
  from public.stock_out_items soi
  group by soi.stock_out_id
),
stock_count_totals as (
  select
    sci.stock_count_id,
    count(*)::integer as line_count
  from public.stock_count_items sci
  group by sci.stock_count_id
)
select
  'SALE:' || o.id::text as event_key,
  o.completed_at as occurred_at,
  'SALE'::text as event_type,
  'ORD-' || o.order_number::text as document_number,
  coalesce(opr.external_reference, o.delivery_reference) as external_reference,
  replace(initcap(lower(o.order_type)), '_', ' ') as description,
  coalesce(nullif(btrim(o.customer_name), ''), 'Walk-in Customer')
    as party_name,
  o.total_amount::numeric(14,2) as amount,
  coalesce(
    nullif(btrim(p.display_name), ''),
    nullif(btrim(concat_ws(' ', p.first_name, p.last_name)), ''),
    o.employee_name_snapshot,
    'Unknown Employee'
  ) as actor_name,
  o.status
from public.orders o
left join public.profiles p on p.id = o.created_by_user_id
left join order_payment_references opr on opr.order_id = o.id
where o.completed_at is not null
  and o.status in ('COMPLETED', 'PARTIALLY_REFUNDED', 'REFUNDED')
  and public.has_permission('reports.view')

union all

select
  'REFUND:' || r.id::text,
  r.created_at,
  'REFUND'::text,
  'RF-' || r.refund_number::text,
  rpr.external_reference,
  r.reason,
  coalesce(nullif(btrim(o.customer_name), ''), 'Walk-in Customer'),
  (-r.total_amount)::numeric(14,2),
  coalesce(
    nullif(btrim(p.display_name), ''),
    nullif(btrim(concat_ws(' ', p.first_name, p.last_name)), ''),
    'Unknown Employee'
  ),
  r.status
from public.refunds r
join public.orders o on o.id = r.order_id
left join public.profiles p on p.id = r.requested_by
left join refund_payment_references rpr on rpr.refund_id = r.id
where r.status = 'COMPLETED'
  and public.has_permission('reports.view')

union all

select
  'GOODS_RECEIPT:' || gr.id::text,
  coalesce(gr.posted_at, gr.received_at),
  'STOCK_IN'::text,
  'GR-' || gr.receipt_number::text,
  gr.supplier_invoice_number,
  coalesce(grt.line_count, 0)::text || ' item(s) received',
  s.name,
  coalesce(grt.receipt_total, 0)::numeric(14,2),
  coalesce(
    nullif(btrim(p.display_name), ''),
    nullif(btrim(concat_ws(' ', p.first_name, p.last_name)), ''),
    'Unknown Employee'
  ),
  gr.status
from public.goods_receipts gr
join public.suppliers s on s.id = gr.supplier_id
left join public.profiles p on p.id = gr.received_by
left join goods_receipt_totals grt on grt.goods_receipt_id = gr.id
where gr.status = 'POSTED'
  and public.has_permission('reports.view')

union all

select
  'STOCK_OUT:' || so.id::text,
  coalesce(so.posted_at, so.occurred_at),
  'STOCK_OUT'::text,
  'SO-' || so.stock_out_number::text,
  so.reference_number,
  so.purpose || ' · ' || coalesce(sot.line_count, 0)::text || ' item(s)',
  null::text,
  null::numeric(14,2),
  coalesce(
    nullif(btrim(p.display_name), ''),
    nullif(btrim(concat_ws(' ', p.first_name, p.last_name)), ''),
    'Unknown Employee'
  ),
  so.status
from public.stock_out_transactions so
left join public.profiles p on p.id = so.recorded_by
left join stock_out_totals sot on sot.stock_out_id = so.id
where so.status = 'POSTED'
  and public.has_permission('reports.view')

union all

select
  'STOCK_COUNT:' || sc.id::text,
  coalesce(sc.posted_at, sc.counted_at),
  'INVENTORY_COUNT'::text,
  'IC-' || sc.count_number::text,
  null::text,
  coalesce(nullif(btrim(sc.notes), ''), 'Physical inventory count')
    || ' · ' || coalesce(sct.line_count, 0)::text || ' item(s)',
  null::text,
  null::numeric(14,2),
  coalesce(
    nullif(btrim(p.display_name), ''),
    nullif(btrim(concat_ws(' ', p.first_name, p.last_name)), ''),
    'Unknown Employee'
  ),
  sc.status
from public.stock_counts sc
left join public.profiles p on p.id = coalesce(sc.posted_by, sc.counted_by)
left join stock_count_totals sct on sct.stock_count_id = sc.id
where sc.status = 'POSTED'
  and public.has_permission('reports.view')

union all

select
  'EXPENSE:' || e.id::text,
  e.expense_date::timestamp at time zone 'Asia/Manila',
  'EXPENSE'::text,
  'EX-' || e.expense_number::text,
  e.reference_number,
  ec.name || ': ' || e.description,
  s.name,
  (-e.amount)::numeric(14,2),
  coalesce(
    nullif(btrim(p.display_name), ''),
    nullif(btrim(concat_ws(' ', p.first_name, p.last_name)), ''),
    'Unknown Employee'
  ),
  e.status
from public.expenses e
join public.expense_categories ec on ec.id = e.expense_category_id
join public.suppliers s on s.id = e.supplier_id
left join public.profiles p on p.id = e.recorded_by
where e.status = 'POSTED'
  and public.has_permission('reports.view')

union all

select
  'SUPPLIER_PAYMENT:' || sbp.id::text,
  sbp.paid_at,
  'SUPPLIER_PAYMENT'::text,
  'BILL-' || coalesce(sb.supplier_invoice_number, left(sb.id::text, 8)),
  sbp.reference_number,
  'Supplier bill payment via ' || pm.name,
  s.name,
  (-sbp.amount)::numeric(14,2),
  coalesce(
    nullif(btrim(p.display_name), ''),
    nullif(btrim(concat_ws(' ', p.first_name, p.last_name)), ''),
    'Unknown Employee'
  ),
  'COMPLETED'::text
from public.supplier_bill_payments sbp
join public.supplier_bills sb on sb.id = sbp.supplier_bill_id
join public.suppliers s on s.id = sb.supplier_id
join public.payment_methods pm on pm.id = sbp.payment_method_id
left join public.profiles p on p.id = sbp.recorded_by
where public.has_permission('reports.view');

grant select on public.v_business_transaction_trace to authenticated;
revoke all on public.v_business_transaction_trace from anon;
