-- Menu item, variant, and recipe management RPCs for Admin/Manager Flutter UI.

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
  v_component jsonb;
  v_inventory_item_id uuid;
  v_quantity numeric;
  v_wastage numeric;
begin
  if not public.has_permission('menu.manage') then
    raise exception 'Permission denied';
  end if;

  if not exists (select 1 from public.menu_variants where id = p_variant_id) then
    raise exception 'Menu variant not found';
  end if;

  v_mode := upper(btrim(coalesce(p_inventory_mode,'UNTRACKED')));

  if v_mode not in ('UNTRACKED','FINISHED_GOOD','RECIPE') then
    raise exception 'Invalid inventory tracking mode';
  end if;

  if v_mode = 'FINISHED_GOOD' then
    if p_finished_inventory_item_id is null then
      raise exception 'Finished inventory item is required';
    end if;

    if not exists (
      select 1 from public.inventory_items
      where id = p_finished_inventory_item_id
        and is_active = true
        and track_inventory = true
    ) then
      raise exception 'Finished inventory item is unavailable';
    end if;

    delete from public.variant_recipe_components
    where menu_variant_id = p_variant_id;

    update public.menu_variants
    set track_finished_inventory = true,
        finished_inventory_item_id = p_finished_inventory_item_id
    where id = p_variant_id;

    return;
  end if;

  update public.menu_variants
  set track_finished_inventory = false,
      finished_inventory_item_id = null
  where id = p_variant_id;

  delete from public.variant_recipe_components
  where menu_variant_id = p_variant_id;

  if v_mode = 'UNTRACKED' then
    return;
  end if;

  if jsonb_typeof(coalesce(p_recipe,'[]'::jsonb)) <> 'array'
     or jsonb_array_length(coalesce(p_recipe,'[]'::jsonb)) = 0 then
    raise exception 'At least one recipe component is required';
  end if;

  for v_component in select value from jsonb_array_elements(p_recipe)
  loop
    v_inventory_item_id := nullif(v_component ->> 'inventory_item_id','')::uuid;
    v_quantity := nullif(v_component ->> 'quantity_base_uom','')::numeric;
    v_wastage := coalesce(nullif(v_component ->> 'wastage_percent','')::numeric,0);

    if v_inventory_item_id is null then
      raise exception 'Recipe inventory item is required';
    end if;
    if v_quantity is null or v_quantity <= 0 then
      raise exception 'Recipe quantity must be greater than zero';
    end if;
    if v_wastage < 0 then
      raise exception 'Recipe wastage cannot be negative';
    end if;

    if not exists (
      select 1 from public.inventory_items
      where id = v_inventory_item_id
        and is_active = true
        and track_inventory = true
    ) then
      raise exception 'Recipe inventory item is unavailable';
    end if;

    insert into public.variant_recipe_components(
      menu_variant_id, inventory_item_id, quantity_base_uom, wastage_percent
    )
    values (p_variant_id, v_inventory_item_id, v_quantity, v_wastage);
  end loop;
end;
$$;

revoke all on function public.apply_variant_inventory_configuration(
  uuid,text,uuid,jsonb
) from public, anon, authenticated;

create or replace function public.create_menu_item_with_variant(
  p_item_name text,
  p_category_id uuid,
  p_variant_name text,
  p_sku text,
  p_price numeric,
  p_inventory_mode text default 'UNTRACKED',
  p_finished_inventory_item_id uuid default null,
  p_recipe jsonb default '[]'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_item_id uuid;
  v_variant_id uuid;
begin
  if not public.has_permission('menu.manage') then
    raise exception 'Permission denied';
  end if;
  if nullif(btrim(coalesce(p_item_name,'')), '') is null then
    raise exception 'Menu item name is required';
  end if;
  if nullif(btrim(coalesce(p_variant_name,'')), '') is null then
    raise exception 'Variant name is required';
  end if;
  if p_price is null or p_price < 0 then
    raise exception 'Price cannot be negative';
  end if;
  if not exists (
    select 1 from public.menu_categories
    where id = p_category_id and is_active = true
  ) then
    raise exception 'Invalid menu category';
  end if;

  insert into public.menu_items(name, category_id, is_active)
  values (btrim(p_item_name), p_category_id, true)
  returning id into v_item_id;

  insert into public.menu_variants(
    menu_item_id, sku, name, price, is_default, is_active, track_finished_inventory
  )
  values (
    v_item_id, nullif(btrim(coalesce(p_sku,'')), ''), btrim(p_variant_name),
    round(p_price,2), true, true, false
  )
  returning id into v_variant_id;

  perform public.apply_variant_inventory_configuration(
    v_variant_id, p_inventory_mode, p_finished_inventory_item_id, p_recipe
  );

  return v_variant_id;
end;
$$;

revoke all on function public.create_menu_item_with_variant(
  text,uuid,text,text,numeric,text,uuid,jsonb
) from public, anon;
grant execute on function public.create_menu_item_with_variant(
  text,uuid,text,text,numeric,text,uuid,jsonb
) to authenticated;

create or replace function public.add_menu_variant(
  p_menu_item_id uuid,
  p_variant_name text,
  p_sku text,
  p_price numeric,
  p_inventory_mode text default 'UNTRACKED',
  p_finished_inventory_item_id uuid default null,
  p_recipe jsonb default '[]'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_variant_id uuid;
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
  if nullif(btrim(coalesce(p_variant_name,'')), '') is null then
    raise exception 'Variant name is required';
  end if;
  if p_price is null or p_price < 0 then
    raise exception 'Price cannot be negative';
  end if;

  insert into public.menu_variants(
    menu_item_id, sku, name, price, is_default, is_active, track_finished_inventory
  )
  values (
    p_menu_item_id, nullif(btrim(coalesce(p_sku,'')), ''), btrim(p_variant_name),
    round(p_price,2), false, true, false
  )
  returning id into v_variant_id;

  perform public.apply_variant_inventory_configuration(
    v_variant_id, p_inventory_mode, p_finished_inventory_item_id, p_recipe
  );

  return v_variant_id;
end;
$$;

revoke all on function public.add_menu_variant(
  uuid,text,text,numeric,text,uuid,jsonb
) from public, anon;
grant execute on function public.add_menu_variant(
  uuid,text,text,numeric,text,uuid,jsonb
) to authenticated;

create or replace function public.update_menu_variant(
  p_variant_id uuid,
  p_item_name text,
  p_category_id uuid,
  p_variant_name text,
  p_sku text,
  p_price numeric,
  p_is_active boolean,
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
  v_item_id uuid;
begin
  if not public.has_permission('menu.manage') then
    raise exception 'Permission denied';
  end if;

  select menu_item_id into v_item_id
  from public.menu_variants
  where id = p_variant_id
  for update;

  if not found then
    raise exception 'Menu variant not found';
  end if;
  if nullif(btrim(coalesce(p_item_name,'')), '') is null
     or nullif(btrim(coalesce(p_variant_name,'')), '') is null then
    raise exception 'Item and variant names are required';
  end if;
  if p_price is null or p_price < 0 then
    raise exception 'Price cannot be negative';
  end if;
  if not exists (
    select 1 from public.menu_categories
    where id = p_category_id and is_active = true
  ) then
    raise exception 'Invalid menu category';
  end if;

  update public.menu_items
  set name = btrim(p_item_name), category_id = p_category_id
  where id = v_item_id;

  update public.menu_variants
  set sku = nullif(btrim(coalesce(p_sku,'')), ''),
      name = btrim(p_variant_name),
      price = round(p_price,2),
      is_active = coalesce(p_is_active,true)
  where id = p_variant_id;

  perform public.apply_variant_inventory_configuration(
    p_variant_id, p_inventory_mode, p_finished_inventory_item_id, p_recipe
  );
end;
$$;

revoke all on function public.update_menu_variant(
  uuid,text,uuid,text,text,numeric,boolean,text,uuid,jsonb
) from public, anon;
grant execute on function public.update_menu_variant(
  uuid,text,uuid,text,text,numeric,boolean,text,uuid,jsonb
) to authenticated;
