-- Purchase-order line read model with posted received quantities and remaining quantity.

create or replace view public.v_purchase_order_lines_remaining
with (security_invoker = true)
as
select
  poi.id,
  poi.purchase_order_id,
  poi.inventory_item_id,
  ii.name as inventory_item_name,
  poi.purchase_uom_id,
  u.code as purchase_uom_code,
  poi.ordered_quantity,
  poi.base_quantity_per_purchase_unit,
  poi.unit_cost,
  coalesce(received.received_base_quantity,0)::numeric(14,4)
    as received_base_quantity,
  (
    coalesce(received.received_base_quantity,0)
    / nullif(poi.base_quantity_per_purchase_unit,0)
  )::numeric(14,4) as received_purchase_quantity,
  greatest(
    0,
    poi.ordered_quantity
      - (
          coalesce(received.received_base_quantity,0)
          / nullif(poi.base_quantity_per_purchase_unit,0)
        )
  )::numeric(14,4) as remaining_purchase_quantity
from public.purchase_order_items poi
join public.inventory_items ii on ii.id = poi.inventory_item_id
join public.units_of_measure u on u.id = poi.purchase_uom_id
left join lateral (
  select sum(gri.base_quantity) as received_base_quantity
  from public.goods_receipt_items gri
  join public.goods_receipts gr on gr.id = gri.goods_receipt_id
  where gri.purchase_order_item_id = poi.id
    and gr.status = 'POSTED'
) received on true;

grant select on public.v_purchase_order_lines_remaining to authenticated;
revoke all on public.v_purchase_order_lines_remaining from anon;
