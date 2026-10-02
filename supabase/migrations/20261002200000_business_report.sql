-- FIN-01, REP-01 to REP-04, S-02, S-03: one set of report definitions.
--
-- Dashboard, Finance and Reports each computed sales their own way:
--   * "gross sales" was the order total after discounts, so discounts were
--     invisible;
--   * the daily views subtracted a refund on the day of the original sale,
--     while the dashboard subtracted it on the day it was refunded;
--   * reports covered only the last 7 or 30 days and the top 10 products.
--
-- Definitions used from now on, the same ones a commercial POS reports:
--   gross sales  = what was sold at menu prices, before discounts
--   discounts    = discounts given on those sales
--   refunds      = money refunded, counted on the day of the refund
--   net sales    = gross sales - discounts - refunds
-- Every figure is attributed to a business day in the café's time zone.
-- Sales and refunds are transaction-date figures: a sale on Monday refunded
-- on Tuesday is a Monday sale and a Tuesday refund.
--
-- Purchases, supplier payments, expenses and stock losses are reported
-- beside sales, never added together, and nothing here is called profit.

create function public.business_timezone()
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    (select bp.timezone from public.business_profile bp where bp.id = 1),
    'Asia/Manila'
  );
$$;

revoke all on function public.business_timezone() from public, anon;
grant execute on function public.business_timezone() to authenticated;

create function public.get_business_report(p_from date, p_to date)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tz text := public.business_timezone();
  v_start timestamptz;
  v_end timestamptz;
  v_summary jsonb;
  v_by_day jsonb;
  v_by_payment jsonb;
  v_by_item jsonb;
  v_by_category jsonb;
  v_by_discount jsonb;
  v_by_employee jsonb;
  v_refunds jsonb;
  v_expenses jsonb;
  v_losses jsonb;
  v_expired jsonb;
  v_inventory jsonb;
begin
  if not (
    public.has_permission('reports.view')
    or public.has_permission('finance.view')
  ) then
    raise exception 'Permission denied';
  end if;

  if p_from is null or p_to is null or p_to < p_from then
    raise exception 'Choose a start date that is not after the end date';
  end if;

  if p_to - p_from > 366 then
    raise exception 'A report can cover at most 366 days';
  end if;

  -- The period as timestamps, so the date indexes are used.
  v_start := p_from::timestamp at time zone v_tz;
  v_end := (p_to + 1)::timestamp at time zone v_tz;

  -- Summary ---------------------------------------------------------------
  with sales as (
    select o.subtotal, o.discount_amount
    from public.orders o
    where o.completed_at >= v_start
      and o.completed_at < v_end
      and o.status in ('COMPLETED', 'PARTIALLY_REFUNDED', 'REFUNDED')
  ),
  totals as (
    select
      coalesce(sum(s.subtotal), 0)::numeric(14,2) as gross_sales,
      coalesce(sum(s.discount_amount), 0)::numeric(14,2) as discounts,
      count(*)::integer as orders
    from sales s
  ),
  refund_totals as (
    select
      coalesce(sum(r.total_amount), 0)::numeric(14,2) as refunds,
      count(*)::integer as refund_count
    from public.refunds r
    where r.status = 'COMPLETED'
      and r.created_at >= v_start
      and r.created_at < v_end
  ),
  expense_totals as (
    select coalesce(sum(e.amount), 0)::numeric(14,2) as expenses
    from public.expenses e
    where e.status = 'POSTED'
      and e.expense_date between p_from and p_to
  ),
  purchase_totals as (
    select coalesce(
      sum(round(gri.purchase_quantity * gri.unit_cost_purchase_uom, 2)), 0
    )::numeric(14,2) as purchases
    from public.goods_receipts gr
    join public.goods_receipt_items gri on gri.goods_receipt_id = gr.id
    where gr.status = 'POSTED'
      and gr.posted_at >= v_start
      and gr.posted_at < v_end
  ),
  supplier_payment_totals as (
    select coalesce(sum(sbp.amount), 0)::numeric(14,2) as supplier_payments
    from public.supplier_bill_payments sbp
    where sbp.paid_at >= v_start
      and sbp.paid_at < v_end
  ),
  loss_totals as (
    select coalesce(
      sum(round(abs(sm.quantity_delta) * sm.unit_cost_base, 2)), 0
    )::numeric(14,2) as stock_loss_cost
    from public.stock_movements sm
    where sm.movement_type in ('WASTE', 'DAMAGED', 'EXPIRED')
      and sm.created_at >= v_start
      and sm.created_at < v_end
  )
  select jsonb_build_object(
    'gross_sales', t.gross_sales,
    'discounts', t.discounts,
    'refunds', r.refunds,
    'net_sales', t.gross_sales - t.discounts - r.refunds,
    'orders', t.orders,
    'refund_count', r.refund_count,
    'average_order', case
      when t.orders = 0 then 0
      else round((t.gross_sales - t.discounts) / t.orders, 2)
    end,
    'expenses', e.expenses,
    'net_sales_less_expenses',
      t.gross_sales - t.discounts - r.refunds - e.expenses,
    'purchases', p.purchases,
    'supplier_payments', sp.supplier_payments,
    'stock_loss_cost', l.stock_loss_cost
  )
  into v_summary
  from totals t, refund_totals r, expense_totals e, purchase_totals p,
       supplier_payment_totals sp, loss_totals l;

  -- By day ----------------------------------------------------------------
  with days as (
    select d::date as day
    from generate_series(p_from::timestamp, p_to::timestamp, interval '1 day') d
  ),
  sales as (
    select
      (o.completed_at at time zone v_tz)::date as day,
      count(*)::integer as orders,
      sum(o.subtotal) as gross_sales,
      sum(o.discount_amount) as discounts
    from public.orders o
    where o.completed_at >= v_start
      and o.completed_at < v_end
      and o.status in ('COMPLETED', 'PARTIALLY_REFUNDED', 'REFUNDED')
    group by 1
  ),
  refunded as (
    select
      (r.created_at at time zone v_tz)::date as day,
      sum(r.total_amount) as refunds
    from public.refunds r
    where r.status = 'COMPLETED'
      and r.created_at >= v_start
      and r.created_at < v_end
    group by 1
  ),
  spent as (
    select e.expense_date as day, sum(e.amount) as expenses
    from public.expenses e
    where e.status = 'POSTED'
      and e.expense_date between p_from and p_to
    group by 1
  )
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'date', d.day,
      'orders', coalesce(s.orders, 0),
      'gross_sales', coalesce(s.gross_sales, 0)::numeric(14,2),
      'discounts', coalesce(s.discounts, 0)::numeric(14,2),
      'refunds', coalesce(rf.refunds, 0)::numeric(14,2),
      'net_sales', (
        coalesce(s.gross_sales, 0) - coalesce(s.discounts, 0)
        - coalesce(rf.refunds, 0)
      )::numeric(14,2),
      'expenses', coalesce(sp.expenses, 0)::numeric(14,2)
    )
    order by d.day
  ), '[]'::jsonb)
  into v_by_day
  from days d
  left join sales s on s.day = d.day
  left join refunded rf on rf.day = d.day
  left join spent sp on sp.day = d.day;

  -- By payment method -----------------------------------------------------
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'payment_method', x.name,
      'payments', x.payments,
      'refunds', x.refunds,
      'net_collected', x.payments - x.refunds,
      'transactions', x.transactions
    )
    order by x.sort_order, x.name
  ), '[]'::jsonb)
  into v_by_payment
  from (
    select
      pm.name,
      pm.sort_order,
      coalesce(sum(p.amount) filter (
        where p.transaction_type = 'PAYMENT'
      ), 0)::numeric(14,2) as payments,
      coalesce(sum(p.amount) filter (
        where p.transaction_type = 'REFUND'
      ), 0)::numeric(14,2) as refunds,
      count(*) filter (where p.transaction_type = 'PAYMENT')::integer
        as transactions
    from public.payments p
    join public.payment_methods pm on pm.id = p.payment_method_id
    where p.status = 'COMPLETED'
      and p.processed_at >= v_start
      and p.processed_at < v_end
    group by pm.name, pm.sort_order
  ) x;

  -- By item and by category -------------------------------------------------
  with sold as (
    select
      oi.id as order_item_id,
      oi.item_name_snapshot as item_name,
      coalesce(oi.variant_name_snapshot, '') as variant_name,
      coalesce(mc.name, 'Uncategorised') as category_name,
      oi.quantity,
      oi.line_subtotal as gross_sales,
      oi.discount_amount + coalesce((
        select sum(odi.discount_amount)
        from public.order_discount_items odi
        where odi.order_item_id = oi.id
      ), 0) as discounts
    from public.order_items oi
    join public.orders o on o.id = oi.order_id
    left join public.menu_items mi on mi.id = oi.menu_item_id
    left join public.menu_categories mc on mc.id = mi.category_id
    where o.completed_at >= v_start
      and o.completed_at < v_end
      and o.status in ('COMPLETED', 'PARTIALLY_REFUNDED', 'REFUNDED')
  ),
  refunded as (
    select
      oi.item_name_snapshot as item_name,
      coalesce(oi.variant_name_snapshot, '') as variant_name,
      coalesce(mc.name, 'Uncategorised') as category_name,
      ri.quantity,
      ri.refund_amount
    from public.refund_items ri
    join public.refunds r on r.id = ri.refund_id
    join public.order_items oi on oi.id = ri.order_item_id
    left join public.menu_items mi on mi.id = oi.menu_item_id
    left join public.menu_categories mc on mc.id = mi.category_id
    where r.status = 'COMPLETED'
      and r.created_at >= v_start
      and r.created_at < v_end
  ),
  item_sales as (
    select
      item_name, variant_name, category_name,
      sum(quantity) as quantity_sold,
      sum(gross_sales) as gross_sales,
      sum(discounts) as discounts
    from sold
    group by 1, 2, 3
  ),
  item_refunds as (
    select
      item_name, variant_name, category_name,
      sum(quantity) as quantity_refunded,
      sum(refund_amount) as refunds
    from refunded
    group by 1, 2, 3
  ),
  items as (
    select
      coalesce(s.item_name, r.item_name) as item_name,
      coalesce(s.variant_name, r.variant_name) as variant_name,
      coalesce(s.category_name, r.category_name) as category_name,
      coalesce(s.quantity_sold, 0) as quantity_sold,
      coalesce(r.quantity_refunded, 0) as quantity_refunded,
      coalesce(s.gross_sales, 0) as gross_sales,
      coalesce(s.discounts, 0) as discounts,
      coalesce(r.refunds, 0) as refunds
    from item_sales s
    full outer join item_refunds r
      on r.item_name = s.item_name
     and r.variant_name = s.variant_name
     and r.category_name = s.category_name
  )
  select
    coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'item_name', i.item_name,
          'variant_name', i.variant_name,
          'category_name', i.category_name,
          'quantity_sold', i.quantity_sold,
          'quantity_refunded', i.quantity_refunded,
          'gross_sales', i.gross_sales::numeric(14,2),
          'discounts', i.discounts::numeric(14,2),
          'refunds', i.refunds::numeric(14,2),
          'net_sales', (i.gross_sales - i.discounts - i.refunds)::numeric(14,2)
        )
        order by (i.gross_sales - i.discounts - i.refunds) desc,
                 i.item_name, i.variant_name
      )
      from items i
    ), '[]'::jsonb),
    coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'category_name', c.category_name,
          'quantity_sold', c.quantity_sold,
          'gross_sales', c.gross_sales::numeric(14,2),
          'discounts', c.discounts::numeric(14,2),
          'refunds', c.refunds::numeric(14,2),
          'net_sales', (c.gross_sales - c.discounts - c.refunds)::numeric(14,2)
        )
        order by (c.gross_sales - c.discounts - c.refunds) desc,
                 c.category_name
      )
      from (
        select
          i.category_name,
          sum(i.quantity_sold) as quantity_sold,
          sum(i.gross_sales) as gross_sales,
          sum(i.discounts) as discounts,
          sum(i.refunds) as refunds
        from items i
        group by i.category_name
      ) c
    ), '[]'::jsonb)
  into v_by_item, v_by_category;

  -- By discount -------------------------------------------------------------
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'discount_name', x.discount_name,
      'times_used', x.times_used,
      'amount', x.amount
    )
    order by x.amount desc, x.discount_name
  ), '[]'::jsonb)
  into v_by_discount
  from (
    select
      od.discount_name_snapshot as discount_name,
      count(*)::integer as times_used,
      sum(od.discount_amount)::numeric(14,2) as amount
    from public.order_discounts od
    join public.orders o on o.id = od.order_id
    where o.completed_at >= v_start
      and o.completed_at < v_end
      and o.status in ('COMPLETED', 'PARTIALLY_REFUNDED', 'REFUNDED')
    group by od.discount_name_snapshot
  ) x;

  -- By employee -------------------------------------------------------------
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'employee_name', x.employee_name,
      'orders', x.orders,
      'gross_sales', x.gross_sales,
      'discounts', x.discounts,
      'sales_after_discounts', x.gross_sales - x.discounts
    )
    order by (x.gross_sales - x.discounts) desc, x.employee_name
  ), '[]'::jsonb)
  into v_by_employee
  from (
    select
      coalesce(nullif(btrim(o.employee_name_snapshot), ''), 'Unknown')
        as employee_name,
      count(*)::integer as orders,
      sum(o.subtotal)::numeric(14,2) as gross_sales,
      sum(o.discount_amount)::numeric(14,2) as discounts
    from public.orders o
    where o.completed_at >= v_start
      and o.completed_at < v_end
      and o.status in ('COMPLETED', 'PARTIALLY_REFUNDED', 'REFUNDED')
    group by 1
  ) x;

  -- Refunds -----------------------------------------------------------------
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'refund_number', r.refund_number,
      'order_number', o.order_number,
      'refunded_at', r.created_at,
      'sold_on', (o.completed_at at time zone v_tz)::date,
      'amount', r.total_amount,
      'reason', r.reason
    )
    order by r.created_at
  ), '[]'::jsonb)
  into v_refunds
  from public.refunds r
  join public.orders o on o.id = r.order_id
  where r.status = 'COMPLETED'
    and r.created_at >= v_start
    and r.created_at < v_end;

  -- Expenses by category ------------------------------------------------------
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'category_name', x.category_name,
      'entries', x.entries,
      'amount', x.amount
    )
    order by x.amount desc, x.category_name
  ), '[]'::jsonb)
  into v_expenses
  from (
    select
      ec.name as category_name,
      count(*)::integer as entries,
      sum(e.amount)::numeric(14,2) as amount
    from public.expenses e
    join public.expense_categories ec on ec.id = e.expense_category_id
    where e.status = 'POSTED'
      and e.expense_date between p_from and p_to
    group by ec.name
  ) x;

  -- Stock losses recorded in the period ----------------------------------------
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'item_name', x.item_name,
      'unit', x.unit,
      'reason', x.movement_type,
      'quantity', x.quantity,
      'cost', x.cost
    )
    order by x.cost desc, x.item_name, x.movement_type
  ), '[]'::jsonb)
  into v_losses
  from (
    select
      ii.name as item_name,
      u.code as unit,
      sm.movement_type,
      sum(abs(sm.quantity_delta))::numeric(14,4) as quantity,
      sum(round(abs(sm.quantity_delta) * sm.unit_cost_base, 2))::numeric(14,2)
        as cost
    from public.stock_movements sm
    join public.inventory_items ii on ii.id = sm.inventory_item_id
    join public.units_of_measure u on u.id = ii.base_uom_id
    where sm.movement_type in ('WASTE', 'DAMAGED', 'EXPIRED')
      and sm.created_at >= v_start
      and sm.created_at < v_end
    group by ii.name, u.code, sm.movement_type
  ) x;

  -- Expired stock still on hand today: exposure, not yet a recorded loss.
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'item_name', x.item_name,
      'unit', x.unit,
      'quantity', x.quantity,
      'cost', x.cost
    )
    order by x.item_name
  ), '[]'::jsonb)
  into v_expired
  from (
    select
      ii.name as item_name,
      u.code as unit,
      sum(il.remaining_quantity)::numeric(14,4) as quantity,
      sum(round(il.remaining_quantity * il.unit_cost_base, 2))::numeric(14,2)
        as cost
    from public.inventory_lots il
    join public.inventory_items ii on ii.id = il.inventory_item_id
    join public.units_of_measure u on u.id = ii.base_uom_id
    where il.status = 'AVAILABLE'
      and il.remaining_quantity > 0
      and il.expiration_date < (select public.business_today())
    group by ii.name, u.code
  ) x;

  -- Stock movement per item: opening + movements = closing ----------------------
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'item_name', x.item_name,
      'unit', x.unit,
      'opening', x.opening,
      'received', x.received,
      'sold', x.sold,
      'released', x.released,
      'lost', x.lost,
      'other', x.other,
      'closing', x.opening + x.received - x.sold - x.released - x.lost + x.other
    )
    order by x.item_name
  ), '[]'::jsonb)
  into v_inventory
  from (
    select
      ii.name as item_name,
      u.code as unit,
      coalesce(sum(sm.quantity_delta) filter (
        where sm.created_at < v_start
      ), 0)::numeric(14,4) as opening,
      -- A voided document's reversal is netted against the same column, so
      -- a release that was voided shows as nothing released.
      coalesce(sum(sm.quantity_delta) filter (
        where sm.created_at >= v_start
          and (
            sm.movement_type = 'PURCHASE_RECEIPT'
            or (
              sm.movement_type = 'REVERSAL'
              and sm.reference_type = 'GOODS_RECEIPT'
            )
          )
      ), 0)::numeric(14,4) as received,
      coalesce(-sum(sm.quantity_delta) filter (
        where sm.created_at >= v_start
          and sm.movement_type = 'SALE_CONSUMPTION'
      ), 0)::numeric(14,4) as sold,
      coalesce(-sum(sm.quantity_delta) filter (
        where sm.created_at >= v_start
          and sm.reference_type = 'STOCK_OUT'
          and sm.movement_type in ('MANUAL_OUT', 'REVERSAL')
      ), 0)::numeric(14,4) as released,
      coalesce(-sum(sm.quantity_delta) filter (
        where sm.created_at >= v_start
          and sm.movement_type in ('WASTE', 'DAMAGED', 'EXPIRED')
      ), 0)::numeric(14,4) as lost,
      -- Opening stock, count corrections, manual adjustments and refund
      -- restocks.
      coalesce(sum(sm.quantity_delta) filter (
        where sm.created_at >= v_start
          and sm.movement_type not in (
            'PURCHASE_RECEIPT', 'SALE_CONSUMPTION', 'WASTE', 'DAMAGED',
            'EXPIRED'
          )
          and not (
            sm.reference_type = 'STOCK_OUT'
            and sm.movement_type in ('MANUAL_OUT', 'REVERSAL')
          )
          and not (
            sm.movement_type = 'REVERSAL'
            and sm.reference_type = 'GOODS_RECEIPT'
          )
      ), 0)::numeric(14,4) as other
    from public.inventory_items ii
    join public.units_of_measure u on u.id = ii.base_uom_id
    left join public.stock_movements sm
      on sm.inventory_item_id = ii.id
     and sm.created_at < v_end
    where ii.track_inventory = true
    group by ii.name, u.code
    having count(sm.id) > 0
  ) x;

  return jsonb_build_object(
    'from', p_from,
    'to', p_to,
    'timezone', v_tz,
    'summary', v_summary,
    'by_day', v_by_day,
    'by_payment_method', v_by_payment,
    'by_item', v_by_item,
    'by_category', v_by_category,
    'by_discount', v_by_discount,
    'by_employee', v_by_employee,
    'refunds', v_refunds,
    'expenses_by_category', v_expenses,
    'stock_losses', v_losses,
    'expired_on_hand', v_expired,
    'stock_movement', v_inventory
  );
end;
$$;

revoke all on function public.get_business_report(date,date)
from public, anon;
grant execute on function public.get_business_report(date,date)
to authenticated;

-- The dashboard uses the same definitions for today. `gross_sales` used to
-- be the total after discounts; it is now before discounts, with the
-- discounts on their own key. `net_sales` is unchanged in value.
create or replace function public.get_dashboard_summary()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tz text := public.business_timezone();
  v_today date := public.business_today();
  v_start timestamptz := v_today::timestamp at time zone v_tz;
  v_end timestamptz := (v_today + 1)::timestamp at time zone v_tz;
  v_can_manage boolean := public.has_permission('reports.view')
                          or public.has_permission('finance.view')
                          or public.has_permission('orders.manage_all');
  v_gross numeric(14,2) := 0;
  v_discounts numeric(14,2) := 0;
  v_refunds numeric(14,2) := 0;
  v_orders bigint := 0;
  v_open_orders bigint := 0;
  v_expenses numeric(14,2) := 0;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  select
    coalesce(sum(o.subtotal), 0),
    coalesce(sum(o.discount_amount), 0),
    count(*)
  into v_gross, v_discounts, v_orders
  from public.orders o
  where o.completed_at >= v_start
    and o.completed_at < v_end
    and o.status in ('COMPLETED','PARTIALLY_REFUNDED','REFUNDED')
    and (v_can_manage or o.created_by_user_id = auth.uid());

  select coalesce(sum(r.total_amount), 0)
  into v_refunds
  from public.refunds r
  join public.orders o on o.id = r.order_id
  where r.status = 'COMPLETED'
    and r.created_at >= v_start
    and r.created_at < v_end
    and (v_can_manage or o.created_by_user_id = auth.uid());

  select count(*)
  into v_open_orders
  from public.orders o
  where o.created_at >= v_start
    and o.created_at < v_end
    and o.status in ('OPEN','PENDING_PAYMENT')
    and (v_can_manage or o.created_by_user_id = auth.uid());

  if v_can_manage then
    select coalesce(sum(e.amount), 0)
    into v_expenses
    from public.expenses e
    where e.expense_date = v_today
      and e.status = 'POSTED';
  end if;

  return jsonb_build_object(
    'report_date', v_today,
    'gross_sales', v_gross,
    'discounts', v_discounts,
    'refunds', v_refunds,
    'net_sales', v_gross - v_discounts - v_refunds,
    'completed_orders', v_orders,
    'open_orders', v_open_orders,
    'average_order', case
      when v_orders = 0 then 0
      else round((v_gross - v_discounts) / v_orders, 2)
    end,
    'expenses', case when v_can_manage then v_expenses else null end,
    'net_after_expenses', case
      when v_can_manage then v_gross - v_discounts - v_refunds - v_expenses
      else null
    end,
    'business_scope', v_can_manage
  );
end;
$$;
