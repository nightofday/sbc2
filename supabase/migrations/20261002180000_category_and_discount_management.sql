-- CAT-01 and DIS-01: let management maintain categories and promotional
-- discounts from the app.
--
-- Until now categories could only be read, and the discounts offered at the
-- till were three codes hard-wired into two functions (S-13). Both needed a
-- developer and SQL to change.

-- ============================================================
-- 1. Categories (menu, inventory, expense)
-- ============================================================

alter table public.inventory_categories
  add column sort_order integer not null default 0;

alter table public.expense_categories
  add column sort_order integer not null default 0;

-- "Coffee", "coffee" and " Coffee " are the same category.
create unique index uq_menu_categories_name_normalized
  on public.menu_categories (lower(btrim(name)));
create unique index uq_inventory_categories_name_normalized
  on public.inventory_categories (lower(btrim(name)));
create unique index uq_expense_categories_name_normalized
  on public.expense_categories (lower(btrim(name)));

-- Maps a domain to its table, the table and column that use it, and the
-- permission needed to maintain it. The three domains stay separate tables.
create function public.category_domain(
  p_domain text,
  out category_table text,
  out usage_table text,
  out usage_column text,
  out permission_code text,
  out entity_type text
)
language plpgsql
immutable
set search_path = ''
as $$
begin
  case upper(btrim(coalesce(p_domain, '')))
    when 'MENU' then
      category_table := 'menu_categories';
      usage_table := 'menu_items';
      usage_column := 'category_id';
      permission_code := 'menu.manage';
      entity_type := 'menu_category';
    when 'INVENTORY' then
      category_table := 'inventory_categories';
      usage_table := 'inventory_items';
      usage_column := 'category_id';
      permission_code := 'inventory.manage';
      entity_type := 'inventory_category';
    when 'EXPENSE' then
      category_table := 'expense_categories';
      usage_table := 'expenses';
      usage_column := 'expense_category_id';
      permission_code := 'expenses.manage';
      entity_type := 'expense_category';
    else
      raise exception 'Unknown category type';
  end case;
end;
$$;

-- Every category of a domain, including archived ones, with how many
-- records use each. For the management screen only.
create function public.list_categories(p_domain text)
returns table (
  id uuid,
  name text,
  description text,
  sort_order integer,
  is_active boolean,
  usage_count bigint
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_domain record;
begin
  select * into v_domain from public.category_domain(p_domain);

  if not public.has_permission(v_domain.permission_code) then
    raise exception 'Permission denied';
  end if;

  return query execute format(
    'select c.id, c.name, c.description, c.sort_order, c.is_active, '
    '(select count(*) from public.%I u where u.%I = c.id) '
    'from public.%I c order by c.sort_order, lower(c.name)',
    v_domain.usage_table, v_domain.usage_column, v_domain.category_table
  );
end;
$$;

create function public.create_category(
  p_domain text,
  p_name text,
  p_description text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_domain record;
  v_name text := nullif(btrim(coalesce(p_name, '')), '');
  v_existing_active boolean;
  v_sort integer;
  v_code text;
  v_base_code text;
  v_suffix integer := 1;
  v_taken boolean;
  v_id uuid;
begin
  select * into v_domain from public.category_domain(p_domain);

  if not public.has_permission(v_domain.permission_code) then
    raise exception 'Permission denied';
  end if;

  if v_name is null then
    raise exception 'Category name is required';
  end if;

  execute format(
    'select c.is_active from public.%I c '
    'where lower(btrim(c.name)) = lower($1) limit 1',
    v_domain.category_table
  )
  into v_existing_active
  using v_name;

  if v_existing_active is true then
    raise exception 'A category with this name already exists';
  elsif v_existing_active is false then
    raise exception
      'An archived category has this name. Reactivate it instead.';
  end if;

  execute format(
    'select coalesce(max(c.sort_order), 0) + 10 from public.%I c',
    v_domain.category_table
  )
  into v_sort;

  if v_domain.category_table = 'expense_categories' then
    -- Expense categories carry a stable code that survives renaming.
    v_base_code := btrim(
      upper(regexp_replace(v_name, '[^A-Za-z0-9]+', '_', 'g')), '_'
    );
    if v_base_code = '' then
      v_base_code := 'CATEGORY';
    end if;
    v_code := v_base_code;
    loop
      select exists (
        select 1 from public.expense_categories ec where ec.code = v_code
      )
      into v_taken;
      exit when not v_taken;
      v_suffix := v_suffix + 1;
      v_code := v_base_code || '_' || v_suffix::text;
    end loop;

    insert into public.expense_categories(
      code, name, description, sort_order, is_active
    )
    values (
      v_code, v_name, nullif(btrim(coalesce(p_description, '')), ''),
      v_sort, true
    )
    returning id into v_id;
  else
    execute format(
      'insert into public.%I(name, description, sort_order, is_active) '
      'values ($1, $2, $3, true) returning id',
      v_domain.category_table
    )
    into v_id
    using v_name, nullif(btrim(coalesce(p_description, '')), ''), v_sort;
  end if;

  insert into public.audit_logs(
    actor_user_id, action_code, entity_type, entity_id, new_data
  )
  values (
    auth.uid(), 'CATEGORY_CREATED', v_domain.entity_type, v_id::text,
    jsonb_build_object('name', v_name)
  );

  return v_id;
end;
$$;

-- Changes only what is supplied. Archiving a category that is in use is
-- allowed: records keep pointing at it, and it is no longer offered for new
-- ones. Nothing is reassigned or deleted.
create function public.update_category(
  p_domain text,
  p_category_id uuid,
  p_name text default null,
  p_description text default null,
  p_sort_order integer default null,
  p_is_active boolean default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_domain record;
  v_name text := nullif(btrim(coalesce(p_name, '')), '');
  v_old jsonb;
  v_new jsonb;
  v_duplicate boolean;
begin
  select * into v_domain from public.category_domain(p_domain);

  if not public.has_permission(v_domain.permission_code) then
    raise exception 'Permission denied';
  end if;

  if p_name is not null and v_name is null then
    raise exception 'Category name is required';
  end if;

  execute format(
    'select to_jsonb(c) from public.%I c where c.id = $1 for update',
    v_domain.category_table
  )
  into v_old
  using p_category_id;

  if v_old is null then
    raise exception 'Category not found';
  end if;

  if v_name is not null then
    execute format(
      'select exists (select 1 from public.%I c '
      'where lower(btrim(c.name)) = lower($1) and c.id <> $2)',
      v_domain.category_table
    )
    into v_duplicate
    using v_name, p_category_id;

    if v_duplicate then
      raise exception 'A category with this name already exists';
    end if;
  end if;

  execute format(
    'update public.%I c set '
    'name = coalesce($1, c.name), '
    'description = case when $2 is null then c.description '
    '  else nullif(btrim($2), '''') end, '
    'sort_order = coalesce($3, c.sort_order), '
    'is_active = coalesce($4, c.is_active) '
    'where c.id = $5 returning to_jsonb(c)',
    v_domain.category_table
  )
  into v_new
  using v_name, p_description, p_sort_order, p_is_active, p_category_id;

  insert into public.audit_logs(
    actor_user_id, action_code, entity_type, entity_id, old_data, new_data
  )
  values (
    auth.uid(), 'CATEGORY_UPDATED', v_domain.entity_type,
    p_category_id::text, v_old, v_new
  );
end;
$$;

-- Sets the display order to the order of the IDs given.
create function public.reorder_categories(
  p_domain text,
  p_category_ids uuid[]
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_domain record;
begin
  select * into v_domain from public.category_domain(p_domain);

  if not public.has_permission(v_domain.permission_code) then
    raise exception 'Permission denied';
  end if;

  execute format(
    'update public.%I c set sort_order = o.position::integer * 10 '
    'from unnest($1) with ordinality as o(id, position) '
    'where c.id = o.id',
    v_domain.category_table
  )
  using p_category_ids;
end;
$$;

revoke all on function public.category_domain(text)
from public, anon, authenticated;

revoke all on function public.list_categories(text) from public, anon;
grant execute on function public.list_categories(text) to authenticated;

revoke all on function public.create_category(text,text,text)
from public, anon;
grant execute on function public.create_category(text,text,text)
to authenticated;

revoke all on function public.update_category(
  text,uuid,text,text,integer,boolean
) from public, anon;
grant execute on function public.update_category(
  text,uuid,text,text,integer,boolean
) to authenticated;

revoke all on function public.reorder_categories(text,uuid[])
from public, anon;
grant execute on function public.reorder_categories(text,uuid[])
to authenticated;

-- ============================================================
-- 2. Promotional discounts
-- ============================================================

alter table public.discount_types
  add column is_pos_enabled boolean not null default false,
  add column allow_custom_value boolean not null default false,
  add column max_value numeric(14,4)
    check (max_value is null or max_value > 0),
  add column valid_from date,
  add column valid_until date,
  add column updated_at timestamptz not null default now(),
  add constraint chk_discount_types_validity
    check (
      valid_from is null or valid_until is null or valid_until >= valid_from
    ),
  -- Senior, PWD and other statutory discounts stay out of the till until
  -- their tax treatment is confirmed (OPS-03).
  add constraint chk_discount_types_statutory_not_in_pos
    check (not (is_pos_enabled and (requires_id or is_tax_exempt_related)));

create unique index uq_discount_types_name_normalized
  on public.discount_types (lower(btrim(name)));

-- The three types the till already offered keep working exactly as before:
-- enabled, with the value typed at the till.
update public.discount_types
set is_pos_enabled = true,
    allow_custom_value = true
where code in ('PROMO_PERCENT', 'PROMO_FIXED', 'MANUAL');

create function public.create_discount_type(
  p_name text,
  p_calculation_method text,
  p_value numeric,
  p_allow_custom_value boolean default false,
  p_max_value numeric default null,
  p_valid_from date default null,
  p_valid_until date default null,
  p_notes text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_name text := nullif(btrim(coalesce(p_name, '')), '');
  v_method text := upper(btrim(coalesce(p_calculation_method, '')));
  v_custom boolean := coalesce(p_allow_custom_value, false);
  v_id uuid;
begin
  if not public.has_permission('discounts.manage') then
    raise exception 'Permission denied';
  end if;

  if v_name is null then
    raise exception 'Discount name is required';
  end if;

  if exists (
    select 1 from public.discount_types dt
    where lower(btrim(dt.name)) = lower(v_name)
  ) then
    raise exception 'A discount with this name already exists';
  end if;

  if v_method not in ('PERCENTAGE', 'FIXED_AMOUNT') then
    raise exception 'Discount must be a percentage or a fixed amount';
  end if;

  if p_value is null or p_value <= 0 then
    raise exception 'Discount value must be greater than zero';
  end if;

  if v_method = 'PERCENTAGE' and p_value > 100 then
    raise exception 'A percentage discount cannot be more than 100';
  end if;

  if p_max_value is not null then
    if not v_custom then
      raise exception
        'A maximum only applies when the value can be changed at the till';
    end if;
    if p_max_value < p_value
       or (v_method = 'PERCENTAGE' and p_max_value > 100) then
      raise exception 'Maximum value is out of range';
    end if;
  end if;

  if p_valid_from is not null and p_valid_until is not null
     and p_valid_until < p_valid_from then
    raise exception 'The end date cannot be before the start date';
  end if;

  insert into public.discount_types(
    code, name, calculation_method, default_value, requires_id,
    requires_authorization, is_tax_exempt_related, is_active, notes,
    is_pos_enabled, allow_custom_value, max_value, valid_from, valid_until
  )
  values (
    'PROMO_' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8)),
    v_name, v_method, p_value, false,
    -- Same rule as the existing promotions: whoever applies it must hold
    -- discounts.manage. Opening discounts to cashiers is a separate decision.
    true, false, true, nullif(btrim(coalesce(p_notes, '')), ''),
    true, v_custom, p_max_value, p_valid_from, p_valid_until
  )
  returning id into v_id;

  insert into public.audit_logs(
    actor_user_id, action_code, entity_type, entity_id, new_data
  )
  values (
    auth.uid(), 'DISCOUNT_TYPE_CREATED', 'discount_type', v_id::text,
    jsonb_build_object(
      'name', v_name, 'method', v_method, 'value', p_value
    )
  );

  return v_id;
end;
$$;

-- The form loads the whole definition and sends it all back. The calculation
-- method cannot change, because past orders were discounted under it.
create function public.update_discount_type(
  p_discount_type_id uuid,
  p_name text,
  p_value numeric,
  p_allow_custom_value boolean,
  p_max_value numeric,
  p_valid_from date,
  p_valid_until date,
  p_is_active boolean,
  p_notes text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_old public.discount_types%rowtype;
  v_new public.discount_types%rowtype;
  v_name text := nullif(btrim(coalesce(p_name, '')), '');
  v_custom boolean := coalesce(p_allow_custom_value, false);
begin
  if not public.has_permission('discounts.manage') then
    raise exception 'Permission denied';
  end if;

  select * into v_old
  from public.discount_types dt
  where dt.id = p_discount_type_id
  for update;

  if not found then
    raise exception 'Discount not found';
  end if;

  if v_old.requires_id or v_old.is_tax_exempt_related then
    raise exception
      'Statutory discounts are not managed here until their rules are confirmed';
  end if;

  if v_name is null then
    raise exception 'Discount name is required';
  end if;

  if exists (
    select 1 from public.discount_types dt
    where lower(btrim(dt.name)) = lower(v_name)
      and dt.id <> p_discount_type_id
  ) then
    raise exception 'A discount with this name already exists';
  end if;

  if p_value is null then
    if not v_custom then
      raise exception 'Discount value is required';
    end if;
  elsif p_value <= 0 then
    raise exception 'Discount value must be greater than zero';
  elsif v_old.calculation_method = 'PERCENTAGE' and p_value > 100 then
    raise exception 'A percentage discount cannot be more than 100';
  end if;

  if p_max_value is not null then
    if not v_custom then
      raise exception
        'A maximum only applies when the value can be changed at the till';
    end if;
    if (p_value is not null and p_max_value < p_value)
       or (v_old.calculation_method = 'PERCENTAGE' and p_max_value > 100) then
      raise exception 'Maximum value is out of range';
    end if;
  end if;

  if p_valid_from is not null and p_valid_until is not null
     and p_valid_until < p_valid_from then
    raise exception 'The end date cannot be before the start date';
  end if;

  update public.discount_types dt
  set name = v_name,
      default_value = p_value,
      allow_custom_value = v_custom,
      max_value = p_max_value,
      valid_from = p_valid_from,
      valid_until = p_valid_until,
      is_active = coalesce(p_is_active, dt.is_active),
      notes = nullif(btrim(coalesce(p_notes, '')), ''),
      updated_at = now()
  where dt.id = p_discount_type_id
  returning * into v_new;

  insert into public.audit_logs(
    actor_user_id, action_code, entity_type, entity_id, old_data, new_data
  )
  values (
    auth.uid(), 'DISCOUNT_TYPE_UPDATED', 'discount_type',
    p_discount_type_id::text, to_jsonb(v_old), to_jsonb(v_new)
  );
end;
$$;

revoke all on function public.create_discount_type(
  text,text,numeric,boolean,numeric,date,date,text
) from public, anon;
grant execute on function public.create_discount_type(
  text,text,numeric,boolean,numeric,date,date,text
) to authenticated;

revoke all on function public.update_discount_type(
  uuid,text,numeric,boolean,numeric,date,date,boolean,text
) from public, anon;
grant execute on function public.update_discount_type(
  uuid,text,numeric,boolean,numeric,date,date,boolean,text
) to authenticated;

-- The till lists what is enabled, active and valid today, instead of three
-- fixed codes. The result gains two columns, so the function is recreated.
drop function public.get_pos_discount_types();

create function public.get_pos_discount_types()
returns table(
  id uuid,
  code text,
  name text,
  calculation_method text,
  default_value numeric,
  requires_authorization boolean,
  allow_custom_value boolean,
  max_value numeric
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.has_permission('discounts.apply') then
    return;
  end if;

  return query
  select
    dt.id,
    dt.code,
    dt.name,
    dt.calculation_method,
    dt.default_value,
    dt.requires_authorization,
    dt.allow_custom_value,
    dt.max_value
  from public.discount_types dt
  where dt.is_active = true
    and dt.is_pos_enabled = true
    and (
      dt.valid_from is null
      or dt.valid_from <= (select public.business_today())
    )
    and (
      dt.valid_until is null
      or dt.valid_until >= (select public.business_today())
    )
  order by dt.name;
end;
$$;

revoke all on function public.get_pos_discount_types() from public, anon;
grant execute on function public.get_pos_discount_types() to authenticated;

-- Checkout enforces the same rules as the list.
create or replace function public.place_order_v2(
  p_order_type text,
  p_items jsonb,
  p_payment jsonb,
  p_discount jsonb default null,
  p_table_number text default null,
  p_customer_name text default null,
  p_delivery_reference text default null,
  p_notes text default null,
  p_client_request_id uuid default null
)
returns public.orders
language plpgsql
security definer
set search_path = public
as $$
declare
  v_existing public.orders%rowtype;
  v_order public.orders%rowtype;
  v_item jsonb;
  v_added public.order_items%rowtype;
  v_item_ids uuid[] := '{}'::uuid[];
  v_modifier_ids uuid[];
  v_discount_type public.discount_types%rowtype;
  v_discount_value numeric;
  v_payment_method public.payment_methods%rowtype;
  v_payment_method_id uuid;
  v_tendered numeric(14,2);
  v_change numeric(14,2) := 0;
  v_payments jsonb;
begin
  if p_client_request_id is not null then
    -- A second submission of the same request waits here until the first
    -- one commits or rolls back, then sees its result.
    perform pg_advisory_xact_lock(
      hashtextextended('order_request:' || p_client_request_id::text, 0)
    );

    select * into v_existing
    from public.orders
    where client_request_id = p_client_request_id;

    if found then
      if v_existing.created_by_user_id is distinct from auth.uid() then
        raise exception 'This request ID is not available';
      end if;

      -- Placement is one transaction, so a stored order is a finished sale.
      -- It may have been refunded since; it is still the result of this
      -- request and must not be sold again.
      if v_existing.status in ('COMPLETED','PARTIALLY_REFUNDED','REFUNDED') then
        return v_existing;
      end if;

      raise exception 'An unfinished order already exists for this request';
    end if;
  end if;

  if jsonb_typeof(coalesce(p_items,'[]'::jsonb)) <> 'array'
     or jsonb_array_length(coalesce(p_items,'[]'::jsonb)) = 0 then
    raise exception 'At least one order item is required';
  end if;

  if jsonb_typeof(coalesce(p_payment,'{}'::jsonb)) <> 'object' then
    raise exception 'Payment details are required';
  end if;

  v_order := public.create_order(
    p_order_type := p_order_type,
    p_table_number := p_table_number,
    p_customer_name := p_customer_name,
    p_source_code := 'POS',
    p_delivery_reference := p_delivery_reference,
    p_notes := p_notes,
    p_client_request_id := p_client_request_id
  );

  for v_item in select value from jsonb_array_elements(p_items)
  loop
    if nullif(v_item ->> 'menu_variant_id','') is null then
      raise exception 'Menu variant is required';
    end if;

    select coalesce(array_agg(x.value::uuid), '{}'::uuid[])
    into v_modifier_ids
    from jsonb_array_elements_text(
      coalesce(v_item -> 'modifier_ids', '[]'::jsonb)
    ) as x(value);

    v_added := public.add_order_item(
      v_order.id,
      (v_item ->> 'menu_variant_id')::uuid,
      coalesce((v_item ->> 'quantity')::numeric, 0),
      v_modifier_ids,
      nullif(btrim(coalesce(v_item ->> 'special_instructions','')), '')
    );

    v_item_ids := array_append(v_item_ids,v_added.id);
  end loop;

  if p_discount is not null
     and jsonb_typeof(p_discount) <> 'null' then
    select * into v_discount_type
    from public.discount_types
    where id = nullif(p_discount ->> 'discount_type_id','')::uuid
      and is_active = true;

    if not found then
      raise exception 'Discount type not found or inactive';
    end if;

    if not v_discount_type.is_pos_enabled then
      raise exception
        'This discount type is not enabled in POS until business rules are confirmed';
    end if;

    if (
      v_discount_type.valid_from is not null
      and v_discount_type.valid_from > (select public.business_today())
    ) or (
      v_discount_type.valid_until is not null
      and v_discount_type.valid_until < (select public.business_today())
    ) then
      raise exception 'This discount is not valid today';
    end if;

    -- A promotion with a fixed value ignores whatever the client sends.
    v_discount_value := case
      when v_discount_type.allow_custom_value then coalesce(
        nullif(p_discount ->> 'manual_value','')::numeric,
        v_discount_type.default_value
      )
      else v_discount_type.default_value
    end;

    if v_discount_type.max_value is not null
       and v_discount_value > v_discount_type.max_value then
      raise exception 'This discount cannot be more than %',
        trim(trailing '.' from trim(trailing '0' from v_discount_type.max_value::text));
    end if;

    perform public.apply_order_discount(
      v_order.id,
      v_discount_type.id,
      v_item_ids,
      null,
      null,
      v_discount_value,
      auth.uid(),
      nullif(btrim(coalesce(p_discount ->> 'notes','')), '')
    );
  end if;

  select * into v_order
  from public.orders
  where id = v_order.id;

  v_payment_method_id :=
    nullif(p_payment ->> 'payment_method_id','')::uuid;

  select * into v_payment_method
  from public.payment_methods
  where id = v_payment_method_id
    and is_active = true;

  if not found then
    raise exception 'Invalid or inactive payment method';
  end if;

  v_tendered :=
    nullif(p_payment ->> 'amount_tendered','')::numeric;

  if v_payment_method.is_cash then
    if v_tendered is null then
      raise exception 'Cash amount tendered is required';
    end if;
    v_change := round(v_tendered - v_order.total_amount,2);
  else
    v_change := 0;
  end if;

  v_payments := jsonb_build_array(
    jsonb_build_object(
      'payment_method_id',v_payment_method_id,
      'amount',v_order.total_amount,
      'amount_tendered',
        case when v_payment_method.is_cash then v_tendered else null end,
      'change_amount',v_change,
      'external_provider',
        nullif(btrim(coalesce(p_payment ->> 'external_provider','')), ''),
      'external_reference',
        nullif(btrim(coalesce(p_payment ->> 'external_reference','')), ''),
      'idempotency_key',
        nullif(p_payment ->> 'idempotency_key','')
    )
  );

  return public.checkout_order(v_order.id,v_payments);
end;
$$;
