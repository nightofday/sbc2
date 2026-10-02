-- 0007_rls.sql
-- Row Level Security.
--
-- This is a strong starting point, but production deployment must include RLS tests.
-- No anonymous business-data access is granted.

-- Enable RLS
alter table public.business_profile enable row level security;
alter table public.system_settings enable row level security;
alter table public.devices enable row level security;
alter table public.roles enable row level security;
alter table public.permissions enable row level security;
alter table public.role_permissions enable row level security;
alter table public.profiles enable row level security;
alter table public.tax_rates enable row level security;
alter table public.payment_methods enable row level security;
alter table public.shifts enable row level security;
alter table public.shift_cash_movements enable row level security;
alter table public.audit_logs enable row level security;

alter table public.units_of_measure enable row level security;
alter table public.inventory_categories enable row level security;
alter table public.inventory_items enable row level security;
alter table public.suppliers enable row level security;
alter table public.supplier_items enable row level security;
alter table public.purchase_orders enable row level security;
alter table public.purchase_order_items enable row level security;
alter table public.goods_receipts enable row level security;
alter table public.goods_receipt_items enable row level security;
alter table public.inventory_lots enable row level security;
alter table public.stock_movements enable row level security;
alter table public.stock_counts enable row level security;
alter table public.stock_count_items enable row level security;
alter table public.supplier_bills enable row level security;
alter table public.supplier_bill_payments enable row level security;

alter table public.menu_categories enable row level security;
alter table public.menu_items enable row level security;
alter table public.menu_variants enable row level security;
alter table public.modifier_groups enable row level security;
alter table public.modifiers enable row level security;
alter table public.menu_item_modifier_groups enable row level security;
alter table public.variant_recipe_components enable row level security;
alter table public.modifier_recipe_components enable row level security;
alter table public.discount_types enable row level security;
alter table public.orders enable row level security;
alter table public.order_items enable row level security;
alter table public.order_item_modifiers enable row level security;
alter table public.order_discounts enable row level security;
alter table public.refunds enable row level security;
alter table public.refund_items enable row level security;
alter table public.payments enable row level security;
alter table public.order_actions enable row level security;
alter table public.order_status_history enable row level security;

alter table public.expense_categories enable row level security;
alter table public.expenses enable row level security;
alter table public.invoice_sequences enable row level security;
alter table public.sales_invoices enable row level security;
alter table public.credit_notes enable row level security;
alter table public.invoice_print_events enable row level security;

-- Remove anonymous access.
revoke all on all tables in schema public from anon;

-- Authenticated role may reach tables; RLS decides which rows/operations pass.
grant select, insert, update, delete on all tables in schema public to authenticated;
grant usage, select on all sequences in schema public to authenticated;

-- ===== Shared lookup reads =====

create policy "authenticated read business profile"
on public.business_profile for select to authenticated using (true);

create policy "authenticated read system settings"
on public.system_settings for select to authenticated using (true);

create policy "authenticated read tax rates"
on public.tax_rates for select to authenticated using (true);

create policy "authenticated read payment methods"
on public.payment_methods for select to authenticated using (true);

create policy "authenticated read uom"
on public.units_of_measure for select to authenticated using (true);

create policy "authenticated read inventory categories"
on public.inventory_categories for select to authenticated using (true);

create policy "authenticated read menu categories"
on public.menu_categories for select to authenticated using (true);

create policy "authenticated read menu items"
on public.menu_items for select to authenticated using (true);

create policy "authenticated read menu variants"
on public.menu_variants for select to authenticated using (true);

create policy "authenticated read modifier groups"
on public.modifier_groups for select to authenticated using (true);

create policy "authenticated read modifiers"
on public.modifiers for select to authenticated using (true);

create policy "authenticated read item modifier groups"
on public.menu_item_modifier_groups for select to authenticated using (true);

create policy "authenticated read variant recipes"
on public.variant_recipe_components for select to authenticated using (true);

create policy "authenticated read modifier recipes"
on public.modifier_recipe_components for select to authenticated using (true);

create policy "authenticated read discount types"
on public.discount_types for select to authenticated using (true);

create policy "authenticated read expense categories"
on public.expense_categories for select to authenticated using (true);

-- ===== Profiles and role metadata =====

create policy "read own profile or manage users"
on public.profiles for select to authenticated
using (id = auth.uid() or public.has_permission('users.view'));

create policy "managers manage profiles"
on public.profiles for update to authenticated
using (public.has_permission('users.manage'))
with check (public.has_permission('users.manage'));

create policy "authorized read roles"
on public.roles for select to authenticated using (true);

create policy "authorized read permissions"
on public.permissions for select to authenticated using (true);

create policy "authorized read role permissions"
on public.role_permissions for select to authenticated using (true);

create policy "admin manage roles"
on public.roles for all to authenticated
using (public.has_permission('roles.manage'))
with check (public.has_permission('roles.manage'));

create policy "admin manage permissions"
on public.permissions for all to authenticated
using (public.has_permission('roles.manage'))
with check (public.has_permission('roles.manage'));

create policy "admin manage role permissions"
on public.role_permissions for all to authenticated
using (public.has_permission('roles.manage'))
with check (public.has_permission('roles.manage'));

-- ===== Devices =====

create policy "authenticated read devices"
on public.devices for select to authenticated using (true);

create policy "manager manage devices"
on public.devices for all to authenticated
using (public.has_permission('devices.manage'))
with check (public.has_permission('devices.manage'));

-- ===== Shifts =====

create policy "own or manager read shifts"
on public.shifts for select to authenticated
using (employee_id = auth.uid() or public.has_permission('shift.manage'));

create policy "own or manager read shift cash movements"
on public.shift_cash_movements for select to authenticated
using (
  exists (
    select 1
    from public.shifts s
    where s.id = shift_id
      and (s.employee_id = auth.uid() or public.has_permission('shift.manage'))
  )
);

create policy "authorized shift cash movement insert"
on public.shift_cash_movements for insert to authenticated
with check (
  recorded_by = auth.uid()
  and public.has_permission('shift.cash_movement')
);

-- Shifts are normally inserted/closed through RPC functions.
create policy "manager manage shifts"
on public.shifts for all to authenticated
using (public.has_permission('shift.manage'))
with check (public.has_permission('shift.manage'));

-- ===== Inventory =====

create policy "inventory view"
on public.inventory_items for select to authenticated
using (public.has_permission('inventory.view'));

create policy "inventory manage"
on public.inventory_items for all to authenticated
using (public.has_permission('inventory.manage'))
with check (public.has_permission('inventory.manage'));

create policy "inventory lot view"
on public.inventory_lots for select to authenticated
using (public.has_permission('inventory.view'));

create policy "stock movement view"
on public.stock_movements for select to authenticated
using (public.has_permission('inventory.view'));

create policy "inventory categories manage"
on public.inventory_categories for all to authenticated
using (public.has_permission('inventory.manage'))
with check (public.has_permission('inventory.manage'));

create policy "stock counts view"
on public.stock_counts for select to authenticated
using (public.has_permission('inventory.view'));

create policy "stock count items view"
on public.stock_count_items for select to authenticated
using (public.has_permission('inventory.view'));

create policy "stock counts manage"
on public.stock_counts for all to authenticated
using (public.has_permission('inventory.adjust'))
with check (public.has_permission('inventory.adjust'));

create policy "stock count items manage"
on public.stock_count_items for all to authenticated
using (public.has_permission('inventory.adjust'))
with check (public.has_permission('inventory.adjust'));

-- Inventory lots and stock movements should normally be created by trusted RPC.
create policy "inventory manager exceptional lot management"
on public.inventory_lots for all to authenticated
using (public.has_permission('inventory.manage'))
with check (public.has_permission('inventory.manage'));

create policy "inventory manager exceptional movement management"
on public.stock_movements for insert to authenticated
with check (public.has_permission('inventory.adjust'));

-- ===== Suppliers and purchasing =====

create policy "supplier view"
on public.suppliers for select to authenticated
using (public.has_permission('suppliers.view'));

create policy "supplier manage"
on public.suppliers for all to authenticated
using (public.has_permission('suppliers.manage'))
with check (public.has_permission('suppliers.manage'));

create policy "supplier items view"
on public.supplier_items for select to authenticated
using (public.has_permission('suppliers.view'));

create policy "supplier items manage"
on public.supplier_items for all to authenticated
using (public.has_permission('suppliers.manage'))
with check (public.has_permission('suppliers.manage'));

create policy "purchase orders view"
on public.purchase_orders for select to authenticated
using (public.has_permission('purchases.view'));

create policy "purchase orders manage"
on public.purchase_orders for all to authenticated
using (public.has_permission('purchases.manage'))
with check (public.has_permission('purchases.manage'));

create policy "purchase order items view"
on public.purchase_order_items for select to authenticated
using (public.has_permission('purchases.view'));

create policy "purchase order items manage"
on public.purchase_order_items for all to authenticated
using (public.has_permission('purchases.manage'))
with check (public.has_permission('purchases.manage'));

create policy "goods receipts view"
on public.goods_receipts for select to authenticated
using (public.has_permission('purchases.view'));

create policy "goods receipts manage"
on public.goods_receipts for all to authenticated
using (public.has_permission('purchases.receive'))
with check (public.has_permission('purchases.receive'));

create policy "goods receipt items view"
on public.goods_receipt_items for select to authenticated
using (public.has_permission('purchases.view'));

create policy "goods receipt items manage"
on public.goods_receipt_items for all to authenticated
using (public.has_permission('purchases.receive'))
with check (public.has_permission('purchases.receive'));

create policy "supplier bills view"
on public.supplier_bills for select to authenticated
using (public.has_permission('purchases.view') or public.has_permission('finance.view'));

create policy "supplier bills manage"
on public.supplier_bills for all to authenticated
using (public.has_permission('purchases.manage'))
with check (public.has_permission('purchases.manage'));

create policy "supplier bill payments view"
on public.supplier_bill_payments for select to authenticated
using (public.has_permission('finance.view'));

create policy "supplier bill payments manage"
on public.supplier_bill_payments for all to authenticated
using (public.has_permission('finance.manage'))
with check (public.has_permission('finance.manage'));

-- ===== Menu maintenance =====

create policy "menu manager manage categories"
on public.menu_categories for all to authenticated
using (public.has_permission('menu.manage'))
with check (public.has_permission('menu.manage'));

create policy "menu manager manage items"
on public.menu_items for all to authenticated
using (public.has_permission('menu.manage'))
with check (public.has_permission('menu.manage'));

create policy "menu manager manage variants"
on public.menu_variants for all to authenticated
using (public.has_permission('menu.manage'))
with check (public.has_permission('menu.manage'));

create policy "menu manager manage modifier groups"
on public.modifier_groups for all to authenticated
using (public.has_permission('menu.manage'))
with check (public.has_permission('menu.manage'));

create policy "menu manager manage modifiers"
on public.modifiers for all to authenticated
using (public.has_permission('menu.manage'))
with check (public.has_permission('menu.manage'));

create policy "menu manager manage item modifier groups"
on public.menu_item_modifier_groups for all to authenticated
using (public.has_permission('menu.manage'))
with check (public.has_permission('menu.manage'));

create policy "menu manager manage variant recipes"
on public.variant_recipe_components for all to authenticated
using (public.has_permission('menu.manage'))
with check (public.has_permission('menu.manage'));

create policy "menu manager manage modifier recipes"
on public.modifier_recipe_components for all to authenticated
using (public.has_permission('menu.manage'))
with check (public.has_permission('menu.manage'));

create policy "discount manager manage discount types"
on public.discount_types for all to authenticated
using (public.has_permission('discounts.manage'))
with check (public.has_permission('discounts.manage'));

-- ===== Orders =====

create policy "order select"
on public.orders for select to authenticated
using (
  public.has_permission('orders.manage_all')
  or created_by_user_id = auth.uid()
);

create policy "order create"
on public.orders for insert to authenticated
with check (
  public.has_permission('orders.create')
  and created_by_user_id = auth.uid()
  and public.current_open_shift_id() is not null
);

create policy "order edit open own"
on public.orders for update to authenticated
using (
  (created_by_user_id = auth.uid() and status in ('OPEN','PENDING_PAYMENT'))
  or public.has_permission('orders.manage_all')
)
with check (
  (created_by_user_id = auth.uid() and status in ('OPEN','PENDING_PAYMENT'))
  or public.has_permission('orders.manage_all')
);

create policy "order items select"
on public.order_items for select to authenticated
using (
  exists (
    select 1 from public.orders o
    where o.id = order_id
      and (o.created_by_user_id = auth.uid() or public.has_permission('orders.manage_all'))
  )
);

create policy "order items insert"
on public.order_items for insert to authenticated
with check (
  exists (
    select 1 from public.orders o
    where o.id = order_id
      and o.status in ('OPEN','PENDING_PAYMENT')
      and (o.created_by_user_id = auth.uid() or public.has_permission('orders.manage_all'))
  )
);

create policy "order items update"
on public.order_items for update to authenticated
using (
  exists (
    select 1 from public.orders o
    where o.id = order_id
      and o.status in ('OPEN','PENDING_PAYMENT')
      and (o.created_by_user_id = auth.uid() or public.has_permission('orders.manage_all'))
  )
)
with check (
  exists (
    select 1 from public.orders o
    where o.id = order_id
      and o.status in ('OPEN','PENDING_PAYMENT')
      and (o.created_by_user_id = auth.uid() or public.has_permission('orders.manage_all'))
  )
);

create policy "order items delete"
on public.order_items for delete to authenticated
using (
  exists (
    select 1 from public.orders o
    where o.id = order_id
      and o.status in ('OPEN','PENDING_PAYMENT')
      and (o.created_by_user_id = auth.uid() or public.has_permission('orders.manage_all'))
  )
);

create policy "order modifiers select"
on public.order_item_modifiers for select to authenticated
using (
  exists (
    select 1
    from public.order_items oi
    join public.orders o on o.id = oi.order_id
    where oi.id = order_item_id
      and (o.created_by_user_id = auth.uid() or public.has_permission('orders.manage_all'))
  )
);

create policy "order modifiers insert"
on public.order_item_modifiers for insert to authenticated
with check (
  exists (
    select 1
    from public.order_items oi
    join public.orders o on o.id = oi.order_id
    where oi.id = order_item_id
      and o.status in ('OPEN','PENDING_PAYMENT')
      and (o.created_by_user_id = auth.uid() or public.has_permission('orders.manage_all'))
  )
);

create policy "order modifiers update"
on public.order_item_modifiers for update to authenticated
using (
  exists (
    select 1
    from public.order_items oi
    join public.orders o on o.id = oi.order_id
    where oi.id = order_item_id
      and o.status in ('OPEN','PENDING_PAYMENT')
      and (o.created_by_user_id = auth.uid() or public.has_permission('orders.manage_all'))
  )
);

create policy "order modifiers delete"
on public.order_item_modifiers for delete to authenticated
using (
  exists (
    select 1
    from public.order_items oi
    join public.orders o on o.id = oi.order_id
    where oi.id = order_item_id
      and o.status in ('OPEN','PENDING_PAYMENT')
      and (o.created_by_user_id = auth.uid() or public.has_permission('orders.manage_all'))
  )
);

create policy "order discounts select"
on public.order_discounts for select to authenticated
using (
  exists (
    select 1 from public.orders o
    where o.id = order_id
      and (o.created_by_user_id = auth.uid() or public.has_permission('orders.manage_all'))
  )
);

create policy "order discounts manage"
on public.order_discounts for all to authenticated
using (public.has_permission('discounts.apply'))
with check (public.has_permission('discounts.apply'));

create policy "payments select"
on public.payments for select to authenticated
using (
  exists (
    select 1 from public.orders o
    where o.id = order_id
      and (o.created_by_user_id = auth.uid() or public.has_permission('orders.manage_all') or public.has_permission('finance.view'))
  )
);

create policy "refunds select"
on public.refunds for select to authenticated
using (public.has_permission('orders.refund') or public.has_permission('finance.view'));

create policy "refund items select"
on public.refund_items for select to authenticated
using (
  exists (
    select 1 from public.refunds r
    where r.id = refund_id
      and (public.has_permission('orders.refund') or public.has_permission('finance.view'))
  )
);

create policy "order actions select"
on public.order_actions for select to authenticated
using (public.has_permission('orders.manage_all'));

create policy "order status history select"
on public.order_status_history for select to authenticated
using (
  exists (
    select 1 from public.orders o
    where o.id = order_id
      and (o.created_by_user_id = auth.uid() or public.has_permission('orders.manage_all'))
  )
);

-- Direct payment/refund/action writes are intentionally not opened here.
-- Use checkout/refund/void RPCs.

-- ===== Expenses / finance / invoices =====

create policy "expenses view"
on public.expenses for select to authenticated
using (public.has_permission('expenses.view') or public.has_permission('finance.view'));

create policy "expenses manage"
on public.expenses for all to authenticated
using (public.has_permission('expenses.manage'))
with check (public.has_permission('expenses.manage'));

create policy "expense categories manage"
on public.expense_categories for all to authenticated
using (public.has_permission('expenses.manage'))
with check (public.has_permission('expenses.manage'));

create policy "invoice sequences manager"
on public.invoice_sequences for select to authenticated
using (public.has_permission('finance.view'));

create policy "sales invoices view"
on public.sales_invoices for select to authenticated
using (
  public.has_permission('finance.view')
  or exists (
    select 1 from public.orders o
    where o.id = order_id and o.created_by_user_id = auth.uid()
  )
);

create policy "credit notes view"
on public.credit_notes for select to authenticated
using (public.has_permission('finance.view') or public.has_permission('orders.refund'));

create policy "invoice print events select"
on public.invoice_print_events for select to authenticated
using (public.has_permission('finance.view'));

create policy "invoice print event insert"
on public.invoice_print_events for insert to authenticated
with check (printed_by = auth.uid());

-- ===== Audit logs =====

create policy "manager read audit logs"
on public.audit_logs for select to authenticated
using (public.has_permission('audit.view'));

-- Audit inserts should normally come from trusted functions.
-- No direct update/delete policies are created for audit logs.

-- ===== Reference/master writes =====

create policy "manager manage system settings"
on public.system_settings for all to authenticated
using (public.has_permission('settings.manage'))
with check (public.has_permission('settings.manage'));

create policy "manager manage tax rates"
on public.tax_rates for all to authenticated
using (public.has_permission('settings.manage'))
with check (public.has_permission('settings.manage'));

create policy "manager manage payment methods"
on public.payment_methods for all to authenticated
using (public.has_permission('settings.manage'))
with check (public.has_permission('settings.manage'));

create policy "manager manage uom"
on public.units_of_measure for all to authenticated
using (public.has_permission('inventory.manage'))
with check (public.has_permission('inventory.manage'));

-- Invoice rows and sequences are written through trusted functions/manager tools.
create policy "finance manage invoice sequences"
on public.invoice_sequences for all to authenticated
using (public.has_permission('finance.manage'))
with check (public.has_permission('finance.manage'));
