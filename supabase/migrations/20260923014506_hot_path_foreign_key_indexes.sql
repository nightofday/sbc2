-- Targeted foreign-key indexes for high-traffic POS, inventory, refund,
-- purchasing and finance paths.

create index if not exists idx_menu_variants_finished_inventory_item
  on public.menu_variants(finished_inventory_item_id)
  where finished_inventory_item_id is not null;

create index if not exists idx_variant_recipe_components_inventory_item
  on public.variant_recipe_components(inventory_item_id);

create index if not exists idx_modifier_recipe_components_inventory_item
  on public.modifier_recipe_components(inventory_item_id);

create index if not exists idx_order_items_menu_item
  on public.order_items(menu_item_id);

create index if not exists idx_order_items_menu_variant
  on public.order_items(menu_variant_id);

create index if not exists idx_order_item_modifiers_modifier
  on public.order_item_modifiers(modifier_id);

create index if not exists idx_order_discounts_discount_type
  on public.order_discounts(discount_type_id);

create index if not exists idx_payments_refund
  on public.payments(refund_id)
  where refund_id is not null;

create index if not exists idx_payments_processed_by
  on public.payments(processed_by);

create index if not exists idx_refund_items_order_item
  on public.refund_items(order_item_id);

create index if not exists idx_refunds_shift
  on public.refunds(shift_id);

create index if not exists idx_stock_movements_inventory_lot
  on public.stock_movements(inventory_lot_id);

create index if not exists idx_stock_movements_order_item
  on public.stock_movements(order_item_id)
  where order_item_id is not null;

create index if not exists idx_purchase_order_items_inventory_item
  on public.purchase_order_items(inventory_item_id);

create index if not exists idx_purchase_order_items_purchase_uom
  on public.purchase_order_items(purchase_uom_id);

create index if not exists idx_goods_receipt_items_inventory_item
  on public.goods_receipt_items(inventory_item_id);

create index if not exists idx_goods_receipt_items_po_item
  on public.goods_receipt_items(purchase_order_item_id)
  where purchase_order_item_id is not null;

create index if not exists idx_supplier_bill_payments_payment_method
  on public.supplier_bill_payments(payment_method_id);

create index if not exists idx_supplier_bills_created_by
  on public.supplier_bills(created_by);

create index if not exists idx_expenses_payment_method
  on public.expenses(payment_method_id);

create index if not exists idx_expenses_supplier
  on public.expenses(supplier_id);

create index if not exists idx_purchase_orders_created_by
  on public.purchase_orders(created_by);

create index if not exists idx_purchase_orders_approved_by
  on public.purchase_orders(approved_by)
  where approved_by is not null;
