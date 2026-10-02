-- Align POS/menu availability and expense traceability with the approved
-- consultation workflow. Prepared products never deduct recipe ingredients;
-- only explicitly linked countable finished goods affect inventory.

create or replace view public.v_pos_menu
with (security_invoker = true)
as
select
  mv.id as variant_id,
  mi.id as menu_item_id,
  mv.sku,
  mi.name as item_name,
  mv.name as variant_name,
  mc.name as category_name,
  mv.price,
  mv.sort_order as variant_sort_order,
  coalesce(mc.sort_order, 999) as category_sort_order,
  mv.is_default,
  case
    when mv.track_finished_inventory then 'FINISHED_GOOD'
    else 'UNTRACKED'
  end as inventory_tracking_mode,
  case
    when mv.track_finished_inventory then
      floor(coalesce(finished_stock.usable_quantity, 0))
    else null
  end::numeric(14,4) as available_quantity
from public.menu_variants mv
join public.menu_items mi on mi.id = mv.menu_item_id
left join public.menu_categories mc on mc.id = mi.category_id
left join public.v_inventory_stock finished_stock
  on finished_stock.inventory_item_id = mv.finished_inventory_item_id
where mv.is_active = true
  and mi.is_active = true;

grant select on public.v_pos_menu to authenticated;
revoke all on public.v_pos_menu from anon;

-- Posted expenses must identify who was paid and the receipt/reference used
-- to verify the transaction. Existing historical rows remain readable, while
-- every new or edited posted transaction is checked by this trigger.
create or replace function public.guard_expense_traceability()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.status = 'POSTED' then
    if new.supplier_id is null then
      raise exception 'Supplier or grocery is required for a posted expense';
    end if;

    if nullif(btrim(coalesce(new.reference_number, '')), '') is null then
      raise exception 'Receipt or reference number is required for a posted expense';
    end if;

    if exists (
      select 1
      from public.expenses e
      where e.supplier_id = new.supplier_id
        and lower(btrim(e.reference_number)) =
          lower(btrim(new.reference_number))
        and e.status <> 'VOIDED'
        and e.id <> new.id
    ) then
      raise exception 'This supplier receipt or reference is already recorded';
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_guard_expense_traceability
on public.expenses;

create trigger trg_guard_expense_traceability
before insert or update of supplier_id, reference_number, status
on public.expenses
for each row execute function public.guard_expense_traceability();

revoke all on function public.guard_expense_traceability()
from public, anon, authenticated;

create index if not exists idx_expenses_supplier_reference
on public.expenses(
  supplier_id,
  lower(btrim(reference_number))
)
where status <> 'VOIDED'
  and reference_number is not null;

create or replace function public.create_expense(
  p_expense_category_id uuid,
  p_description text,
  p_amount numeric,
  p_expense_date date default current_date,
  p_payment_method_id uuid default null,
  p_supplier_id uuid default null,
  p_reference_number text default null,
  p_notes text default null
)
returns public.expenses
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_expense public.expenses%rowtype;
  v_category_code text;
begin
  if not public.has_permission('expenses.manage') then
    raise exception 'Permission denied';
  end if;

  if nullif(btrim(coalesce(p_description, '')), '') is null then
    raise exception 'Expense purpose is required';
  end if;

  if p_amount is null or p_amount <= 0 then
    raise exception 'Amount must be greater than zero';
  end if;

  if p_supplier_id is null or not exists (
    select 1
    from public.suppliers s
    where s.id = p_supplier_id
      and s.is_active = true
  ) then
    raise exception 'A valid supplier or grocery is required';
  end if;

  if nullif(btrim(coalesce(p_reference_number, '')), '') is null then
    raise exception 'Receipt or reference number is required';
  end if;

  select ec.code
  into v_category_code
  from public.expense_categories ec
  where ec.id = p_expense_category_id
    and ec.is_active = true;

  if not found then
    raise exception 'Invalid expense category';
  end if;

  if p_payment_method_id is not null and not exists (
    select 1
    from public.payment_methods pm
    where pm.id = p_payment_method_id
      and pm.is_active = true
  ) then
    raise exception 'Invalid payment method';
  end if;

  insert into public.expenses(
    expense_date,
    expense_category_id,
    expense_type,
    description,
    amount,
    payment_method_id,
    supplier_id,
    reference_number,
    status,
    recorded_by,
    notes
  )
  values (
    coalesce(p_expense_date, current_date),
    p_expense_category_id,
    case
      when v_category_code = 'INGREDIENTS' then 'NON_INVENTORY_PURCHASE'
      else 'OPERATING'
    end,
    btrim(p_description),
    round(p_amount, 2),
    p_payment_method_id,
    p_supplier_id,
    btrim(p_reference_number),
    'POSTED',
    auth.uid(),
    nullif(btrim(coalesce(p_notes, '')), '')
  )
  returning * into v_expense;

  return v_expense;
end;
$$;

revoke all on function public.create_expense(
  uuid,text,numeric,date,uuid,uuid,text,text
) from public, anon, authenticated;
grant execute on function public.create_expense(
  uuid,text,numeric,date,uuid,uuid,text,text
) to authenticated;

create or replace function public.update_expense(
  p_expense_id uuid,
  p_expense_category_id uuid,
  p_description text,
  p_amount numeric,
  p_expense_date date,
  p_payment_method_id uuid default null,
  p_supplier_id uuid default null,
  p_reference_number text default null,
  p_notes text default null
)
returns public.expenses
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_expense public.expenses%rowtype;
  v_category_code text;
begin
  if not public.has_permission('expenses.manage') then
    raise exception 'Permission denied';
  end if;

  select *
  into v_expense
  from public.expenses e
  where e.id = p_expense_id
  for update;

  if not found or v_expense.status = 'VOIDED' then
    raise exception 'Expense not available';
  end if;

  if nullif(btrim(coalesce(p_description, '')), '') is null then
    raise exception 'Expense purpose is required';
  end if;

  if p_amount is null or p_amount <= 0 then
    raise exception 'Amount must be greater than zero';
  end if;

  if p_supplier_id is null or not exists (
    select 1
    from public.suppliers s
    where s.id = p_supplier_id
      and s.is_active = true
  ) then
    raise exception 'A valid supplier or grocery is required';
  end if;

  if nullif(btrim(coalesce(p_reference_number, '')), '') is null then
    raise exception 'Receipt or reference number is required';
  end if;

  select ec.code
  into v_category_code
  from public.expense_categories ec
  where ec.id = p_expense_category_id
    and ec.is_active = true;

  if not found then
    raise exception 'Invalid expense category';
  end if;

  if p_payment_method_id is not null and not exists (
    select 1
    from public.payment_methods pm
    where pm.id = p_payment_method_id
      and pm.is_active = true
  ) then
    raise exception 'Invalid payment method';
  end if;

  update public.expenses
  set
    expense_category_id = p_expense_category_id,
    expense_type = case
      when v_category_code = 'INGREDIENTS' then 'NON_INVENTORY_PURCHASE'
      else 'OPERATING'
    end,
    description = btrim(p_description),
    amount = round(p_amount, 2),
    expense_date = coalesce(p_expense_date, expense_date),
    payment_method_id = p_payment_method_id,
    supplier_id = p_supplier_id,
    reference_number = btrim(p_reference_number),
    notes = nullif(btrim(coalesce(p_notes, '')), '')
  where id = p_expense_id
  returning * into v_expense;

  return v_expense;
end;
$$;

revoke all on function public.update_expense(
  uuid,uuid,text,numeric,date,uuid,uuid,text,text
) from public, anon, authenticated;
grant execute on function public.update_expense(
  uuid,uuid,text,numeric,date,uuid,uuid,text,text
) to authenticated;
