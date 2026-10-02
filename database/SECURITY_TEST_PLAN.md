# Database Hardening / Acceptance Test Plan

Run these tests against a non-production Supabase project before connecting the Flutter UI.

## 1. Authentication and role security

- Create ADMIN, MANAGER and CASHIER test Auth users.
- Verify a CASHIER cannot update another employee.
- Verify a MANAGER can update normal employee profile fields.
- Verify a MANAGER cannot change a user's role to ADMIN.
- Verify only an account with roles.manage can change role assignments.
- Verify anonymous requests cannot read business tables.
- Verify anonymous requests cannot execute any function in the public schema.
- Verify all public application tables have RLS enabled.
- Verify all public views use `security_invoker=true`.
- Verify every `SECURITY DEFINER` function has a pinned `search_path`.
- Verify trigger/helper functions are not executable by authenticated clients.
- Verify every RPC called by Flutter has an explicit authenticated grant.
- Create probe tables and sequences and inspect the migration owner's function
  defaults to verify future objects are not exposed until explicitly granted.

## 2. Shift gate

- CASHIER without an open shift cannot create an order.
- CASHIER can call start_shift().
- Only one open shift per employee is allowed.
- After starting a shift, order creation succeeds.
- If require_opening_cash=true, missing opening cash is rejected.
- end_shift() calculates expected cash from opening cash, cash sales, cash refunds, pay-ins, and pay-outs/drops.
- If require_closing_cash=true, missing closing cash is rejected.

## 3. Server-authoritative menu pricing

- Create a menu variant priced at ₱150.
- add_order_item() must store ₱150 from the database.
- Direct client insertion of an order item at ₱1 must fail.
- Quantity updates must recalculate line and order totals.
- Removing an item must recalculate totals.
- Inactive menu items/variants cannot be added.
- Modifier price must come from modifiers.price_delta, not client input.

## 4. Menu inventory mode

- A menu variant may be untracked or finished-good inventory-driven.
- Recipe-driven mode and non-empty recipe payloads are rejected.
- Modifiers may affect price but cannot configure ingredient deductions.
- A finished-good mapping must point to an active tracked inventory item.

## 5. Discounts

- Senior/PWD discount requires an ID/reference number.
- Discount types requiring authorization reject a missing authorizer.
- Discount allocation rows are created in order_discount_items.
- Discount total never exceeds eligible amount.
- Cashier cannot directly write discount amounts.
- Final SC/PWD tax treatment remains blocked from production sign-off until business/BIR validation.

## 6. Inventory receiving

- Expiry-tracked item rejects a receipt without expiration.
- Posting a valid receipt creates an inventory lot and PURCHASE_RECEIPT stock movement.
- Posting the same goods receipt twice is rejected.
- Partial PO receiving changes PO to PARTIALLY_RECEIVED.
- Receiving remaining quantity changes PO to RECEIVED.

## 7. Inventory ledger and FEFO

- v_inventory_stock.current_quantity equals the sum of stock movement deltas.
- v_inventory_stock.usable_quantity excludes expired lots.
- v_inventory_stock.expired_quantity reports expired stock that still needs disposal.
- v_low_stock compares the reorder level against usable quantity.
- MANUAL_IN creates a lot and positive movement.
- WASTE/DAMAGED/EXPIRED/MANUAL_OUT consumes available lots.
- Earliest expiration is consumed before later expiration.
- Stock-out and checkout never consume an expired lot.
- POS availability uses usable quantity rather than total on-hand quantity.
- Insufficient stock rolls back checkout when negative stock is disabled.
- Failed checkout creates no payment and no stock movement.
- One stock-out accepts multiple unique supply lines.
- A package conversion deducts the correct base quantity.
- Incompatible release and base-unit dimensions are rejected.
- Insufficient stock rolls back the entire multi-line stock-out.
- Each stock-out movement links to its header and line.

## 8. Checkout

- Checkout without active shift is rejected.
- Checkout with no items is rejected.
- Cash requires amount_tendered.
- Cash change must equal tendered minus applied payment.
- GCash/Maya/Card methods marked requires_reference=true reject missing reference.
- Non-cash payment rejects non-zero change.
- Multiple payment entries are rejected while split payments are disabled.
- Payment total must equal order total.
- Successful checkout inserts payments, deducts inventory, completes order, records shift, creates invoice and writes audit history.
- Reusing an idempotency key must not duplicate a payment.

## 9. Void

- Unpaid/open order can be voided by an authorized role.
- Void requires a reason.
- Paid order cannot be voided and must use refund workflow.

## 10. Refund

- Refund cannot exceed sold quantity.
- A second partial refund cannot exceed remaining quantity.
- Trusted refund amount is calculated server-side.
- Refund payment total must equal calculated refund total.
- Online refund method requiring reference rejects missing reference.
- Full cumulative refund changes order status to REFUNDED.
- Partial cumulative refund changes order status to PARTIALLY_REFUNDED.
- Prepared food is not automatically restored to inventory.
- Credit note is created for an invoiced sale.

## 11. Supplier bills

- Supplier bill may be UNPAID.
- First partial supplier payment changes status to PARTIALLY_PAID.
- Final payment changes status to PAID.
- Overpayment is rejected.
- Required online reference is enforced.

## 12. Auditability

Confirm audit records exist for shift start, shift end, order checkout, goods receipt posting and order refund.
Historical orders/payments/invoices/stock movements must not be hard-deleted during normal operations.

## 13. Reporting smoke tests

Verify `v_inventory_stock`, `v_low_stock`, `v_expiring_inventory_lots`,
`v_daily_sales`, `v_product_sales_daily`, `v_business_transaction_trace`,
`v_order_cogs`, `v_shift_summary`, `v_supplier_balances` and
`v_daily_profit_estimate` against manually calculated sample data. Confirm that
cashiers receive no rows from the management transaction trace.

## 14. Production blockers

- VAT or Non-VAT registration.
- Registered business/TIN/address/invoice details.
- Current BIR POS/invoicing requirements.
- Actual SC/PWD calculation used by the café.
- Actual payment methods and online reference workflow.
- Whether split payments are needed.
- Shift opening/closing cash procedure.
- Printer model and paper width.
- Internet outage/offline behavior.
- Backup and restore procedure.
