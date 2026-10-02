-- Performance-only RLS rewrite: initialize auth.uid() once per statement.

alter policy "read own profile or manage users"
on public.profiles
using (
  id = (select auth.uid())
  or public.has_permission('users.view')
);

alter policy "own or manager read shifts"
on public.shifts
using (
  employee_id = (select auth.uid())
  or public.has_permission('shift.manage')
);

alter policy "own or manager read shift cash movements"
on public.shift_cash_movements
using (
  exists (
    select 1
    from public.shifts s
    where s.id = shift_id
      and (
        s.employee_id = (select auth.uid())
        or public.has_permission('shift.manage')
      )
  )
);

alter policy "authorized shift cash movement insert"
on public.shift_cash_movements
with check (
  recorded_by = (select auth.uid())
  and public.has_permission('shift.cash_movement')
);

alter policy "order select"
on public.orders
using (
  public.has_permission('orders.manage_all')
  or created_by_user_id = (select auth.uid())
);

alter policy "order items select"
on public.order_items
using (
  exists (
    select 1
    from public.orders o
    where o.id = order_id
      and (
        o.created_by_user_id = (select auth.uid())
        or public.has_permission('orders.manage_all')
      )
  )
);

alter policy "order modifiers select"
on public.order_item_modifiers
using (
  exists (
    select 1
    from public.order_items oi
    join public.orders o on o.id = oi.order_id
    where oi.id = order_item_id
      and (
        o.created_by_user_id = (select auth.uid())
        or public.has_permission('orders.manage_all')
      )
  )
);

alter policy "order discounts select"
on public.order_discounts
using (
  exists (
    select 1
    from public.orders o
    where o.id = order_id
      and (
        o.created_by_user_id = (select auth.uid())
        or public.has_permission('orders.manage_all')
      )
  )
);

alter policy "payments select"
on public.payments
using (
  exists (
    select 1
    from public.orders o
    where o.id = order_id
      and (
        o.created_by_user_id = (select auth.uid())
        or public.has_permission('orders.manage_all')
        or public.has_permission('finance.view')
      )
  )
);

alter policy "order status history select"
on public.order_status_history
using (
  exists (
    select 1
    from public.orders o
    where o.id = order_id
      and (
        o.created_by_user_id = (select auth.uid())
        or public.has_permission('orders.manage_all')
      )
  )
);

alter policy "sales invoices view"
on public.sales_invoices
using (
  public.has_permission('finance.view')
  or exists (
    select 1
    from public.orders o
    where o.id = order_id
      and o.created_by_user_id = (select auth.uid())
  )
);

alter policy "invoice print event insert"
on public.invoice_print_events
with check (
  printed_by = (select auth.uid())
);

alter policy "order discount allocations select"
on public.order_discount_items
using (
  exists (
    select 1
    from public.order_discounts od
    join public.orders o on o.id = od.order_id
    where od.id = order_discount_id
      and (
        o.created_by_user_id = (select auth.uid())
        or public.has_permission('orders.manage_all')
        or public.has_permission('finance.view')
      )
  )
);

alter policy "goods receipt draft insert"
on public.goods_receipts
with check (
  public.has_permission('purchases.receive')
  and received_by = (select auth.uid())
  and status = 'DRAFT'
);
