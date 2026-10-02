-- S-01: use the café's business date instead of the database server's UTC date.
--
-- `current_date` is evaluated in UTC on Supabase. Asia/Manila is UTC+8, so
-- from midnight to 08:00 local time the server date is still the previous
-- day. That shifted which lots counted as expired and which date a new
-- expense or supplier bill received by default. Dashboard and report views
-- already convert timestamps to Asia/Manila; this aligns everything else.
--
-- Every object below is the current definition with `current_date` replaced.
-- No other behavior changes.

create or replace function public.business_today()
returns date
language sql
stable
security definer
set search_path = ''
as $$
  select (
    now() at time zone coalesce(
      (select bp.timezone from public.business_profile bp where bp.id = 1),
      'Asia/Manila'
    )
  )::date;
$$;

revoke all on function public.business_today() from public, anon;
grant execute on function public.business_today() to authenticated;

alter table public.expenses
  alter column expense_date set default public.business_today();

alter table public.supplier_bills
  alter column invoice_date set default public.business_today();

-- Usable and expired quantities.
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
  coalesce(movement_totals.current_quantity, 0)::numeric(14,4)
    as current_quantity,
  coalesce(lot_totals.usable_quantity, 0)::numeric(14,4)
    as usable_quantity,
  coalesce(lot_totals.expired_quantity, 0)::numeric(14,4)
    as expired_quantity
from public.inventory_items ii
join public.units_of_measure u on u.id = ii.base_uom_id
left join (
  select
    sm.inventory_item_id,
    sum(sm.quantity_delta)::numeric(14,4) as current_quantity
  from public.stock_movements sm
  group by sm.inventory_item_id
) movement_totals on movement_totals.inventory_item_id = ii.id
left join (
  select
    il.inventory_item_id,
    coalesce(
      sum(il.remaining_quantity) filter (
        where il.status = 'AVAILABLE'
          and il.remaining_quantity > 0
          and (
            il.expiration_date is null
            or il.expiration_date >= (select public.business_today())
          )
      ),
      0
    )::numeric(14,4) as usable_quantity,
    coalesce(
      sum(il.remaining_quantity) filter (
        where il.status = 'AVAILABLE'
          and il.remaining_quantity > 0
          and il.expiration_date < (select public.business_today())
      ),
      0
    )::numeric(14,4) as expired_quantity
  from public.inventory_lots il
  group by il.inventory_item_id
) lot_totals on lot_totals.inventory_item_id = ii.id
where ii.is_active = true;

create or replace view public.v_inventory_catalog
with (security_invoker = true)
as
select
  ii.id as inventory_item_id,
  ii.sku,
  ii.name,
  ii.category_id,
  ic.name as category_name,
  ii.base_uom_id,
  u.code as base_uom_code,
  ii.track_inventory,
  ii.track_expiry,
  ii.reorder_level,
  ii.reorder_target,
  coalesce(vs.current_quantity, 0)::numeric(14,4) as current_quantity,
  (
    select min(il.expiration_date)
    from public.inventory_lots il
    where il.inventory_item_id = ii.id
      and il.remaining_quantity > 0
      and il.status = 'AVAILABLE'
      and il.expiration_date >= (select public.business_today())
  ) as next_expiration_date,
  coalesce(vs.usable_quantity, 0)::numeric(14,4) as usable_quantity,
  coalesce(vs.expired_quantity, 0)::numeric(14,4) as expired_quantity
from public.inventory_items ii
join public.units_of_measure u on u.id = ii.base_uom_id
left join public.inventory_categories ic on ic.id = ii.category_id
left join public.v_inventory_stock vs on vs.inventory_item_id = ii.id
where ii.is_active = true;

create or replace view public.v_expiring_inventory_lots
with (security_invoker = true)
as
select
  il.id as lot_id,
  ii.id as inventory_item_id,
  ii.name as item_name,
  il.lot_code,
  il.expiration_date,
  il.remaining_quantity,
  u.code as uom_code,
  (il.expiration_date - (select public.business_today())) as days_until_expiry
from public.inventory_lots il
join public.inventory_items ii on ii.id = il.inventory_item_id
join public.units_of_measure u on u.id = ii.base_uom_id
where il.remaining_quantity > 0
  and il.status = 'AVAILABLE'
  and il.expiration_date is not null;

-- Sale consumption: first-expire-first-out over lots usable today.
create or replace function public.consume_inventory_fefo(
  p_inventory_item_id uuid,
  p_quantity numeric,
  p_order_id uuid,
  p_order_item_id uuid,
  p_recorded_by uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_item public.inventory_items%rowtype;
  v_lot public.inventory_lots%rowtype;
  v_remaining numeric(14,4);
  v_take numeric(14,4);
begin
  if p_quantity <= 0 then
    raise exception 'Consumption quantity must be greater than zero';
  end if;

  select * into v_item
  from public.inventory_items
  where id = p_inventory_item_id
  for update;

  if not found then
    raise exception 'Inventory item not found';
  end if;

  if not v_item.track_inventory then
    return;
  end if;

  v_remaining := p_quantity;

  for v_lot in
    select *
    from public.inventory_lots
    where inventory_item_id = p_inventory_item_id
      and remaining_quantity > 0
      and status = 'AVAILABLE'
      and (expiration_date is null or expiration_date >= (select public.business_today()))
    order by expiration_date asc nulls last, received_at asc
    for update
  loop
    exit when v_remaining <= 0;

    v_take := least(v_remaining, v_lot.remaining_quantity);

    update public.inventory_lots
    set
      remaining_quantity = remaining_quantity - v_take,
      status = case
        when remaining_quantity - v_take <= 0 then 'DEPLETED'
        else status
      end
    where id = v_lot.id;

    insert into public.stock_movements (
      inventory_item_id,
      inventory_lot_id,
      movement_type,
      quantity_delta,
      unit_cost_base,
      reference_type,
      reference_id,
      order_id,
      order_item_id,
      recorded_by
    )
    values (
      p_inventory_item_id,
      v_lot.id,
      'SALE_CONSUMPTION',
      -v_take,
      v_lot.unit_cost_base,
      'ORDER',
      p_order_id,
      p_order_id,
      p_order_item_id,
      p_recorded_by
    );

    v_remaining := v_remaining - v_take;
  end loop;

  if v_remaining > 0 then
    if v_item.allow_negative_stock then
      insert into public.stock_movements (
        inventory_item_id,
        movement_type,
        quantity_delta,
        unit_cost_base,
        reference_type,
        reference_id,
        order_id,
        order_item_id,
        recorded_by,
        reason
      )
      values (
        p_inventory_item_id,
        'SALE_CONSUMPTION',
        -v_remaining,
        0,
        'ORDER',
        p_order_id,
        p_order_id,
        p_order_item_id,
        p_recorded_by,
        'Negative stock allowed: insufficient usable lot quantity'
      );
    else
      raise exception 'Insufficient usable stock for inventory item %',
        p_inventory_item_id;
    end if;
  end if;
end;
$$;

-- Supply release.
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
        and (expiration_date is null or expiration_date >= (select public.business_today()))
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

-- Refund restock.
create or replace function public.approve_refund_item_restock(
  p_refund_item_id uuid,
  p_notes text default null
)
returns public.refund_items
language plpgsql
security definer
set search_path = public
as $$
declare
  v_refund_item public.refund_items%rowtype;
  v_refund public.refunds%rowtype;
  v_order_item public.order_items%rowtype;
  v_variant public.menu_variants%rowtype;
  v_sale_movement public.stock_movements%rowtype;
  v_lot public.inventory_lots%rowtype;
  v_already_restored numeric(14,4);
  v_capacity numeric(14,4);
  v_take numeric(14,4);
  v_remaining numeric(14,4);
begin
  if not public.has_permission('inventory.adjust')
     or not public.has_permission('orders.refund') then
    raise exception 'Permission denied';
  end if;

  select * into v_refund_item
  from public.refund_items
  where id = p_refund_item_id
  for update;

  if not found then
    raise exception 'Refund item not found';
  end if;

  if v_refund_item.restock_approved then
    raise exception 'Refund item was already restocked';
  end if;

  select * into v_refund
  from public.refunds
  where id = v_refund_item.refund_id;

  if not found or v_refund.status <> 'COMPLETED' then
    raise exception 'Only completed refunds can be restocked';
  end if;

  select * into v_order_item
  from public.order_items
  where id = v_refund_item.order_item_id;

  if not found then
    raise exception 'Original order item not found';
  end if;

  select * into v_variant
  from public.menu_variants
  where id = v_order_item.menu_variant_id;

  if not found
     or not v_variant.track_finished_inventory
     or v_variant.finished_inventory_item_id is null then
    raise exception
      'Only finished-goods variants can be restocked automatically';
  end if;

  v_remaining := v_refund_item.quantity;

  for v_sale_movement in
    select sm.*
    from public.stock_movements sm
    where sm.order_item_id = v_order_item.id
      and sm.inventory_item_id = v_variant.finished_inventory_item_id
      and sm.movement_type = 'SALE_CONSUMPTION'
      and sm.quantity_delta < 0
      and sm.inventory_lot_id is not null
    order by sm.created_at, sm.id
  loop
    exit when v_remaining <= 0;

    select coalesce(sum(sm.quantity_delta),0)
    into v_already_restored
    from public.stock_movements sm
    where sm.order_item_id = v_order_item.id
      and sm.inventory_lot_id = v_sale_movement.inventory_lot_id
      and sm.movement_type = 'REFUND_RESTOCK'
      and sm.quantity_delta > 0;

    v_capacity :=
      abs(v_sale_movement.quantity_delta) - coalesce(v_already_restored,0);

    if v_capacity <= 0 then
      continue;
    end if;

    v_take := least(v_remaining, v_capacity);

    select * into v_lot
    from public.inventory_lots
    where id = v_sale_movement.inventory_lot_id
    for update;

    if not found then
      raise exception 'Original inventory lot no longer exists';
    end if;

    if v_lot.status not in ('AVAILABLE','DEPLETED') then
      raise exception
        'Returned stock cannot be restored to a % inventory lot',
        lower(v_lot.status);
    end if;

    if v_lot.expiration_date is not null
       and v_lot.expiration_date < (select public.business_today()) then
      raise exception
        'Returned stock cannot be restored to an expired inventory lot';
    end if;

    update public.inventory_lots
    set remaining_quantity = remaining_quantity + v_take,
        status = 'AVAILABLE'
    where id = v_lot.id;

    insert into public.stock_movements(
      inventory_item_id,inventory_lot_id,movement_type,quantity_delta,
      unit_cost_base,reference_type,reference_id,order_id,order_item_id,
      reason,recorded_by
    )
    values (
      v_variant.finished_inventory_item_id,v_lot.id,'REFUND_RESTOCK',
      v_take,v_sale_movement.unit_cost_base,'REFUND_ITEM',
      v_refund_item.id,v_refund.order_id,v_order_item.id,
      coalesce(nullif(btrim(coalesce(p_notes,'')), ''),'Approved refund restock'),
      auth.uid()
    );

    v_remaining := v_remaining - v_take;
  end loop;

  if v_remaining > 0 then
    raise exception
      'Unable to restock the full refunded quantity from original inventory lots';
  end if;

  update public.refund_items
  set restock_approved = true,
      notes = concat_ws(E'\n',notes,nullif(btrim(coalesce(p_notes,'')), ''))
  where id = p_refund_item_id
  returning * into v_refund_item;

  insert into public.audit_logs(
    actor_user_id,action_code,entity_type,entity_id,new_data
  )
  values (
    auth.uid(),'REFUND_RESTOCK_APPROVED','refund_item',
    p_refund_item_id::text,
    jsonb_build_object(
      'refund_id',v_refund_item.refund_id,
      'order_item_id',v_refund_item.order_item_id,
      'quantity',v_refund_item.quantity
    )
  );

  return v_refund_item;
end;
$$;

-- Expense date default. The parameter default becomes null and is resolved
-- inside the function, so the signature and its grants are unchanged.
create or replace function public.create_expense(
  p_expense_category_id uuid,
  p_description text,
  p_amount numeric,
  p_expense_date date default null,
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
    coalesce(p_expense_date, (select public.business_today())),
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

-- Supplier bill created with a receipt.
create or replace function public.create_and_post_goods_receipt(
  p_supplier_id uuid,
  p_items jsonb,
  p_purchase_order_id uuid default null,
  p_supplier_invoice_number text default null,
  p_supplier_invoice_date date default null,
  p_notes text default null,
  p_create_supplier_bill boolean default true,
  p_due_date date default null
)
returns public.goods_receipts
language plpgsql
security definer
set search_path = public
as $$
declare
  v_receipt public.goods_receipts%rowtype;
  v_line jsonb;
  v_inventory_item_id uuid;
  v_purchase_uom_id uuid;
  v_po_item_id uuid;
  v_purchase_qty numeric;
  v_base_per_unit numeric;
  v_base_qty numeric;
  v_unit_cost_purchase numeric;
  v_unit_cost_base numeric;
  v_expiration date;
  v_lot_code text;
  v_total numeric(14,2) := 0;
begin
  if not public.has_permission('purchases.receive') then
    raise exception 'Permission denied';
  end if;

  if not exists (
    select 1 from public.suppliers
    where id = p_supplier_id and is_active = true
  ) then
    raise exception 'Supplier is unavailable';
  end if;

  if p_purchase_order_id is not null and not exists (
    select 1
    from public.purchase_orders
    where id = p_purchase_order_id
      and supplier_id = p_supplier_id
      and status in ('APPROVED','SENT','PARTIALLY_RECEIVED')
  ) then
    raise exception 'Purchase order is unavailable for receiving';
  end if;

  if jsonb_typeof(coalesce(p_items,'[]'::jsonb)) <> 'array'
     or jsonb_array_length(coalesce(p_items,'[]'::jsonb)) = 0 then
    raise exception 'At least one received item is required';
  end if;

  insert into public.goods_receipts(
    supplier_id,purchase_order_id,supplier_invoice_number,
    supplier_invoice_date,received_by,status,notes
  )
  values (
    p_supplier_id,p_purchase_order_id,
    nullif(btrim(coalesce(p_supplier_invoice_number,'')), ''),
    p_supplier_invoice_date,auth.uid(),'DRAFT',
    nullif(btrim(coalesce(p_notes,'')), '')
  )
  returning * into v_receipt;

  for v_line in select value from jsonb_array_elements(p_items)
  loop
    v_inventory_item_id := nullif(v_line ->> 'inventory_item_id','')::uuid;
    v_purchase_uom_id := nullif(v_line ->> 'purchase_uom_id','')::uuid;
    v_po_item_id := nullif(v_line ->> 'purchase_order_item_id','')::uuid;
    v_purchase_qty := nullif(v_line ->> 'purchase_quantity','')::numeric;
    v_base_per_unit := nullif(v_line ->> 'base_quantity_per_purchase_unit','')::numeric;
    v_unit_cost_purchase := nullif(v_line ->> 'unit_cost_purchase_uom','')::numeric;
    v_expiration := nullif(v_line ->> 'expiration_date','')::date;
    v_lot_code := nullif(btrim(coalesce(v_line ->> 'lot_code','')), '');

    if v_purchase_qty is null or v_purchase_qty <= 0
       or v_base_per_unit is null or v_base_per_unit <= 0
       or v_unit_cost_purchase is null or v_unit_cost_purchase < 0 then
      raise exception 'Invalid received item values';
    end if;

    if not exists (
      select 1 from public.inventory_items
      where id = v_inventory_item_id and is_active = true
    ) then
      raise exception 'Inventory item is unavailable';
    end if;

    v_base_qty := v_purchase_qty * v_base_per_unit;
    v_unit_cost_base := case
      when v_base_per_unit = 0 then 0
      else v_unit_cost_purchase / v_base_per_unit
    end;

    insert into public.goods_receipt_items(
      goods_receipt_id,purchase_order_item_id,inventory_item_id,purchase_uom_id,
      purchase_quantity,base_quantity_per_purchase_unit,base_quantity,
      unit_cost_purchase_uom,unit_cost_base,lot_code,expiration_date
    )
    values (
      v_receipt.id,v_po_item_id,v_inventory_item_id,v_purchase_uom_id,
      v_purchase_qty,v_base_per_unit,v_base_qty,v_unit_cost_purchase,
      v_unit_cost_base,v_lot_code,v_expiration
    );

    v_total := v_total + round(v_purchase_qty * v_unit_cost_purchase,2);
  end loop;

  perform public.post_goods_receipt(v_receipt.id);

  if coalesce(p_create_supplier_bill,true) then
    insert into public.supplier_bills(
      supplier_id,goods_receipt_id,supplier_invoice_number,invoice_date,
      due_date,amount,status,created_by,notes
    )
    values (
      p_supplier_id,v_receipt.id,
      nullif(btrim(coalesce(p_supplier_invoice_number,'')), ''),
      coalesce(p_supplier_invoice_date,(select public.business_today())),p_due_date,v_total,
      case when v_total = 0 then 'PAID' else 'UNPAID' end,
      auth.uid(),'Created from posted goods receipt'
    );
  end if;

  select * into v_receipt
  from public.goods_receipts
  where id = v_receipt.id;

  return v_receipt;
end;
$$;
