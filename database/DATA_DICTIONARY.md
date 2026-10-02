# Data Dictionary

## Identity, access, shifts

| Table | Purpose |
|---|---|
| `business_profile` | Single café identity, address and tax-registration settings. |
| `system_settings` | Feature/configuration flags such as opening-cash requirement and expiry warning days. |
| `devices` | Registered POS/tablet terminals. |
| `roles` | Application roles such as ADMIN, MANAGER, CASHIER. |
| `permissions` | Fine-grained capabilities. |
| `role_permissions` | Role-to-permission mapping. |
| `profiles` | Employee profile linked to Supabase `auth.users`. |
| `shifts` | Employee cashier/operational shifts. |
| `shift_cash_movements` | Cash pay-ins, pay-outs, drops and corrections during a shift. |
| `audit_logs` | Append-only audit trail for sensitive business actions. |

## Menu

| Table | Purpose |
|---|---|
| `menu_categories` | Product/menu categories. |
| `menu_items` | Product families such as Iced Latte. |
| `menu_variants` | Sellable variants such as Small / Medium / Large. |
| `modifier_groups` | Customization groups such as Sugar Level or Add-ons. |
| `modifiers` | Options such as Extra Shot. |
| `menu_item_modifier_groups` | Which modifier groups apply to which menu items. |
| `variant_recipe_components` | Legacy compatibility table; active recipe deductions are retired. |
| `modifier_recipe_components` | Legacy compatibility table; active modifier recipe deductions are retired. |

## Orders and payments

| Table | Purpose |
|---|---|
| `orders` | Main operational order record. |
| `order_items` | Sold variants with price/name/tax snapshots. |
| `order_item_modifiers` | Selected modifiers with price snapshots. |
| `discount_types` | Senior, PWD, promo, manual, etc. |
| `order_discounts` | Discount applied to an order. |
| `payments` | Sale and refund money transactions; supports split payment. |
| `refunds` | Full/partial refund headers. |
| `refund_items` | Line-level refunded quantities/amounts. |
| `order_actions` | Void/refund/manager authorization audit actions. |
| `order_status_history` | Status changes over the order lifecycle. |

## Inventory

| Table | Purpose |
|---|---|
| `units_of_measure` | g, kg, ml, L, pc and other units. |
| `inventory_categories` | Ingredient/packaging/finished-good categories. |
| `inventory_items` | Stock-controlled materials/products. |
| `inventory_lots` | Received batches with cost and expiry. |
| `stock_movements` | Permanent stock ledger. |
| `stock_out_transactions` | Multi-item supply-release header with purpose, reference, user and date. |
| `stock_out_items` | Supply lines and package-to-base-unit conversions for a stock-out. |
| `stock_counts` | Physical count headers, posting state, responsible employee and notes. |
| `stock_count_items` | System, physical and variance quantities, plus cost/expiry metadata for positive adjustments. |

## Suppliers and purchasing

| Table | Purpose |
|---|---|
| `suppliers` | Supplier master records. |
| `supplier_items` | Supplier-specific item/UOM/pack/cost defaults. |
| `purchase_orders` | Optional planned purchases. |
| `purchase_order_items` | PO lines. |
| `goods_receipts` | Actual supplier deliveries/direct purchases with mandatory supplier invoice or grocery receipt traceability. |
| `goods_receipt_items` | Multi-item received lines with purchase-unit conversion, cost, batch and expiration details; each creates an inventory lot. |
| `supplier_bills` | Amount owed to suppliers. |
| `supplier_bill_payments` | Full or partial settlement of supplier bills. |

## Expenses and fiscal records

| Table | Purpose |
|---|---|
| `expense_categories` | Operating expense categories. |
| `expenses` | Non-inventory operating costs and untracked ingredient/grocery purchases, with required supplier and receipt traceability; active references are unique per supplier. |
| `tax_rates` | Configurable sales tax/VAT definitions. |
| `payment_methods` | Cash, GCash, Maya, Card, Bank Transfer, Other. |
| `invoice_sequences` | Controlled invoice number sequences. |
| `sales_invoices` | Issued sales invoice snapshots. |
| `credit_notes` | Refund-related fiscal adjustment documents. |
| `invoice_print_events` | Invoice/receipt print audit records. |

## Reporting views

| View | Purpose |
|---|---|
| `v_pos_menu` | Active sellable variants, authoritative price and practical finished-good availability for POS. |
| `v_pos_modifiers` | Active modifier groups/options and their selection rules for POS. |
| `v_menu_management` | Menu, variant and finished-good mapping data for management screens. |
| `v_inventory_stock` | On-hand inventory calculated from the permanent stock ledger. |
| `v_inventory_catalog` | Inventory master data with on-hand, usable and expired quantities for application screens. |
| `v_inventory_lots` | Per-lot remaining quantity, expiration and availability information. |
| `v_low_stock` | Tracked items whose usable quantity is at or below the reorder level. |
| `v_inventory_movement_history` | Per-item movement history with readable source documents and external references. |
| `v_stock_out_summary` | Multi-item stock-out headers with responsible employee and line totals. |
| `v_stock_count_summary` | Physical count headers with line and variance counts. |
| `v_purchase_order_summary` | Purchase-order status and amount summary. |
| `v_purchase_order_lines_remaining` | Ordered, received and remaining purchase quantities per PO line. |
| `v_goods_receipt_summary` | Goods receipt header, supplier, receipt reference and posting summary. |
| `v_goods_receipt_line_details` | Received package quantity, conversion, base quantity and resulting lot balance. |
| `v_user_management` | Employee profile, role and account status for authorized administrators. |
| `v_daily_sales` | Daily completed sales totals. |
| `v_product_sales_daily` | Daily product-level gross sold, refunded and net quantities and sales, using the café's Manila business date. |
| `v_business_transaction_trace` | Management-only chronological trace across sales, refunds, goods receipts, stock-outs, physical counts, expenses and supplier payments. |

The transaction trace is derived from the operational source tables. It does
not duplicate or replace their records. Its `document_number` is the readable
internal reference, while `external_reference` stores the supplier receipt,
invoice, payment or other outside reference when one exists.

## Important field conventions

### IDs

Business tables use UUID primary keys so records can later be created safely in offline-capable clients.

Human-facing numbers are separate fields such as:

- `order_number`
- `shift_number`
- `purchase_order_number`
- `receipt_number`
- `stock_out_number`
- `refund_number`

### Money

Use `numeric(14,2)`.

### Quantities

Use `numeric(14,4)`.

### Soft state

Master data uses fields such as:

```text
is_active
archived_at
```

Historical transactional records should not normally be deleted.

## Seed data conventions

`supabase/seed.sql` contains the reference and base prototype masters used by a
fresh local environment. `supabase/demo_seed.sql` is an optional presentation
overlay containing stable `DEMO-` supplier codes and `INV-DEMO-` inventory
SKUs. Both scripts are repeatable.

The presentation seed intentionally creates no Auth users, completed orders,
payments, refunds, expenses, goods receipts, inventory lots or stock movements.
Those records must be produced through the application workflows so their audit
trail and cross-module data flow remain genuine.
