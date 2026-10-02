-- Modifier management and POS modifier read model.

create or replace view public.v_pos_modifiers
with (security_invoker = true)
as
select
  mig.menu_item_id,
  mg.id as modifier_group_id,
  mg.name as group_name,
  mg.min_selections,
  mg.max_selections,
  mg.is_required,
  mg.sort_order as group_sort_order,
  m.id as modifier_id,
  m.name as modifier_name,
  m.price_delta,
  m.sort_order as modifier_sort_order
from public.menu_item_modifier_groups mig
join public.modifier_groups mg
  on mg.id = mig.modifier_group_id
 and mg.is_active = true
join public.modifiers m
  on m.modifier_group_id = mg.id
 and m.is_active = true
order by mig.menu_item_id, mig.sort_order, mg.sort_order, m.sort_order, m.name;

grant select on public.v_pos_modifiers to authenticated;
revoke all on public.v_pos_modifiers from anon;

create or replace function public.create_modifier_group_for_menu_item(
  p_menu_item_id uuid,
  p_group_name text,
  p_min_selections integer default 0,
  p_max_selections integer default null,
  p_is_required boolean default false
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_group_id uuid;
  v_min integer := coalesce(p_min_selections,0);
begin
  if not public.has_permission('menu.manage') then
    raise exception 'Permission denied';
  end if;

  if not exists (
    select 1 from public.menu_items
    where id = p_menu_item_id and is_active = true
  ) then
    raise exception 'Menu item not found or inactive';
  end if;

  if nullif(btrim(coalesce(p_group_name,'')), '') is null then
    raise exception 'Modifier group name is required';
  end if;

  if v_min < 0 then
    raise exception 'Minimum selections cannot be negative';
  end if;

  if coalesce(p_is_required,false) and v_min < 1 then
    raise exception 'Required modifier groups must require at least one selection';
  end if;

  if p_max_selections is not null
     and (p_max_selections < 1 or p_max_selections < v_min) then
    raise exception 'Maximum selections must be at least the minimum';
  end if;

  insert into public.modifier_groups(
    name,min_selections,max_selections,is_required,is_active
  )
  values (
    btrim(p_group_name),v_min,p_max_selections,coalesce(p_is_required,false),true
  )
  returning id into v_group_id;

  insert into public.menu_item_modifier_groups(
    menu_item_id,modifier_group_id,sort_order
  )
  values (
    p_menu_item_id,
    v_group_id,
    coalesce(
      (
        select max(sort_order) + 1
        from public.menu_item_modifier_groups
        where menu_item_id = p_menu_item_id
      ),
      0
    )
  );

  return v_group_id;
end;
$$;

revoke all on function public.create_modifier_group_for_menu_item(
  uuid,text,integer,integer,boolean
) from public, anon;
grant execute on function public.create_modifier_group_for_menu_item(
  uuid,text,integer,integer,boolean
) to authenticated;

create or replace function public.update_modifier_group(
  p_modifier_group_id uuid,
  p_group_name text,
  p_min_selections integer,
  p_max_selections integer,
  p_is_required boolean,
  p_is_active boolean
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_min integer := coalesce(p_min_selections,0);
begin
  if not public.has_permission('menu.manage') then
    raise exception 'Permission denied';
  end if;

  if nullif(btrim(coalesce(p_group_name,'')), '') is null then
    raise exception 'Modifier group name is required';
  end if;

  if v_min < 0 then
    raise exception 'Minimum selections cannot be negative';
  end if;

  if coalesce(p_is_required,false) and v_min < 1 then
    raise exception 'Required modifier groups must require at least one selection';
  end if;

  if p_max_selections is not null
     and (p_max_selections < 1 or p_max_selections < v_min) then
    raise exception 'Maximum selections must be at least the minimum';
  end if;

  update public.modifier_groups
  set
    name = btrim(p_group_name),
    min_selections = v_min,
    max_selections = p_max_selections,
    is_required = coalesce(p_is_required,false),
    is_active = coalesce(p_is_active,true)
  where id = p_modifier_group_id;

  if not found then
    raise exception 'Modifier group not found';
  end if;
end;
$$;

revoke all on function public.update_modifier_group(
  uuid,text,integer,integer,boolean,boolean
) from public, anon;
grant execute on function public.update_modifier_group(
  uuid,text,integer,integer,boolean,boolean
) to authenticated;

create or replace function public.replace_modifier_recipe(
  p_modifier_id uuid,
  p_recipe jsonb default '[]'::jsonb
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_component jsonb;
  v_inventory_item_id uuid;
  v_quantity numeric;
  v_wastage numeric;
begin
  if not public.has_permission('menu.manage') then
    raise exception 'Permission denied';
  end if;

  if not exists (select 1 from public.modifiers where id = p_modifier_id) then
    raise exception 'Modifier not found';
  end if;

  if jsonb_typeof(coalesce(p_recipe,'[]'::jsonb)) <> 'array' then
    raise exception 'Modifier recipe must be an array';
  end if;

  delete from public.modifier_recipe_components
  where modifier_id = p_modifier_id;

  for v_component in
    select value from jsonb_array_elements(coalesce(p_recipe,'[]'::jsonb))
  loop
    v_inventory_item_id := nullif(v_component ->> 'inventory_item_id','')::uuid;
    v_quantity := nullif(v_component ->> 'quantity_base_uom','')::numeric;
    v_wastage := coalesce(nullif(v_component ->> 'wastage_percent','')::numeric,0);

    if v_inventory_item_id is null then
      raise exception 'Modifier recipe inventory item is required';
    end if;
    if v_quantity is null or v_quantity <= 0 then
      raise exception 'Modifier recipe quantity must be greater than zero';
    end if;
    if v_wastage < 0 then
      raise exception 'Modifier recipe wastage cannot be negative';
    end if;

    if not exists (
      select 1 from public.inventory_items
      where id = v_inventory_item_id
        and is_active = true
        and track_inventory = true
    ) then
      raise exception 'Modifier recipe inventory item is unavailable';
    end if;

    insert into public.modifier_recipe_components(
      modifier_id,inventory_item_id,quantity_base_uom,wastage_percent
    )
    values (
      p_modifier_id,v_inventory_item_id,v_quantity,v_wastage
    );
  end loop;
end;
$$;

revoke all on function public.replace_modifier_recipe(uuid,jsonb)
from public, anon, authenticated;

create or replace function public.create_modifier(
  p_modifier_group_id uuid,
  p_name text,
  p_price_delta numeric default 0,
  p_recipe jsonb default '[]'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_modifier_id uuid;
begin
  if not public.has_permission('menu.manage') then
    raise exception 'Permission denied';
  end if;

  if not exists (
    select 1 from public.modifier_groups
    where id = p_modifier_group_id and is_active = true
  ) then
    raise exception 'Modifier group not found or inactive';
  end if;

  if nullif(btrim(coalesce(p_name,'')), '') is null then
    raise exception 'Modifier name is required';
  end if;

  insert into public.modifiers(
    modifier_group_id,name,price_delta,is_active,sort_order
  )
  values (
    p_modifier_group_id,
    btrim(p_name),
    round(coalesce(p_price_delta,0),2),
    true,
    coalesce(
      (
        select max(sort_order) + 1
        from public.modifiers
        where modifier_group_id = p_modifier_group_id
      ),
      0
    )
  )
  returning id into v_modifier_id;

  perform public.replace_modifier_recipe(
    v_modifier_id,
    coalesce(p_recipe,'[]'::jsonb)
  );

  return v_modifier_id;
end;
$$;

revoke all on function public.create_modifier(uuid,text,numeric,jsonb)
from public, anon;
grant execute on function public.create_modifier(uuid,text,numeric,jsonb)
to authenticated;

create or replace function public.update_modifier(
  p_modifier_id uuid,
  p_name text,
  p_price_delta numeric,
  p_is_active boolean,
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

  if nullif(btrim(coalesce(p_name,'')), '') is null then
    raise exception 'Modifier name is required';
  end if;

  update public.modifiers
  set
    name = btrim(p_name),
    price_delta = round(coalesce(p_price_delta,0),2),
    is_active = coalesce(p_is_active,true)
  where id = p_modifier_id;

  if not found then
    raise exception 'Modifier not found';
  end if;

  perform public.replace_modifier_recipe(
    p_modifier_id,
    coalesce(p_recipe,'[]'::jsonb)
  );
end;
$$;

revoke all on function public.update_modifier(
  uuid,text,numeric,boolean,jsonb
) from public, anon;
grant execute on function public.update_modifier(
  uuid,text,numeric,boolean,jsonb
) to authenticated;

create or replace view public.v_menu_modifier_management
with (security_invoker = true)
as
select
  mig.menu_item_id,
  mg.id as modifier_group_id,
  mg.name as group_name,
  mg.min_selections,
  mg.max_selections,
  mg.is_required,
  mg.is_active as group_active,
  mg.sort_order as group_sort_order,
  m.id as modifier_id,
  m.name as modifier_name,
  m.price_delta,
  m.is_active as modifier_active,
  m.sort_order as modifier_sort_order,
  (
    select count(*)
    from public.modifier_recipe_components mrc
    where mrc.modifier_id = m.id
  )::integer as recipe_component_count
from public.menu_item_modifier_groups mig
join public.modifier_groups mg
  on mg.id = mig.modifier_group_id
left join public.modifiers m
  on m.modifier_group_id = mg.id
order by mig.menu_item_id, mig.sort_order, mg.sort_order, m.sort_order, m.name;

grant select on public.v_menu_modifier_management to authenticated;
revoke all on public.v_menu_modifier_management from anon;
