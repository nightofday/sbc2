-- MOD-01 and S-07: complete modifier management.
--
--   * A group name had to be unique across the whole menu, so a second
--     product could not have its own "Size" or "Add-ons" group.
--   * A group could only be created for one product; there was no way to use
--     the same group on another product or to take it off again.
--   * Options could not be reordered.
--   * A required group whose options were all switched off is not shown at
--     the till, yet it still blocked checkout.

alter table public.modifier_groups
  drop constraint modifier_groups_name_key;

-- Uses an existing group on another product. The group and its options are
-- shared: editing them changes every product that uses the group.
create function public.attach_modifier_group(
  p_menu_item_id uuid,
  p_modifier_group_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.has_permission('menu.manage') then
    raise exception 'Permission denied';
  end if;

  if not exists (
    select 1 from public.menu_items mi where mi.id = p_menu_item_id
  ) then
    raise exception 'Menu item not found';
  end if;

  if not exists (
    select 1 from public.modifier_groups mg where mg.id = p_modifier_group_id
  ) then
    raise exception 'Modifier group not found';
  end if;

  insert into public.menu_item_modifier_groups(
    menu_item_id, modifier_group_id, sort_order
  )
  values (
    p_menu_item_id,
    p_modifier_group_id,
    coalesce(
      (
        select max(mig.sort_order) + 1
        from public.menu_item_modifier_groups mig
        where mig.menu_item_id = p_menu_item_id
      ),
      0
    )
  )
  on conflict (menu_item_id, modifier_group_id) do nothing;
end;
$$;

-- Takes a group off one product. The group, its options and every past
-- order line that recorded them are untouched.
create function public.detach_modifier_group(
  p_menu_item_id uuid,
  p_modifier_group_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.has_permission('menu.manage') then
    raise exception 'Permission denied';
  end if;

  delete from public.menu_item_modifier_groups mig
  where mig.menu_item_id = p_menu_item_id
    and mig.modifier_group_id = p_modifier_group_id;

  if not found then
    raise exception 'This product does not use that modifier group';
  end if;
end;
$$;

-- Sets the order options are offered in to the order of the IDs given.
create function public.reorder_modifiers(
  p_modifier_group_id uuid,
  p_modifier_ids uuid[]
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.has_permission('menu.manage') then
    raise exception 'Permission denied';
  end if;

  update public.modifiers m
  set sort_order = o.position::integer
  from unnest(p_modifier_ids) with ordinality as o(id, position)
  where m.id = o.id
    and m.modifier_group_id = p_modifier_group_id;
end;
$$;

revoke all on function public.attach_modifier_group(uuid,uuid)
from public, anon;
grant execute on function public.attach_modifier_group(uuid,uuid)
to authenticated;

revoke all on function public.detach_modifier_group(uuid,uuid)
from public, anon;
grant execute on function public.detach_modifier_group(uuid,uuid)
to authenticated;

revoke all on function public.reorder_modifiers(uuid,uuid[])
from public, anon;
grant execute on function public.reorder_modifiers(uuid,uuid[])
to authenticated;

-- Every group with the products that use it, for choosing an existing one.
create view public.v_modifier_group_library
with (security_invoker = true)
as
select
  mg.id as modifier_group_id,
  mg.name as group_name,
  mg.min_selections,
  mg.max_selections,
  mg.is_required,
  mg.is_active,
  (
    select count(*)
    from public.modifiers m
    where m.modifier_group_id = mg.id
      and m.is_active = true
  )::integer as active_option_count,
  (
    select count(*)
    from public.menu_item_modifier_groups mig
    where mig.modifier_group_id = mg.id
  )::integer as product_count,
  coalesce(
    (
      select string_agg(mi.name, ', ' order by mi.name)
      from public.menu_item_modifier_groups mig
      join public.menu_items mi on mi.id = mig.menu_item_id
      where mig.modifier_group_id = mg.id
    ),
    ''
  ) as product_names
from public.modifier_groups mg;

grant select on public.v_modifier_group_library to authenticated;
revoke all on public.v_modifier_group_library from anon;

-- The management view also reports how many products share each group.
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
  )::integer as recipe_component_count,
  (
    select count(*)
    from public.menu_item_modifier_groups shared
    where shared.modifier_group_id = mg.id
  )::integer as group_product_count
from public.menu_item_modifier_groups mig
join public.modifier_groups mg
  on mg.id = mig.modifier_group_id
left join public.modifiers m
  on m.modifier_group_id = mg.id
order by mig.menu_item_id, mig.sort_order, mg.sort_order, m.sort_order, m.name;

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
      -- A group whose options are all switched off is not shown at the till,
      -- so it cannot be allowed to block the sale.
      and exists (
        select 1
        from public.modifiers available
        where available.modifier_group_id = mg.id
          and available.is_active = true
      )
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
