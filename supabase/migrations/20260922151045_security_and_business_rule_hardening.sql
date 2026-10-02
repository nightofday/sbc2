-- Security and business-rule hardening discovered during live acceptance testing.

-- 1) New hardening table was created after the broad authenticated grant in migration 0007.
grant select on table public.order_discount_items to authenticated;
revoke all on table public.order_discount_items from anon;

-- 2) Pin search_path on shared trigger helper.
alter function public.set_updated_at() set search_path = public;

-- 3) Internal authorization helper. Not exposed as an RPC.
create or replace function public.user_has_permission_for(
  p_user_id uuid,
  p_permission_code text
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.profiles pr
    join public.role_permissions rp on rp.role_id = pr.role_id
    join public.permissions pe on pe.id = rp.permission_id
    where pr.id = p_user_id
      and pr.status = 'ACTIVE'
      and pe.code = p_permission_code
  );
$$;

revoke all on function public.user_has_permission_for(uuid,text)
from public, anon, authenticated;

-- 4) Enforce order-type required fields in the database.
create or replace function public.guard_order_required_fields()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.order_type in ('TAKE_OUT','DELIVERY')
     and nullif(btrim(coalesce(new.customer_name,'')), '') is null then
    raise exception 'Customer name is required for take-out and delivery orders';
  end if;

  if new.order_type = 'DINE_IN'
     and nullif(btrim(coalesce(new.table_number,'')), '') is null then
    raise exception 'Table number is required for dine-in orders';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_guard_order_required_fields on public.orders;
create trigger trg_guard_order_required_fields
before insert or update of order_type, customer_name, table_number
on public.orders
for each row execute function public.guard_order_required_fields();

revoke all on function public.guard_order_required_fields()
from public, anon, authenticated;

-- 5) Derive status-history old_status from the actual preceding history row.
create or replace function public.normalize_order_status_history()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_previous text;
begin
  select osh.new_status
  into v_previous
  from public.order_status_history osh
  where osh.order_id = new.order_id
  order by osh.created_at desc, osh.id desc
  limit 1;

  new.old_status := v_previous;
  return new;
end;
$$;

drop trigger if exists trg_normalize_order_status_history
on public.order_status_history;

create trigger trg_normalize_order_status_history
before insert on public.order_status_history
for each row execute function public.normalize_order_status_history();

revoke all on function public.normalize_order_status_history()
from public, anon, authenticated;

-- 6) Required/min/max modifiers must be satisfied before an order can complete.
create or replace function public.guard_order_modifier_requirements()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_req record;
  v_selected numeric;
  v_min integer;
begin
  if new.status <> 'COMPLETED'
     or old.status = 'COMPLETED' then
    return new;
  end if;

  for v_req in
    select
      oi.id as order_item_id,
      mg.id as modifier_group_id,
      mg.name as modifier_group_name,
      mg.min_selections,
      mg.max_selections,
      mg.is_required
    from public.order_items oi
    join public.menu_item_modifier_groups mig
      on mig.menu_item_id = oi.menu_item_id
    join public.modifier_groups mg
      on mg.id = mig.modifier_group_id
    where oi.order_id = new.id
      and mg.is_active = true
  loop
    select coalesce(sum(oim.quantity),0)
    into v_selected
    from public.order_item_modifiers oim
    join public.modifiers m on m.id = oim.modifier_id
    where oim.order_item_id = v_req.order_item_id
      and m.modifier_group_id = v_req.modifier_group_id
      and m.is_active = true;

    v_min := greatest(
      coalesce(v_req.min_selections,0),
      case when v_req.is_required then 1 else 0 end
    );

    if v_selected < v_min then
      raise exception 'Modifier group "%" requires at least % selection(s)',
        v_req.modifier_group_name, v_min;
    end if;

    if v_req.max_selections is not null
       and v_selected > v_req.max_selections then
      raise exception 'Modifier group "%" allows at most % selection(s)',
        v_req.modifier_group_name, v_req.max_selections;
    end if;
  end loop;

  return new;
end;
$$;

drop trigger if exists trg_guard_order_modifier_requirements on public.orders;
create trigger trg_guard_order_modifier_requirements
before update of status on public.orders
for each row execute function public.guard_order_modifier_requirements();

revoke all on function public.guard_order_modifier_requirements()
from public, anon, authenticated;

-- 7) Authorization UUIDs must identify an ACTIVE user with the required permission.
create or replace function public.guard_order_discount_authorizer()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_requires boolean;
begin
  select dt.requires_authorization
  into v_requires
  from public.discount_types dt
  where dt.id = new.discount_type_id;

  if coalesce(v_requires,false) then
    if new.authorized_by is null
       or not public.user_has_permission_for(new.authorized_by,'discounts.manage') then
      raise exception 'A valid manager/admin authorization is required for this discount';
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_guard_order_discount_authorizer
on public.order_discounts;

create trigger trg_guard_order_discount_authorizer
before insert or update of discount_type_id, authorized_by
on public.order_discounts
for each row execute function public.guard_order_discount_authorizer();

revoke all on function public.guard_order_discount_authorizer()
from public, anon, authenticated;

create or replace function public.guard_refund_authorizer()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.authorized_by is null
     or not public.user_has_permission_for(new.authorized_by,'orders.refund') then
    raise exception 'A valid manager/admin authorization is required for refunds';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_guard_refund_authorizer on public.refunds;
create trigger trg_guard_refund_authorizer
before insert or update of authorized_by
on public.refunds
for each row execute function public.guard_refund_authorizer();

revoke all on function public.guard_refund_authorizer()
from public, anon, authenticated;

create or replace function public.guard_order_action_authorizer()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_permission text;
begin
  v_permission := case new.action_type
    when 'VOID' then 'orders.void'
    when 'REFUND' then 'orders.refund'
    else null
  end;

  if v_permission is not null then
    if new.authorized_by is null
       or not public.user_has_permission_for(new.authorized_by,v_permission) then
      raise exception 'A valid manager/admin authorization is required for %', new.action_type;
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_guard_order_action_authorizer on public.order_actions;
create trigger trg_guard_order_action_authorizer
before insert or update of action_type, authorized_by
on public.order_actions
for each row execute function public.guard_order_action_authorizer();

revoke all on function public.guard_order_action_authorizer()
from public, anon, authenticated;

-- 8) Supplier bill payments may use only active payment methods.
create or replace function public.guard_supplier_bill_payment_method()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_method public.payment_methods%rowtype;
begin
  select *
  into v_method
  from public.payment_methods
  where id = new.payment_method_id
    and is_active = true;

  if not found then
    raise exception 'Invalid or inactive payment method';
  end if;

  if v_method.requires_reference
     and nullif(btrim(coalesce(new.reference_number,'')), '') is null then
    raise exception 'Payment reference is required';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_guard_supplier_bill_payment_method
on public.supplier_bill_payments;

create trigger trg_guard_supplier_bill_payment_method
before insert or update of payment_method_id, reference_number
on public.supplier_bill_payments
for each row execute function public.guard_supplier_bill_payment_method();

revoke all on function public.guard_supplier_bill_payment_method()
from public, anon, authenticated;

-- 9) Normalize purchase-order receipt status from POSTED receipts only.
create or replace function public.normalize_purchase_order_receipt_status()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_expected numeric(14,4);
  v_received numeric(14,4);
  v_status text;
begin
  if pg_trigger_depth() > 1
     or new.status not in ('PARTIALLY_RECEIVED','RECEIVED') then
    return new;
  end if;

  select coalesce(sum(
    poi.ordered_quantity * poi.base_quantity_per_purchase_unit
  ),0)
  into v_expected
  from public.purchase_order_items poi
  where poi.purchase_order_id = new.id;

  select coalesce(sum(gri.base_quantity),0)
  into v_received
  from public.goods_receipt_items gri
  join public.goods_receipts gr
    on gr.id = gri.goods_receipt_id
   and gr.status = 'POSTED'
  join public.purchase_order_items poi
    on poi.id = gri.purchase_order_item_id
  where poi.purchase_order_id = new.id;

  if v_expected <= 0 or v_received <= 0 then
    return new;
  end if;

  v_status := case
    when v_received < v_expected then 'PARTIALLY_RECEIVED'
    else 'RECEIVED'
  end;

  if new.status is distinct from v_status then
    update public.purchase_orders
    set status = v_status
    where id = new.id;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_normalize_purchase_order_receipt_status
on public.purchase_orders;

create trigger trg_normalize_purchase_order_receipt_status
after update of status on public.purchase_orders
for each row execute function public.normalize_purchase_order_receipt_status();

revoke all on function public.normalize_purchase_order_receipt_status()
from public, anon, authenticated;

-- 10) Remove RPC exposure from internal SECURITY DEFINER / trigger helpers.
revoke all on function public.handle_new_auth_user() from public, anon, authenticated;
revoke all on function public.protect_profile_privileges() from public, anon, authenticated;
revoke all on function public.after_supplier_bill_payment_change() from public, anon, authenticated;
revoke all on function public.sync_supplier_bill_status(uuid) from public, anon, authenticated;
revoke all on function public.recalculate_order_totals(uuid) from public, anon, authenticated;
revoke all on function public.reprice_order_item(uuid) from public, anon, authenticated;
revoke all on function public.next_invoice_number(text) from public, anon, authenticated;
revoke all on function public.issue_sales_invoice(uuid) from public, anon, authenticated;
revoke all on function public.consume_inventory_fefo(uuid,numeric,uuid,uuid,uuid)
  from public, anon, authenticated;
revoke all on function public.assert_active_order_access(uuid)
  from public, anon, authenticated;
revoke all on function public.guard_variant_inventory_mode()
  from public, anon, authenticated;
revoke all on function public.guard_recipe_inventory_mode()
  from public, anon, authenticated;

alter default privileges in schema public
revoke execute on functions from public, anon, authenticated;
