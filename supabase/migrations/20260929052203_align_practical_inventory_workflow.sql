-- Align inventory with the business-validated Street Bowl Cafe workflow.
--
-- Prepared menu items do not consume recipe ingredients at checkout.
-- Inventory is reserved for countable finished goods and practical supplies.
-- One stock-out document can release many supplies in a single transaction.

-- Preserve the discontinued recipe configuration for audit/reference before
-- removing it from the active checkout path.
create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

create table if not exists private.retired_variant_recipe_components (
  id uuid primary key,
  menu_variant_id uuid not null,
  inventory_item_id uuid not null,
  quantity_base_uom numeric(14,4) not null,
  wastage_percent numeric(7,4) not null,
  retired_at timestamptz not null default now(),
  retired_reason text not null
);

create table if not exists private.retired_modifier_recipe_components (
  id uuid primary key,
  modifier_id uuid not null,
  inventory_item_id uuid not null,
  quantity_base_uom numeric(14,4) not null,
  wastage_percent numeric(7,4) not null,
  retired_at timestamptz not null default now(),
  retired_reason text not null
);

insert into private.retired_variant_recipe_components(
  id, menu_variant_id, inventory_item_id, quantity_base_uom,
  wastage_percent, retired_reason
)
select
  id, menu_variant_id, inventory_item_id, quantity_base_uom,
  wastage_percent,
  'Recipe-based ingredient deduction removed after business consultation'
from public.variant_recipe_components
on conflict (id) do nothing;

insert into private.retired_modifier_recipe_components(
  id, modifier_id, inventory_item_id, quantity_base_uom,
  wastage_percent, retired_reason
)
select
  id, modifier_id, inventory_item_id, quantity_base_uom,
  wastage_percent,
  'Recipe-based ingredient deduction removed after business consultation'
from public.modifier_recipe_components
on conflict (id) do nothing;

delete from public.modifier_recipe_components;
delete from public.variant_recipe_components;

-- Keep the legacy public tables readable for old clients and historical
-- joins, but close every direct write path so recipe deduction cannot be
-- reintroduced outside the approved RPCs.
revoke insert, update, delete
on public.variant_recipe_components, public.modifier_recipe_components
from authenticated, anon;

-- Raw ingredients previously seeded for recipe deduction are retained in the
-- ledger but removed from active stock tracking. Future grocery purchases use
-- the Ingredients / Grocery expense category instead.
update public.inventory_items
set track_inventory = false,
    is_active = false,
    archived_at = coalesce(archived_at, now())
where category_id in (
  select id from public.inventory_categories where name = 'Raw Ingredients'
);

update public.inventory_categories
set is_active = false,
    description = 'Retired after consultation; these purchases are expenses'
where name = 'Raw Ingredients';

insert into public.expense_categories(code, name, description, is_active)
values (
  'INGREDIENTS',
  'Ingredients / Grocery',
  'Untracked ingredients and grocery purchases used in daily operations',
  true
)
on conflict (code) do update set
  name = excluded.name,
  description = excluded.description,
  is_active = true;

-- Keep the existing public API signature for backward-compatible clients, but
-- accept only the two validated modes: untracked prepared items and countable
-- finished goods.
create or replace function public.apply_variant_inventory_configuration(
  p_variant_id uuid,
  p_inventory_mode text,
  p_finished_inventory_item_id uuid default null,
  p_recipe jsonb default '[]'::jsonb
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_mode text;
begin
  if not public.has_permission('menu.manage') then
    raise exception 'Permission denied';
  end if;

  if not exists (select 1 from public.menu_variants where id = p_variant_id) then
    raise exception 'Menu variant not found';
  end if;

  v_mode := upper(btrim(coalesce(p_inventory_mode, 'UNTRACKED')));

  if v_mode = 'RECIPE'
     or jsonb_array_length(coalesce(p_recipe, '[]'::jsonb)) > 0 then
    raise exception 'Recipe ingredient tracking is outside the approved system scope';
  end if;

  if v_mode not in ('UNTRACKED', 'FINISHED_GOOD') then
    raise exception 'Invalid inventory tracking mode';
  end if;

  if v_mode = 'FINISHED_GOOD' then
    if p_finished_inventory_item_id is null then
      raise exception 'Finished inventory item is required';
    end if;

    if not exists (
      select 1
      from public.inventory_items
      where id = p_finished_inventory_item_id
        and is_active = true
        and track_inventory = true
    ) then
      raise exception 'Finished inventory item is unavailable';
    end if;

    update public.menu_variants
    set track_finished_inventory = true,
        finished_inventory_item_id = p_finished_inventory_item_id
    where id = p_variant_id;
  else
    update public.menu_variants
    set track_finished_inventory = false,
        finished_inventory_item_id = null
    where id = p_variant_id;
  end if;
end;
$$;

revoke all on function public.apply_variant_inventory_configuration(
  uuid,text,uuid,jsonb
) from public, anon, authenticated;

create or replace function public.replace_modifier_recipe(
  p_modifier_id uuid,
  p_recipe jsonb default '[]'::jsonb
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.has_permission('menu.manage') then
    raise exception 'Permission denied';
  end if;

  if not exists (select 1 from public.modifiers where id = p_modifier_id) then
    raise exception 'Modifier not found';
  end if;

  if jsonb_typeof(coalesce(p_recipe, '[]'::jsonb)) <> 'array' then
    raise exception 'Modifier recipe must be an array';
  end if;

  if jsonb_array_length(coalesce(p_recipe, '[]'::jsonb)) > 0 then
    raise exception 'Modifier ingredient tracking is outside the approved system scope';
  end if;

  delete from public.modifier_recipe_components
  where modifier_id = p_modifier_id;
end;
$$;

revoke all on function public.replace_modifier_recipe(uuid,jsonb)
from public, anon, authenticated;

-- The management view now reports only the approved inventory modes.
create or replace view public.v_menu_management
with (security_invoker = true)
as
select
  mi.id as menu_item_id,
  mi.name as item_name,
  mi.description,
  mi.category_id,
  mc.name as category_name,
  mi.is_active as item_active,
  mv.id as variant_id,
  mv.sku,
  mv.name as variant_name,
  mv.price,
  mv.is_default,
  mv.is_active as variant_active,
  mv.track_finished_inventory,
  mv.finished_inventory_item_id,
  fii.name as finished_inventory_name,
  case
    when mv.track_finished_inventory then 'FINISHED_GOOD'
    else 'UNTRACKED'
  end as inventory_tracking_mode,
  0::integer as recipe_component_count
from public.menu_items mi
left join public.menu_categories mc on mc.id = mi.category_id
join public.menu_variants mv on mv.menu_item_id = mi.id
left join public.inventory_items fii on fii.id = mv.finished_inventory_item_id;

grant select on public.v_menu_management to authenticated;
revoke all on public.v_menu_management from anon;

-- One posted stock-out transaction may contain many supply lines. Quantities
-- are entered in a practical release unit (box/pack/piece) and stored in the
-- inventory item's base unit for ledger consistency.
insert into public.units_of_measure(
  code, name, dimension, factor_to_dimension_base
)
values
  ('box', 'Box', 'COUNT', 1),
  ('pack', 'Pack', 'COUNT', 1)
on conflict (code) do nothing;

create table public.stock_out_transactions (
  id uuid primary key default gen_random_uuid(),
  stock_out_number bigint generated by default as identity unique,
  occurred_at timestamptz not null default now(),
  purpose text not null check (length(btrim(purpose)) > 0),
  reference_number text,
  notes text,
  status text not null default 'DRAFT'
    check (status in ('DRAFT', 'POSTED', 'VOIDED')),
  recorded_by uuid not null references public.profiles(id),
  posted_at timestamptz,
  created_at timestamptz not null default now()
);

create table public.stock_out_items (
  id uuid primary key default gen_random_uuid(),
  stock_out_id uuid not null
    references public.stock_out_transactions(id) on delete restrict,
  inventory_item_id uuid not null references public.inventory_items(id),
  issue_uom_id uuid not null references public.units_of_measure(id),
  issue_quantity numeric(14,4) not null check (issue_quantity > 0),
  base_quantity_per_issue_unit numeric(14,4) not null
    check (base_quantity_per_issue_unit > 0),
  base_quantity numeric(14,4) not null check (base_quantity > 0),
  notes text,
  unique (stock_out_id, inventory_item_id)
);

alter table public.stock_movements
add column stock_out_item_id uuid
references public.stock_out_items(id) on delete restrict;

create index idx_stock_out_transactions_occurred_at
  on public.stock_out_transactions(occurred_at desc);
create index idx_stock_out_transactions_recorded_by
  on public.stock_out_transactions(recorded_by, occurred_at desc);
create index idx_stock_out_items_transaction
  on public.stock_out_items(stock_out_id);
create index idx_stock_out_items_inventory_item
  on public.stock_out_items(inventory_item_id);
create index idx_stock_movements_stock_out_item
  on public.stock_movements(stock_out_item_id)
  where stock_out_item_id is not null;

alter table public.stock_out_transactions enable row level security;
alter table public.stock_out_items enable row level security;

create policy "stock out transactions view"
on public.stock_out_transactions for select to authenticated
using (public.has_permission('inventory.view'));

create policy "stock out items view"
on public.stock_out_items for select to authenticated
using (public.has_permission('inventory.view'));

grant select on public.stock_out_transactions, public.stock_out_items
to authenticated;
revoke all on public.stock_out_transactions, public.stock_out_items from anon;

create or replace view public.v_stock_out_summary
with (security_invoker = true)
as
select
  so.id,
  so.stock_out_number,
  so.occurred_at,
  so.purpose,
  so.reference_number,
  so.notes,
  so.status,
  so.recorded_by,
  coalesce(p.display_name, concat_ws(' ', p.first_name, p.last_name))
    as recorded_by_name,
  count(soi.id)::integer as line_count,
  coalesce(sum(soi.base_quantity), 0)::numeric(14,4) as total_base_quantity
from public.stock_out_transactions so
left join public.profiles p on p.id = so.recorded_by
left join public.stock_out_items soi on soi.stock_out_id = so.id
group by so.id, p.display_name, p.first_name, p.last_name;

grant select on public.v_stock_out_summary to authenticated;
revoke all on public.v_stock_out_summary from anon;

-- Present every ledger entry together with the business document that caused
-- it. This gives the per-item history a readable receipt/order/stock-out trail
-- instead of exposing only internal UUID references.
create or replace view public.v_inventory_movement_history
with (security_invoker = true)
as
select
  sm.id,
  sm.inventory_item_id,
  sm.inventory_lot_id,
  sm.movement_type,
  sm.quantity_delta,
  sm.unit_cost_base,
  sm.reference_type,
  sm.reference_id,
  sm.order_id,
  sm.order_item_id,
  sm.stock_out_item_id,
  sm.reason,
  sm.recorded_by,
  sm.created_at,
  case
    when sm.reference_type = 'STOCK_OUT' then
      'SO-' || so.stock_out_number::text
    when sm.reference_type = 'GOODS_RECEIPT' then
      'GR-' || gr.receipt_number::text
    when sm.reference_type = 'ORDER' then
      'ORD-' || o.order_number::text
    else null
  end as source_document_number,
  case
    when sm.reference_type = 'STOCK_OUT' then so.reference_number
    when sm.reference_type = 'GOODS_RECEIPT' then gr.supplier_invoice_number
    else null
  end as external_reference_number
from public.stock_movements sm
left join public.stock_out_transactions so
  on sm.reference_type = 'STOCK_OUT' and so.id = sm.reference_id
left join public.goods_receipts gr
  on sm.reference_type = 'GOODS_RECEIPT' and gr.id = sm.reference_id
left join public.orders o
  on sm.reference_type = 'ORDER' and o.id = sm.reference_id;

grant select on public.v_inventory_movement_history to authenticated;
revoke all on public.v_inventory_movement_history from anon;

create or replace function public.create_and_post_stock_out(
  p_purpose text,
  p_items jsonb,
  p_reference_number text default null,
  p_notes text default null,
  p_occurred_at timestamptz default now()
)
returns public.stock_out_transactions
language plpgsql
security definer
set search_path = public
as $$
declare
  v_stock_out public.stock_out_transactions%rowtype;
  v_item public.inventory_items%rowtype;
  v_line jsonb;
  v_lot public.inventory_lots%rowtype;
  v_stock_out_item_id uuid;
  v_inventory_item_id uuid;
  v_issue_uom_id uuid;
  v_issue_quantity numeric(14,4);
  v_base_per_unit numeric(14,4);
  v_base_quantity numeric(14,4);
  v_remaining numeric(14,4);
  v_take numeric(14,4);
begin
  if not public.has_permission('inventory.adjust') then
    raise exception 'Permission denied';
  end if;

  if nullif(btrim(coalesce(p_purpose, '')), '') is null then
    raise exception 'Stock-out purpose is required';
  end if;

  if jsonb_typeof(coalesce(p_items, '[]'::jsonb)) <> 'array'
     or jsonb_array_length(coalesce(p_items, '[]'::jsonb)) = 0 then
    raise exception 'At least one stock-out item is required';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(p_items) line
    group by line ->> 'inventory_item_id'
    having count(*) > 1
  ) then
    raise exception 'Each inventory item may appear only once per stock-out';
  end if;

  insert into public.stock_out_transactions(
    occurred_at, purpose, reference_number, notes, status, recorded_by
  )
  values (
    coalesce(p_occurred_at, now()), btrim(p_purpose),
    nullif(btrim(coalesce(p_reference_number, '')), ''),
    nullif(btrim(coalesce(p_notes, '')), ''), 'DRAFT', auth.uid()
  )
  returning * into v_stock_out;

  for v_line in select value from jsonb_array_elements(p_items)
  loop
    v_inventory_item_id := nullif(v_line ->> 'inventory_item_id', '')::uuid;
    v_issue_uom_id := nullif(v_line ->> 'issue_uom_id', '')::uuid;
    v_issue_quantity := nullif(v_line ->> 'issue_quantity', '')::numeric;
    v_base_per_unit :=
      nullif(v_line ->> 'base_quantity_per_issue_unit', '')::numeric;

    if v_inventory_item_id is null or v_issue_uom_id is null then
      raise exception 'Inventory item and release unit are required';
    end if;

    if v_issue_quantity is null or v_issue_quantity <= 0
       or v_base_per_unit is null or v_base_per_unit <= 0 then
      raise exception 'Stock-out quantities must be greater than zero';
    end if;

    select * into v_item
    from public.inventory_items
    where id = v_inventory_item_id
      and is_active = true
      and track_inventory = true
    for update;

    if not found then
      raise exception 'Tracked inventory item is unavailable';
    end if;

    if not exists (
      select 1
      from public.units_of_measure issue_uom
      join public.units_of_measure base_uom
        on base_uom.id = v_item.base_uom_id
       and base_uom.dimension = issue_uom.dimension
      where issue_uom.id = v_issue_uom_id
        and issue_uom.is_active = true
    ) then
      raise exception 'Release unit is unavailable or incompatible with the item base unit';
    end if;

    v_base_quantity := v_issue_quantity * v_base_per_unit;

    insert into public.stock_out_items(
      stock_out_id, inventory_item_id, issue_uom_id, issue_quantity,
      base_quantity_per_issue_unit, base_quantity, notes
    )
    values (
      v_stock_out.id, v_inventory_item_id, v_issue_uom_id,
      v_issue_quantity, v_base_per_unit, v_base_quantity,
      nullif(btrim(coalesce(v_line ->> 'notes', '')), '')
    )
    returning id into v_stock_out_item_id;

    v_remaining := v_base_quantity;

    for v_lot in
      select *
      from public.inventory_lots
      where inventory_item_id = v_inventory_item_id
        and remaining_quantity > 0
        and status = 'AVAILABLE'
        and (expiration_date is null or expiration_date >= current_date)
      order by expiration_date asc nulls last, received_at asc
      for update
    loop
      exit when v_remaining <= 0;
      v_take := least(v_remaining, v_lot.remaining_quantity);

      update public.inventory_lots
      set remaining_quantity = remaining_quantity - v_take,
          status = case
            when remaining_quantity - v_take <= 0 then 'DEPLETED'
            else status
          end
      where id = v_lot.id;

      insert into public.stock_movements(
        inventory_item_id, inventory_lot_id, movement_type,
        quantity_delta, unit_cost_base, reference_type, reference_id,
        stock_out_item_id, reason, recorded_by
      )
      values (
        v_inventory_item_id, v_lot.id, 'MANUAL_OUT',
        -v_take, v_lot.unit_cost_base, 'STOCK_OUT', v_stock_out.id,
        v_stock_out_item_id, btrim(p_purpose), auth.uid()
      );

      v_remaining := v_remaining - v_take;
    end loop;

    if v_remaining > 0 then
      raise exception 'Insufficient usable stock for item %', v_item.name;
    end if;
  end loop;

  update public.stock_out_transactions
  set status = 'POSTED', posted_at = now()
  where id = v_stock_out.id
  returning * into v_stock_out;

  insert into public.audit_logs(
    actor_user_id, action_code, entity_type, entity_id, new_data
  )
  values (
    auth.uid(), 'STOCK_OUT_POSTED', 'stock_out_transaction',
    v_stock_out.id::text,
    jsonb_build_object(
      'stock_out_number', v_stock_out.stock_out_number,
      'purpose', v_stock_out.purpose,
      'line_count', jsonb_array_length(p_items)
    )
  );

  return v_stock_out;
end;
$$;

revoke all on function public.create_and_post_stock_out(
  text,jsonb,text,text,timestamptz
) from public, anon;
grant execute on function public.create_and_post_stock_out(
  text,jsonb,text,text,timestamptz
) to authenticated;
