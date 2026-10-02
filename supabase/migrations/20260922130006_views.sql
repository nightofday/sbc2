-- 0006_views.sql
-- Operational/reporting views.
-- security_invoker keeps underlying RLS behavior on supported PostgreSQL versions.

create or replace view public.v_inventory_stock
with (security_invoker = true)
as
select
  ii.id as inventory_item_id,
  ii.sku,
  ii.name,
  ii.track_inventory,
  ii.track_expiry,
  ii.reorder_level,
  ii.reorder_target,
  u.code as base_uom_code,
  coalesce(sum(
    case
      when il.status in ('AVAILABLE','DEPLETED') then il.remaining_quantity
      else 0
    end
  ),0)::numeric(14,4) as current_quantity
from public.inventory_items ii
join public.units_of_measure u on u.id = ii.base_uom_id
left join public.inventory_lots il on il.inventory_item_id = ii.id
where ii.is_active = true
group by ii.id, ii.sku, ii.name, ii.track_inventory, ii.track_expiry,
         ii.reorder_level, ii.reorder_target, u.code;

create or replace view public.v_low_stock
with (security_invoker = true)
as
select *
from public.v_inventory_stock
where track_inventory = true
  and current_quantity <= reorder_level;

create or replace view public.v_expiring_inventory_lots
with (security_invoker = true)
as
select
  il.id as lot_id,
  ii.id as inventory_item_id,
  ii.name as item_name,
  il.lot_code,
  il.expiration_date,
  il.remaining_quantity,
  u.code as uom_code,
  (il.expiration_date - current_date) as days_until_expiry
from public.inventory_lots il
join public.inventory_items ii on ii.id = il.inventory_item_id
join public.units_of_measure u on u.id = ii.base_uom_id
where il.remaining_quantity > 0
  and il.status = 'AVAILABLE'
  and il.expiration_date is not null;

create or replace view public.v_order_cogs
with (security_invoker = true)
as
select
  sm.order_id,
  round(sum(abs(sm.quantity_delta) * sm.unit_cost_base),2) as cogs
from public.stock_movements sm
where sm.movement_type = 'SALE_CONSUMPTION'
  and sm.order_id is not null
group by sm.order_id;

create or replace view public.v_daily_sales
with (security_invoker = true)
as
select
  (o.completed_at at time zone 'Asia/Manila')::date as sales_date,
  count(*) as completed_orders,
  round(sum(o.total_amount),2) as gross_sales,
  round(coalesce(sum(r.refunded_amount),0),2) as refunds,
  round(sum(o.total_amount) - coalesce(sum(r.refunded_amount),0),2) as net_sales
from public.orders o
left join (
  select order_id, sum(total_amount) as refunded_amount
  from public.refunds
  where status = 'COMPLETED'
  group by order_id
) r on r.order_id = o.id
where o.completed_at is not null
  and o.status in ('COMPLETED','PARTIALLY_REFUNDED','REFUNDED')
group by (o.completed_at at time zone 'Asia/Manila')::date;

create or replace view public.v_product_sales
with (security_invoker = true)
as
select
  oi.menu_item_id,
  oi.menu_variant_id,
  oi.item_name_snapshot,
  oi.variant_name_snapshot,
  sum(oi.quantity) as quantity_sold,
  round(sum(oi.line_total),2) as gross_line_sales
from public.order_items oi
join public.orders o on o.id = oi.order_id
where o.status in ('COMPLETED','PARTIALLY_REFUNDED','REFUNDED')
group by oi.menu_item_id, oi.menu_variant_id, oi.item_name_snapshot, oi.variant_name_snapshot;

create or replace view public.v_shift_summary
with (security_invoker = true)
as
select
  s.id as shift_id,
  s.shift_number,
  s.employee_id,
  coalesce(p.display_name, concat_ws(' ',p.first_name,p.last_name)) as employee_name,
  s.started_at,
  s.ended_at,
  s.opening_cash,
  s.expected_closing_cash,
  s.closing_cash_counted,
  s.cash_variance,
  count(distinct o.id) filter (where o.status in ('COMPLETED','PARTIALLY_REFUNDED','REFUNDED')) as orders_handled,
  round(coalesce(sum(o.total_amount) filter (where o.status in ('COMPLETED','PARTIALLY_REFUNDED','REFUNDED')),0),2) as gross_order_value
from public.shifts s
join public.profiles p on p.id = s.employee_id
left join public.orders o on o.shift_id = s.id
group by s.id, s.shift_number, s.employee_id, p.display_name, p.first_name, p.last_name,
         s.started_at, s.ended_at, s.opening_cash, s.expected_closing_cash,
         s.closing_cash_counted, s.cash_variance;

create or replace view public.v_supplier_balances
with (security_invoker = true)
as
select
  sb.id as supplier_bill_id,
  sb.supplier_id,
  s.name as supplier_name,
  sb.supplier_invoice_number,
  sb.invoice_date,
  sb.due_date,
  sb.amount,
  coalesce(sum(sbp.amount),0)::numeric(14,2) as amount_paid,
  (sb.amount - coalesce(sum(sbp.amount),0))::numeric(14,2) as balance
from public.supplier_bills sb
join public.suppliers s on s.id = sb.supplier_id
left join public.supplier_bill_payments sbp on sbp.supplier_bill_id = sb.id
where sb.status <> 'VOID'
group by sb.id, sb.supplier_id, s.name, sb.supplier_invoice_number,
         sb.invoice_date, sb.due_date, sb.amount;

create or replace view public.v_daily_profit_estimate
with (security_invoker = true)
as
with sales as (
  select
    (o.completed_at at time zone 'Asia/Manila')::date as d,
    sum(o.total_amount) as gross_sales,
    coalesce(sum(r.refunded_amount),0) as refunds
  from public.orders o
  left join (
    select order_id, sum(total_amount) as refunded_amount
    from public.refunds
    where status = 'COMPLETED'
    group by order_id
  ) r on r.order_id = o.id
  where o.completed_at is not null
    and o.status in ('COMPLETED','PARTIALLY_REFUNDED','REFUNDED')
  group by (o.completed_at at time zone 'Asia/Manila')::date
),
cogs as (
  select
    (sm.created_at at time zone 'Asia/Manila')::date as d,
    sum(abs(sm.quantity_delta) * sm.unit_cost_base) as cogs
  from public.stock_movements sm
  where sm.movement_type = 'SALE_CONSUMPTION'
  group by (sm.created_at at time zone 'Asia/Manila')::date
),
expenses as (
  select
    expense_date as d,
    sum(amount) as operating_expenses
  from public.expenses
  where status = 'POSTED'
  group by expense_date
)
select
  s.d as report_date,
  round(s.gross_sales,2) as gross_sales,
  round(s.refunds,2) as refunds,
  round(s.gross_sales - s.refunds,2) as net_sales,
  round(coalesce(c.cogs,0),2) as cogs,
  round((s.gross_sales - s.refunds) - coalesce(c.cogs,0),2) as estimated_gross_profit,
  round(coalesce(e.operating_expenses,0),2) as operating_expenses,
  round((s.gross_sales - s.refunds) - coalesce(c.cogs,0) - coalesce(e.operating_expenses,0),2)
    as estimated_operating_result
from sales s
left join cogs c on c.d = s.d
left join expenses e on e.d = s.d;
