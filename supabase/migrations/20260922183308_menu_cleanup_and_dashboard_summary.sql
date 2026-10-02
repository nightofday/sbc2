-- Development menu cleanup and dashboard reporting summary.

update public.menu_items mi
set name = 'Coca-Cola'
from public.menu_variants mv
where mv.menu_item_id = mi.id
  and mv.sku = 'PRD-008';

update public.menu_variants mv
set
  name = '330 ml Can',
  track_finished_inventory = true,
  finished_inventory_item_id = ii.id
from public.inventory_items ii
where mv.sku = 'PRD-008'
  and ii.sku = 'INV-002'
  and not exists (
    select 1 from public.variant_recipe_components rc
    where rc.menu_variant_id = mv.id
  );

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
    when exists (
      select 1
      from public.variant_recipe_components rc
      where rc.menu_variant_id = mv.id
    ) then 'RECIPE'
    else 'UNTRACKED'
  end as inventory_tracking_mode,
  (
    select count(*)
    from public.variant_recipe_components rc
    where rc.menu_variant_id = mv.id
  )::integer as recipe_component_count
from public.menu_items mi
left join public.menu_categories mc on mc.id = mi.category_id
join public.menu_variants mv on mv.menu_item_id = mi.id
left join public.inventory_items fii on fii.id = mv.finished_inventory_item_id;

grant select on public.v_menu_management to authenticated;
revoke all on public.v_menu_management from anon;

create or replace function public.get_dashboard_summary()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_today date := (now() at time zone 'Asia/Manila')::date;
  v_can_manage boolean := public.has_permission('reports.view')
                          or public.has_permission('finance.view')
                          or public.has_permission('orders.manage_all');
  v_sales numeric(14,2) := 0;
  v_refunds numeric(14,2) := 0;
  v_orders bigint := 0;
  v_open_orders bigint := 0;
  v_expenses numeric(14,2) := 0;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  select coalesce(sum(o.total_amount),0), count(*)
  into v_sales, v_orders
  from public.orders o
  where o.completed_at is not null
    and (o.completed_at at time zone 'Asia/Manila')::date = v_today
    and o.status in ('COMPLETED','PARTIALLY_REFUNDED','REFUNDED')
    and (v_can_manage or o.created_by_user_id = auth.uid());

  select coalesce(sum(r.total_amount),0)
  into v_refunds
  from public.refunds r
  join public.orders o on o.id = r.order_id
  where r.status = 'COMPLETED'
    and (r.created_at at time zone 'Asia/Manila')::date = v_today
    and (v_can_manage or o.created_by_user_id = auth.uid());

  select count(*)
  into v_open_orders
  from public.orders o
  where (o.created_at at time zone 'Asia/Manila')::date = v_today
    and o.status in ('OPEN','PENDING_PAYMENT')
    and (v_can_manage or o.created_by_user_id = auth.uid());

  if v_can_manage then
    select coalesce(sum(e.amount),0)
    into v_expenses
    from public.expenses e
    where e.expense_date = v_today
      and e.status = 'POSTED';
  end if;

  return jsonb_build_object(
    'report_date', v_today,
    'gross_sales', round(v_sales,2),
    'refunds', round(v_refunds,2),
    'net_sales', round(v_sales - v_refunds,2),
    'completed_orders', v_orders,
    'open_orders', v_open_orders,
    'average_order', case when v_orders = 0 then 0 else round((v_sales - v_refunds) / v_orders,2) end,
    'expenses', case when v_can_manage then round(v_expenses,2) else null end,
    'net_after_expenses', case when v_can_manage then round((v_sales - v_refunds) - v_expenses,2) else null end,
    'business_scope', v_can_manage
  );
end;
$$;

revoke all on function public.get_dashboard_summary() from public, anon;
grant execute on function public.get_dashboard_summary() to authenticated;
