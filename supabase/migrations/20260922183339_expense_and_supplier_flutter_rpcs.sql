-- Secure expense and supplier management RPCs for Flutter.

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
set search_path = public
as $$
declare
  v_expense public.expenses%rowtype;
begin
  if not public.has_permission('expenses.manage') then
    raise exception 'Permission denied';
  end if;
  if nullif(btrim(coalesce(p_description,'')), '') is null then
    raise exception 'Description is required';
  end if;
  if p_amount is null or p_amount <= 0 then
    raise exception 'Amount must be greater than zero';
  end if;
  if not exists (
    select 1 from public.expense_categories
    where id = p_expense_category_id and is_active = true
  ) then
    raise exception 'Invalid expense category';
  end if;

  insert into public.expenses(
    expense_date,expense_category_id,expense_type,description,amount,
    payment_method_id,supplier_id,reference_number,status,recorded_by,notes
  )
  values (
    coalesce(p_expense_date,current_date),p_expense_category_id,'OPERATING',
    btrim(p_description),round(p_amount,2),p_payment_method_id,p_supplier_id,
    nullif(btrim(coalesce(p_reference_number,'')), ''),'POSTED',auth.uid(),
    nullif(btrim(coalesce(p_notes,'')), '')
  )
  returning * into v_expense;
  return v_expense;
end;
$$;

revoke all on function public.create_expense(uuid,text,numeric,date,uuid,uuid,text,text)
from public, anon;
grant execute on function public.create_expense(uuid,text,numeric,date,uuid,uuid,text,text)
to authenticated;

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
set search_path = public
as $$
declare
  v_expense public.expenses%rowtype;
begin
  if not public.has_permission('expenses.manage') then
    raise exception 'Permission denied';
  end if;

  select * into v_expense
  from public.expenses
  where id = p_expense_id
  for update;

  if not found or v_expense.status = 'VOIDED' then
    raise exception 'Expense not available';
  end if;

  update public.expenses
  set
    expense_category_id = p_expense_category_id,
    description = btrim(p_description),
    amount = round(p_amount,2),
    expense_date = coalesce(p_expense_date,expense_date),
    payment_method_id = p_payment_method_id,
    supplier_id = p_supplier_id,
    reference_number = nullif(btrim(coalesce(p_reference_number,'')), ''),
    notes = nullif(btrim(coalesce(p_notes,'')), '')
  where id = p_expense_id
  returning * into v_expense;

  return v_expense;
end;
$$;

revoke all on function public.update_expense(uuid,uuid,text,numeric,date,uuid,uuid,text,text)
from public, anon;
grant execute on function public.update_expense(uuid,uuid,text,numeric,date,uuid,uuid,text,text)
to authenticated;

create or replace function public.void_expense(
  p_expense_id uuid,
  p_reason text default null
)
returns public.expenses
language plpgsql
security definer
set search_path = public
as $$
declare
  v_expense public.expenses%rowtype;
begin
  if not public.has_permission('expenses.manage') then
    raise exception 'Permission denied';
  end if;

  update public.expenses
  set status = 'VOIDED',
      notes = concat_ws(E'\n', notes, nullif(btrim(coalesce(p_reason,'')), ''))
  where id = p_expense_id
    and status <> 'VOIDED'
  returning * into v_expense;

  if not found then
    raise exception 'Expense not available';
  end if;

  return v_expense;
end;
$$;

revoke all on function public.void_expense(uuid,text) from public, anon;
grant execute on function public.void_expense(uuid,text) to authenticated;

create or replace function public.create_supplier(
  p_name text,
  p_contact_person text default null,
  p_phone text default null,
  p_email text default null,
  p_address text default null,
  p_payment_terms_days integer default 0,
  p_notes text default null
)
returns public.suppliers
language plpgsql
security definer
set search_path = public
as $$
declare
  v_supplier public.suppliers%rowtype;
begin
  if not public.has_permission('suppliers.manage') then
    raise exception 'Permission denied';
  end if;

  if nullif(btrim(coalesce(p_name,'')), '') is null then
    raise exception 'Supplier name is required';
  end if;

  insert into public.suppliers(
    name,contact_person,phone,email,address,payment_terms_days,notes,is_active
  )
  values (
    btrim(p_name),nullif(btrim(coalesce(p_contact_person,'')), ''),
    nullif(btrim(coalesce(p_phone,'')), ''),nullif(btrim(coalesce(p_email,'')), ''),
    nullif(btrim(coalesce(p_address,'')), ''),coalesce(p_payment_terms_days,0),
    nullif(btrim(coalesce(p_notes,'')), ''),true
  )
  returning * into v_supplier;
  return v_supplier;
end;
$$;

revoke all on function public.create_supplier(text,text,text,text,text,integer,text)
from public, anon;
grant execute on function public.create_supplier(text,text,text,text,text,integer,text)
to authenticated;

create or replace function public.update_supplier(
  p_supplier_id uuid,
  p_name text,
  p_contact_person text default null,
  p_phone text default null,
  p_email text default null,
  p_address text default null,
  p_payment_terms_days integer default 0,
  p_notes text default null,
  p_is_active boolean default true
)
returns public.suppliers
language plpgsql
security definer
set search_path = public
as $$
declare
  v_supplier public.suppliers%rowtype;
begin
  if not public.has_permission('suppliers.manage') then
    raise exception 'Permission denied';
  end if;

  update public.suppliers
  set
    name = btrim(p_name),
    contact_person = nullif(btrim(coalesce(p_contact_person,'')), ''),
    phone = nullif(btrim(coalesce(p_phone,'')), ''),
    email = nullif(btrim(coalesce(p_email,'')), ''),
    address = nullif(btrim(coalesce(p_address,'')), ''),
    payment_terms_days = coalesce(p_payment_terms_days,0),
    notes = nullif(btrim(coalesce(p_notes,'')), ''),
    is_active = coalesce(p_is_active,true),
    archived_at = case when coalesce(p_is_active,true) then null else now() end
  where id = p_supplier_id
  returning * into v_supplier;

  if not found then
    raise exception 'Supplier not found';
  end if;

  return v_supplier;
end;
$$;

revoke all on function public.update_supplier(uuid,text,text,text,text,text,integer,text,boolean)
from public, anon;
grant execute on function public.update_supplier(uuid,text,text,text,text,text,integer,text,boolean)
to authenticated;
