-- 0008_hardening_structure.sql
-- Structural/security hardening before the first real Supabase deployment.
-- This migration intentionally patches the V1 schema instead of changing historical migrations.

-- ============================================================
-- 1. Stronger relational integrity
-- ============================================================

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'fk_stock_movements_order'
  ) then
    alter table public.stock_movements
      add constraint fk_stock_movements_order
      foreign key (order_id) references public.orders(id) on delete set null;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'fk_stock_movements_order_item'
  ) then
    alter table public.stock_movements
      add constraint fk_stock_movements_order_item
      foreign key (order_item_id) references public.order_items(id) on delete set null;
  end if;
end
$$;

create index if not exists idx_stock_movements_reference
  on public.stock_movements(reference_type, reference_id);

create index if not exists idx_payments_external_reference
  on public.payments(payment_method_id, external_reference)
  where external_reference is not null;

-- One modifier row per modifier per order line. Quantity handles repeated selections.
create unique index if not exists uq_order_item_modifier
  on public.order_item_modifiers(order_item_id, modifier_id)
  where modifier_id is not null;

-- ============================================================
-- 2. Discount allocation for SC/PWD, refunds and auditability
-- ============================================================

create table if not exists public.order_discount_items (
  id uuid primary key default gen_random_uuid(),
  order_discount_id uuid not null
    references public.order_discounts(id) on delete cascade,
  order_item_id uuid not null
    references public.order_items(id) on delete cascade,
  eligible_amount numeric(14,2) not null check (eligible_amount >= 0),
  discount_amount numeric(14,2) not null check (discount_amount >= 0),
  created_at timestamptz not null default now(),
  unique (order_discount_id, order_item_id),
  check (discount_amount <= eligible_amount)
);

create index if not exists idx_order_discount_items_order_item
  on public.order_discount_items(order_item_id);

alter table public.order_discount_items enable row level security;

create policy "order discount allocations select"
on public.order_discount_items for select to authenticated
using (
  exists (
    select 1
    from public.order_discounts od
    join public.orders o on o.id = od.order_id
    where od.id = order_discount_id
      and (
        o.created_by_user_id = auth.uid()
        or public.has_permission('orders.manage_all')
        or public.has_permission('finance.view')
      )
  )
);

-- No direct client write policy is intentionally created for order_discount_items.
-- Trusted RPC functions own pricing/discount calculations.

-- ============================================================
-- 3. Prevent conflicting inventory configuration
--    A sellable variant is EITHER a finished stock item OR recipe-driven.
-- ============================================================

create or replace function public.guard_variant_inventory_mode()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.track_finished_inventory = true
     and exists (
       select 1
       from public.variant_recipe_components rc
       where rc.menu_variant_id = new.id
     ) then
    raise exception
      'A menu variant cannot use finished-goods inventory and a base recipe at the same time';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_guard_variant_inventory_mode on public.menu_variants;
create trigger trg_guard_variant_inventory_mode
before update of track_finished_inventory, finished_inventory_item_id
on public.menu_variants
for each row execute function public.guard_variant_inventory_mode();

create or replace function public.guard_recipe_inventory_mode()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_finished boolean;
begin
  select mv.track_finished_inventory
  into v_finished
  from public.menu_variants mv
  where mv.id = new.menu_variant_id;

  if coalesce(v_finished, false) then
    raise exception
      'Cannot add recipe components to a variant configured as finished-goods inventory';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_guard_recipe_inventory_mode
on public.variant_recipe_components;

create trigger trg_guard_recipe_inventory_mode
before insert or update of menu_variant_id
on public.variant_recipe_components
for each row execute function public.guard_recipe_inventory_mode();

-- ============================================================
-- 4. Protect role changes from manager privilege escalation
-- ============================================================

create or replace function public.protect_profile_privileges()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.role_id is distinct from old.role_id then
    if not public.has_permission('roles.manage') then
      raise exception 'Only an administrator may change user roles';
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_protect_profile_privileges on public.profiles;
create trigger trg_protect_profile_privileges
before update on public.profiles
for each row execute function public.protect_profile_privileges();

-- ============================================================
-- 5. Supplier bill status is derived from actual payments
-- ============================================================

create or replace function public.sync_supplier_bill_status(p_bill_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_bill public.supplier_bills%rowtype;
  v_paid numeric(14,2);
begin
  select *
  into v_bill
  from public.supplier_bills
  where id = p_bill_id
  for update;

  if not found or v_bill.status = 'VOID' then
    return;
  end if;

  select coalesce(sum(amount),0)
  into v_paid
  from public.supplier_bill_payments
  where supplier_bill_id = p_bill_id;

  update public.supplier_bills
  set status = case
    when v_paid <= 0 then 'UNPAID'
    when v_paid < amount then 'PARTIALLY_PAID'
    else 'PAID'
  end
  where id = p_bill_id;
end;
$$;

revoke all on function public.sync_supplier_bill_status(uuid) from public;

create or replace function public.after_supplier_bill_payment_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.sync_supplier_bill_status(
    case when tg_op = 'DELETE' then old.supplier_bill_id else new.supplier_bill_id end
  );
  return coalesce(new, old);
end;
$$;

drop trigger if exists trg_supplier_bill_payment_sync
on public.supplier_bill_payments;

create trigger trg_supplier_bill_payment_sync
after insert or update or delete
on public.supplier_bill_payments
for each row execute function public.after_supplier_bill_payment_change();

-- ============================================================
-- 6. Stock ledger becomes the authoritative quantity source
-- ============================================================

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
  coalesce(sum(sm.quantity_delta),0)::numeric(14,4) as current_quantity
from public.inventory_items ii
join public.units_of_measure u on u.id = ii.base_uom_id
left join public.stock_movements sm
  on sm.inventory_item_id = ii.id
where ii.is_active = true
group by
  ii.id,
  ii.sku,
  ii.name,
  ii.track_inventory,
  ii.track_expiry,
  ii.reorder_level,
  ii.reorder_target,
  u.code;

create or replace view public.v_low_stock
with (security_invoker = true)
as
select *
from public.v_inventory_stock
where track_inventory = true
  and current_quantity <= reorder_level;

-- ============================================================
-- 7. Remove client-side write paths that could bypass business rules
-- ============================================================

-- Orders must be created/edited through trusted RPCs.
drop policy if exists "order create" on public.orders;
drop policy if exists "order edit open own" on public.orders;

-- Prices and totals must never be client supplied.
drop policy if exists "order items insert" on public.order_items;
drop policy if exists "order items update" on public.order_items;
drop policy if exists "order items delete" on public.order_items;

drop policy if exists "order modifiers insert" on public.order_item_modifiers;
drop policy if exists "order modifiers update" on public.order_item_modifiers;
drop policy if exists "order modifiers delete" on public.order_item_modifiers;

drop policy if exists "order discounts manage" on public.order_discounts;

-- Lots and movement ledger are maintained by transactional functions.
drop policy if exists "inventory manager exceptional lot management"
  on public.inventory_lots;
drop policy if exists "inventory manager exceptional movement management"
  on public.stock_movements;

-- Supplier bill payments must use the payment RPC so balances cannot be bypassed.
drop policy if exists "supplier bill payments manage"
  on public.supplier_bill_payments;

-- Receiving may be edited only while still DRAFT.
drop policy if exists "goods receipts manage" on public.goods_receipts;
drop policy if exists "goods receipt items manage" on public.goods_receipt_items;

create policy "goods receipt draft insert"
on public.goods_receipts for insert to authenticated
with check (
  public.has_permission('purchases.receive')
  and received_by = auth.uid()
  and status = 'DRAFT'
);

create policy "goods receipt draft update"
on public.goods_receipts for update to authenticated
using (
  public.has_permission('purchases.receive')
  and status = 'DRAFT'
)
with check (
  public.has_permission('purchases.receive')
  and status = 'DRAFT'
);

create policy "goods receipt item draft insert"
on public.goods_receipt_items for insert to authenticated
with check (
  public.has_permission('purchases.receive')
  and exists (
    select 1
    from public.goods_receipts gr
    where gr.id = goods_receipt_id
      and gr.status = 'DRAFT'
  )
);

create policy "goods receipt item draft update"
on public.goods_receipt_items for update to authenticated
using (
  public.has_permission('purchases.receive')
  and exists (
    select 1
    from public.goods_receipts gr
    where gr.id = goods_receipt_id
      and gr.status = 'DRAFT'
  )
)
with check (
  public.has_permission('purchases.receive')
  and exists (
    select 1
    from public.goods_receipts gr
    where gr.id = goods_receipt_id
      and gr.status = 'DRAFT'
  )
);

create policy "goods receipt item draft delete"
on public.goods_receipt_items for delete to authenticated
using (
  public.has_permission('purchases.receive')
  and exists (
    select 1
    from public.goods_receipts gr
    where gr.id = goods_receipt_id
      and gr.status = 'DRAFT'
  )
);

-- Keep direct table privileges available for RLS-protected reads.
-- Sensitive writes above have no matching RLS policy and therefore fail for clients.

-- ============================================================
-- 8. Small integrity constraints
-- ============================================================

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'chk_orders_nonblank_table'
  ) then
    alter table public.orders
      add constraint chk_orders_nonblank_table
      check (
        order_type <> 'DINE_IN'
        or nullif(btrim(table_number), '') is not null
      ) not valid;
  end if;
end
$$;

-- The original dine-in check remains valid; this strengthens it against empty strings.
