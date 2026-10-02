-- S-14 / S-16: close the direct write paths around posted records.
--
-- Business writes already go through SECURITY DEFINER functions, which
-- validate, post atomically and write the audit trail. The tables still
-- carried write policies and table-level write grants from the first RLS
-- migration, so an account with the matching permission could insert, edit
-- or delete rows through the Data API and bypass every one of those rules:
-- delete a posted expense, change a supplier bill amount, rewrite a shift's
-- opening cash, or reset the invoice sequence.
--
-- The Flutter app does not use these paths. Its only direct table write is
-- archiving an inventory item (an UPDATE on inventory_items), which stays.
--
-- Functions are unaffected: they run as their owner, not as the caller.

-- 1. Transactional tables: no client writes at all.
do $$
declare
  v_tables constant text[] := array[
    'orders', 'order_items', 'order_item_modifiers', 'order_discounts',
    'order_discount_items', 'payments', 'refunds', 'refund_items',
    'order_actions', 'order_status_history', 'sales_invoices',
    'credit_notes', 'invoice_sequences', 'expenses', 'purchase_orders',
    'purchase_order_items', 'goods_receipts', 'goods_receipt_items',
    'inventory_lots', 'stock_movements', 'stock_counts',
    'stock_count_items', 'stock_out_transactions', 'stock_out_items',
    'supplier_bills', 'supplier_bill_payments', 'shifts',
    'shift_cash_movements', 'audit_logs', 'client_requests'
  ];
  v_policy record;
  v_table text;
begin
  -- A FOR ALL policy would also be the table's read policy. None should be
  -- left on these tables; stop instead of silently removing read access.
  if exists (
    select 1
    from pg_policies p
    where p.schemaname = 'public'
      and p.tablename = any (v_tables)
      and p.cmd = 'ALL'
  ) then
    raise exception 'Unexpected FOR ALL policy on a transactional table';
  end if;

  for v_policy in
    select p.policyname, p.tablename
    from pg_policies p
    where p.schemaname = 'public'
      and p.tablename = any (v_tables)
      and p.cmd in ('INSERT', 'UPDATE', 'DELETE')
  loop
    execute format(
      'drop policy %I on public.%I',
      v_policy.policyname,
      v_policy.tablename
    );
  end loop;

  foreach v_table in array v_tables
  loop
    execute format(
      'revoke insert, update, delete, truncate on table public.%I '
      'from authenticated, anon',
      v_table
    );
  end loop;
end
$$;

-- 2. Master data that posted records refer to: clients may still create and
--    edit it, but not delete it. Rows are archived with is_active instead,
--    so history keeps its links. The two pure link tables
--    (role_permissions, menu_item_modifier_groups) keep DELETE because
--    removing a link is how a role or a menu item is edited.
do $$
declare
  v_tables constant text[] := array[
    'menu_categories', 'menu_items', 'menu_variants', 'modifier_groups',
    'modifiers', 'discount_types', 'inventory_categories',
    'inventory_items', 'units_of_measure', 'suppliers', 'supplier_items',
    'expense_categories', 'payment_methods', 'tax_rates', 'devices',
    'system_settings', 'roles', 'permissions',
    'variant_recipe_components', 'modifier_recipe_components'
  ];
  v_policy record;
  v_table text;
begin
  for v_policy in
    select p.policyname, p.tablename
    from pg_policies p
    where p.schemaname = 'public'
      and p.tablename = any (v_tables)
      and p.cmd = 'DELETE'
  loop
    execute format(
      'drop policy %I on public.%I',
      v_policy.policyname,
      v_policy.tablename
    );
  end loop;

  foreach v_table in array v_tables
  loop
    execute format(
      'revoke delete, truncate on table public.%I from authenticated, anon',
      v_table
    );
  end loop;
end
$$;

-- 3. S-19: the shared updated_at trigger function was never revoked. On a
--    hosted project the platform's default privileges leave it executable
--    by clients; it is only ever meant to run as a trigger.
revoke all on function public.set_updated_at() from public, anon, authenticated;
