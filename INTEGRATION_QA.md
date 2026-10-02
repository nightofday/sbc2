# Full-System Integration QA

Branch: `brian/inventory-workflow-navigation`

This document tracks integration work and rollback-based database regression checks. It is not a claim that the application is production-ready.

## Integrated modules

- Supabase Auth and role-aware navigation
- Grouped role-aware navigation with collapsible desktop sections, a compact
  tablet rail and a phone drawer
- Shared responsive filter bars, narrow-phone page actions and scroll-safe
  dialogs across the integrated modules
- Dashboard with live daily sales/order/refund/expense metrics
- Orders / POS with shifts, payments, variants, modifiers, promotional discounts, refunds and invoice issuance
- Inventory with multi-item stock-out, package conversions, lots, FEFO, traceable movements and lot-specific disposal
- Separate inventory workflow views for Stock Overview, Release Supplies,
  Dispose Stock, Inventory Count, Stock Adjustment and Inventory History
- Physical inventory counts accept multiple items, compare physical quantities
  with system stock and post all variances as one traceable transaction
- Separate on-hand, usable and expired quantities, with expired lots excluded from release and POS availability
- Menu management with variants, countable finished-good mappings and modifiers; recipe deduction is retired
- Expenses with date, supplier/grocery, purpose, amount, reference, notes and create/update/void workflow
- Suppliers with live Supabase records
- Purchasing with purchase orders, approval, partial receiving, goods receipts and supplier bills
- Receiving requires a supplier invoice/grocery receipt reference and supports
  explicit package conversions such as one box containing fifty pieces
- Sales & Finance with reporting data and supplier bill payments
- Period-aware reports with gross, refunded and net product totals
- Management transaction traceability across sales, refunds, inventory,
  purchasing, expenses and supplier payments
- Users with role/status management and the protected `create-employee` Edge Function
- Optional repeatable presentation master data, an editable crow's-foot ERD and
  an end-to-end live demonstration walkthrough

## Regression checks completed

The automated pgTAP suite includes 85 consultation-alignment and security
assertions in addition to the existing integration regression suite. Each
scenario creates isolated fixtures inside a transaction and rolls them back.
Run it with:

```bash
supabase start
supabase test db
```

Database CI runs the same suite for integration-branch pushes and pull requests.

The final Phase 10 regression test runs the optional presentation seed twice,
checks its supplier, package-conversion, menu and modifier masters, and confirms
that it neither reintroduces recipe deductions nor fabricates inventory lots or
stock movements.

### POS and inventory

- Finished-good availability is exposed to POS.
- POS rejects quantity above available finished stock.
- Checkout deducts finished goods.
- Prepared-to-order variants do not deduct ingredients.
- Prepared-to-order variants do not expose recipe-derived stock availability.
- Only countable finished products can become unavailable from POS stock.
- Recipe inventory mode is rejected by the database API.
- Required modifier rules are enforced.
- Server-side pricing remains authoritative.
- Underpayment is rejected.
- Split payments remain disabled while the feature flag is false.

### Refunds

- First partial refund changes an order to `PARTIALLY_REFUNDED`.
- Refund preview returns only the remaining refundable quantity.
- A second refund can complete the remaining quantity.
- Fully refunded orders become `REFUNDED`.
- Repeated/over-refund attempts are rejected.
- Finished-good restocking requires the explicit restock workflow.
- Unsafe restocking into blocked lots is rejected.

### Purchasing

- Draft purchase order creation works.
- Approval transitions the order into an approved state.
- Partial goods receipt updates the purchase order to `PARTIALLY_RECEIVED`.
- Remaining purchase quantity is calculated from posted receipts only.
- Over-receiving a purchase-order line is rejected.
- Receiving the exact remainder transitions the purchase order to `RECEIVED`.
- One direct goods receipt accepts multiple supplies and posts them atomically.
- Supplier invoice/grocery receipt number and date are mandatory and duplicate
  references for the same supplier are rejected.
- Goods receipt details preserve purchase unit, package conversion, batch/lot,
  expiration date, received base quantity and remaining lot balance.

### Expenses

- Posted expenses require a valid supplier/grocery and receipt/reference.
- Duplicate active receipt/reference values for the same supplier are rejected.
- Untracked ingredient/grocery expenses are classified separately from normal
  operating expenses.
- Expense creation and editing repeat the same server-side validation.
- Cashiers cannot create or edit expenses.
- Order, inventory, purchasing, menu, expense, dashboard, finance and report
  views share refresh notifications after a successful transaction.

### Reports and traceability

- The selected report period applies to daily sales, expenses and top products.
- Product reporting separates gross sold, refunded and net quantities.
- Completed line refunds reduce net product sales without changing the original
  gross sale record.
- Management can trace sales, refunds, goods receipts, stock-outs, inventory
  counts, expenses and supplier payments in one chronological view.
- Trace rows preserve readable document numbers, external receipt/payment
  references, amounts, supplier/customer context, responsible employee and
  timestamp where applicable.
- Cashiers cannot read the management transaction traceability report.

### Practical inventory release

- One stock-out document accepts multiple supplies.
- Package-to-base-unit conversion is stored and applied.
- Standard unit conversions are calculated automatically; variable box and pack sizes are entered per release.
- Earliest-expiring usable stock is released first.
- Expired lots remain visible on hand until disposal but are excluded from usable stock.
- POS availability, release validation and low-stock reporting use usable stock.
- Sale consumption never takes quantity from an expired lot.
- Insufficient stock rolls back the entire transaction.
- Movement rows link back to the stock-out line and header.
- Item history exposes readable source document and receipt/reference values.
- Inventory History can be filtered by item, movement type, date range,
  document/reference, reason, or item name.
- Disposal requires an exact lot, quantity, disposal type and written reason.
- Stock adjustments require a physical-count direction, quantity and reason;
  the resulting ledger entry remains part of immutable movement history.
- One physical count accepts multiple unique items and records the system,
  physical and variance quantity for every line.
- Negative count variances deduct available lots in FEFO order; positive
  variances create a traceable count lot and require expiry when applicable.
- Count posting is atomic, permission checked and exposed in Inventory History
  with its `IC-` document number.

### Shifts and cash

- Shift start/end works.
- Pay-in and pay-out movements update expected cash.
- Closing cash variance is calculated when a counted amount is supplied.
- Cashier session isolation is enforced.

### Authorization

- Cashiers receive only their own operational dashboard scope.
- Cashier navigation exposes only Dashboard, Orders / POS and Stock Overview.
- Management navigation groups operational, inventory, purchasing, finance,
  reporting and administration destinations without changing authorization.
- Release, disposal and adjustment actions continue to rely on server-side
  `inventory.adjust` permission checks; hiding navigation is not the security boundary.
- Cashiers cannot create suppliers.
- Cashiers cannot create menu products/variants.
- Profile RLS prevents a cashier from reading or editing another employee profile.
- Administrative and management RPCs perform permission checks server-side.

## Database hardening

- RLS is enabled on operational tables.
- Anonymous access to the public business-data schema, tables, views,
  sequences and RPC functions is explicitly denied.
- Public and private schema default privileges now fail closed. Every future
  table, sequence, view or RPC must be deliberately granted in its migration.
- Internal helper functions are not exposed to normal API roles.
- Business-changing operations use permission-checked RPC functions.
- Automated security regression tests verify RLS coverage, invoker-security
  views, pinned search paths, hidden helper functions and the Flutter RPC
  allow-list.
- High-traffic foreign-key and report-period indexes were added for POS,
  inventory, refunds, purchasing, finance and traceability.
- Overlapping `FOR ALL` management policies were split into action-specific
  `INSERT`, `UPDATE` and `DELETE` policies. Existing read policies and
  permission expressions were preserved, and the duplicate permissive-policy
  advisor warning is clear.
- Supabase security advisor still reports public `SECURITY DEFINER` API functions. These are intentional RPC entry points and each must retain its internal authorization checks.
- Supabase Auth leaked-password protection is still disabled and should be enabled in the Supabase Auth settings before production use.
- The remaining foreign-key and unused-index advisor notices are informational;
  they should be reviewed again with real usage data instead of adding or
  removing every index preemptively.

## Intentionally pending business decisions

### Senior citizen / PWD discounts

The schema contains Senior and PWD discount definitions, but the POS intentionally does not expose them yet. Philippine tax/VAT handling depends on the café's actual registration and applicable current rules. Do not enable these discounts until that configuration is verified.

### Real menu and practical inventory masters

Development products and inventory are placeholders for integration testing. Before deployment:

- replace seed menu products with Street Bowl Café's real menu;
- configure actual sizes/variants and prices;
- link finished goods to their correct inventory records;
- configure real modifiers/add-ons;
- configure supplier-item mappings, purchase/release units and package conversions;
- identify the final countable supplies and finished goods;
- record untracked ingredient/grocery purchases through Expenses.

### Production settings

Before production:

- confirm tax/VAT registration details;
- fill the business profile and invoice information;
- decide whether opening and closing cash counts are mandatory;
- decide whether split payments should be enabled;
- enable leaked-password protection;
- use production inventory opening balances rather than development seed quantities;
- review user accounts and least-privilege roles.

## Flutter validation

GitHub contains a Flutter CI workflow for `flutter analyze` and `flutter test`. A local run should also be completed after pulling the integration branch, because the development environment has the project's exact Flutter SDK and platform-generated files.

### Responsive UI checks

- Search/filter controls stack consistently below their configured breakpoint.
- Page-level actions use the available width on very narrow phones.
- Summary values scale down instead of overflowing their cards.
- Wide data tables retain horizontal scrolling on phone layouts.
- Dialog content remains scrollable on small screens and when the keyboard is open.
- Authentication/account-state cards use safe-area padding and vertical scrolling.
- Purchasing line summaries move their amount/actions below item details when space is limited.

Widget regression tests exercise the shared filters, a phone-sized page with a
large summary amount and wide table, and a long phone-sized dialog.
