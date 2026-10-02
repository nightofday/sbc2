-- Prevent purchase-order receiving from exceeding ordered quantities or mismatching lines.

create unique index if not exists uq_goods_receipt_po_item_per_receipt
on public.goods_receipt_items(goods_receipt_id, purchase_order_item_id)
where purchase_order_item_id is not null;

create or replace function public.guard_goods_receipt_po_quantity()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_po_item public.purchase_order_items%rowtype;
  v_receipt public.goods_receipts%rowtype;
  v_expected_base numeric(14,4);
  v_already_posted numeric(14,4);
begin
  if new.purchase_order_item_id is null then
    return new;
  end if;

  select * into v_po_item
  from public.purchase_order_items
  where id = new.purchase_order_item_id;

  if not found then
    raise exception 'Purchase order item not found';
  end if;

  select * into v_receipt
  from public.goods_receipts
  where id = new.goods_receipt_id;

  if not found then
    raise exception 'Goods receipt not found';
  end if;

  if v_receipt.purchase_order_id is null
     or v_receipt.purchase_order_id <> v_po_item.purchase_order_id then
    raise exception 'Receipt and purchase order item do not match';
  end if;

  if new.inventory_item_id <> v_po_item.inventory_item_id then
    raise exception 'Received inventory item does not match purchase order item';
  end if;

  if new.purchase_uom_id <> v_po_item.purchase_uom_id then
    raise exception 'Received purchase unit does not match purchase order item';
  end if;

  if round(new.base_quantity_per_purchase_unit,4)
     <> round(v_po_item.base_quantity_per_purchase_unit,4) then
    raise exception 'Received unit conversion does not match purchase order item';
  end if;

  v_expected_base :=
    v_po_item.ordered_quantity * v_po_item.base_quantity_per_purchase_unit;

  select coalesce(sum(gri.base_quantity),0)
  into v_already_posted
  from public.goods_receipt_items gri
  join public.goods_receipts gr on gr.id = gri.goods_receipt_id
  where gri.purchase_order_item_id = new.purchase_order_item_id
    and gr.status = 'POSTED'
    and (tg_op <> 'UPDATE' or gri.id <> new.id);

  if v_already_posted + new.base_quantity > v_expected_base then
    raise exception
      'Received quantity exceeds remaining purchase order quantity';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_guard_goods_receipt_po_quantity
on public.goods_receipt_items;

create trigger trg_guard_goods_receipt_po_quantity
before insert or update of
  purchase_order_item_id,
  inventory_item_id,
  purchase_uom_id,
  purchase_quantity,
  base_quantity_per_purchase_unit,
  base_quantity
on public.goods_receipt_items
for each row
execute function public.guard_goods_receipt_po_quantity();

revoke all on function public.guard_goods_receipt_po_quantity()
from public, anon, authenticated;
