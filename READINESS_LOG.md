# Readiness log

A running record of how this app is taken from the audited prototype to something the café can use: what was found, what was changed, why, and what evidence exists. Newest entries go at the bottom of each section. Task IDs refer to [TODO.md](TODO.md); rules are in [AGENTS.md](AGENTS.md).

Status words are used strictly: **found** (observed, not fixed), **changed** (code or schema edited), **verified** (checked with the evidence named), **accepted** (confirmed by the café).

## 1. Starting point (2 October 2026)

- Source: `main` at `59db8c8` ("Initialize SBC 2") from `bbriones559657/sbc2`. Work happens on branch `charlie`.
- The backlog lists about 35 open tasks in five batches. Its audit was done by reading code; the app and the tests had not been run against this commit.

## 2. Environment set up

| Item | State | Evidence |
| --- | --- | --- |
| Flutter 3.47.6 / Dart 3.13.5 | installed | `flutter analyze`: no issues. `flutter test`: 22 passed. |
| Supabase CLI 2.109.1 | installed (version pinned by Database CI) | `supabase --version` |
| Hosted test database | project `ybjyandkpgegrtthokgs`, 38 migrations and `seed.sql` applied | `supabase db push --include-seed` output, no errors |
| First admin account | created in the dashboard, then activated by SQL | signed in as Administrator |
| Docker | not installed | pgTAP database tests have **not** been run |
| `create-employee` Edge Function | deployed to the test project on 3 October 2026 (version 1, JWT required) | a Cashier account was created with it from User Management on 3 October 2026 |

Found during setup:

- **Committed `pubspec.lock` is incomplete.** It lacks the `supabase_flutter` dependency tree; `flutter pub get` adds about 415 lines and regenerates the desktop plugin registrants. Not yet committed.
- **First-admin bootstrap is undocumented and blocked by a guard.** `database/INTEGRATION_PLAN.md` says to assign the ADMIN role by SQL, but `trg_protect_profile_privileges` rejects a role `UPDATE` unless the caller already has `roles.manage`. The working method was to delete the auto-created `PENDING` profile and insert it again as `ADMIN`/`ACTIVE` in one transaction. This needs a supported bootstrap path (`AUTH-01`).

## 3. First run of the app (look-only pass)

All 14 destinations opened as Administrator in the phone-width layout against the hosted test database. Nothing was created or posted in this pass.

| ID | Finding | Status | Task |
| --- | --- | --- | --- |
| F-01 | Menu Management rows overflow by 9 px at about 800 px width; Flutter logs a layout error per row. Source: action-button row at `lib/screens/menu/menu_management_screen.dart:217`. | found | `UX-03`, `MOD-01` |
| F-02 | `supabase/seed.sql` is described as reference data only but creates 8 menu products and 3 stock items with opening quantities and stock-in movements. | found | `DOC-01` |
| F-03 | "Add Expense" is disabled until a supplier exists. Deliberate, but a first-run trap. | found | `UX-04` |
| F-04 | The Email column is blank for the admin row in User Management. Cause not investigated. | found | `AUTH-01` |
| F-05 | In New Order, the cart once showed Chocolate Cake × 4 while the app warned "only has 2 available". **Not reproduced** in the transaction pass: both the Add button and the cart "+" stopped at 2. | not reproduced | — |

Not covered yet: any transaction (sale, refund, receiving, release, disposal, count, expense), tablet and desktop layouts, Cashier and Manager logins.

## 3a. Transaction pass (2 October 2026, Administrator, hosted test database)

Run in debug mode at a 296 px wide viewport, which is narrower than the 320 px minimum in `UX-03`; layout overflows seen at this width are marked as such. Test records are prefixed `TEST`.

Steps completed and results:

| Step | Result |
| --- | --- |
| Add supplier "TEST Grocery Mart" | saved; listed |
| Add inventory item "TEST Paper Cups" (pc) | saved |
| Receive 2 boxes at 50 pc per box, ₱100 per box, invoice `TEST-INV-001` | posted as `GR-1`; Stock Overview shows Usable 100 pc; supplier payable appears in Finance |
| Sell 1 Cookie + 2 Chocolate Cake, 10% promotional discount, cash | order `#1`, invoice `SI-00000001`, subtotal ₱410, discount ₱41, total ₱369 |
| Refund 1 Chocolate Cake | refund ₱162 (discount correctly allocated: ₱162 per cake, ₱45 per cookie) |
| Compare Dashboard, Finance | agree after reload: net sales ₱207, refunds ₱162, 1 order |

Findings:

| ID | Finding | Status | Task |
| --- | --- | --- | --- |
| F-06 | **App crashed to the Flutter error screen** when saving a line in Receive Stock → Add Item (first attempt). Console: "A TextEditingController was used after being disposed", then framework assertions. The same steps worked on the second attempt, so it is intermittent. Likely cause: `_showLineEditor` in `lib/screens/purchasing/purchasing_screen.dart` disposes its controllers immediately after the dialog returns, while the closing dialog can still rebuild. The same dispose-after-dialog pattern appears in most screens. Seen in debug mode only; release-mode behavior not tested. | found | new (P0 candidate) |
| F-07 | "setState() callback argument returned a Future" is logged in the purchasing and payment flows. | found | `UX-04` |
| F-08 | The receipt and the order detail list items at full price (₱50 + ₱360) and a total of ₱369 with **no discount line**. | found; confirms `POS-02` | `POS-02` |
| F-09 | After a sale and a refund, the **Dashboard still showed ₱0.00 and 0 orders** while Finance showed ₱207. It was correct only after reloading the page. | found; confirms `SYNC-01` | `SYNC-01` |
| F-10 | Finance labels ₱369 as "Gross Sales"; that figure is already after the ₱41 discount. Pre-discount sales (₱410) and the discount are not shown anywhere. | found; confirms `FIN-01` | `FIN-01`, `REP-02` |
| F-11 | The payment dialog defaults the method to "Other", and "Amount Received" stays at the pre-discount ₱410 after a discount is applied. | found | `UX-01`, `UX-04` |
| F-12 | Add Supplier offers only name and phone. Email, address, contact person and terms cannot be entered, so `SUP-01` (details wiped on edit) cannot be reproduced through the app alone. | found | `SUP-01`, `PUR-01` |
| F-13 | Layout overflows at 296 px: item dropdown in Received Item (24 px, `purchasing_screen.dart:987`) and discount dropdown in Proceed to Payment (32 px). Below the supported minimum width; recheck at 320 px. | found | `UX-03` |

Worked as intended: package conversion on receiving, the finished-goods stock cap in the cart, proportional discount allocation in the refund preview, invoice numbering.

Not yet exercised: stock release, disposal, physical count, adjustment, expenses, purchase orders, supplier bill payment, shift close, Cashier and Manager roles, reports beyond Finance.

### Transaction pass, part 2 (same day, after the fixes in section 5)

| Step | Result |
| --- | --- |
| Release 1 box of TEST Paper Cups (50 pc per box) | posted as `SO-1`; on hand went 100 → 50 pc |
| Dispose 1 Coca-Cola from lot `SEED-INV-002` as damaged | "Lot disposal recorded" |
| Record expense, ₱350, receipt `TEST-OR-001` | posted as `EX-1` |
| Dashboard after the expense, without reloading | expenses ₱350, net after expenses −₱143 (confirms the F-09 fix live) |

| ID | Finding | Status | Task |
| --- | --- | --- | --- |
| F-14 | Releasing by the box asks for "pc in one box" again; the 50 entered at receiving is not remembered. Nothing writes `supplier_items`, so no package definition is stored. | found | `INV-01`, `PUR-01` |
| F-15 | In Dispose Stock the row is not tappable; the only action is a "Review Lots" button in the last column, off-screen at phone width. | found | `UX-01`, `UX-03` |
| F-16 | Add Expense overflows by 11 px at 296 px, and the category defaults to the first one ("Utilities") rather than asking. | found | `UX-03`, `UX-04` |
| F-17 | Once, cancelling a dialog left the screen dimmed and unresponsive with repeated "Unexpected null value" errors, and the screen state had reset. Most likely cause: `AuthGate` rebuilt the whole app on a background auth event. Not reproduced on demand. | changed (see section 5), not verified by test | `SYNC-01`, `UX-04` |

Correction to F-04: the blank email is **not an app defect**. `profiles.email` is filled by the new-user trigger, and the first-admin bootstrap in section 2 replaced that row without the email. The underlying gap is that the email is only synchronised when the auth user is created.

Still not exercised: physical count, stock adjustment, purchase orders, supplier bill payment, shift close, Cashier and Manager logins (creating those accounts needs the dashboard or the undeployed `create-employee` function).

## 4. Database schema review (first pass)

Method: counted, for each of the 53 public tables and 26 views, the references in `lib/`, in the combined migration SQL (inserts, updates, reads) and in the pgTAP tests, then read the definitions of the outliers. This is a usage review of the migration text, not a full audit, and nothing has been dropped.

### 4.1 Present but unused — candidates to remove or to finish

| Object | What the review found | Recommendation |
| --- | --- | --- |
| `devices` | No reads or writes anywhere. Six foreign-key columns on other tables point to it. | **Keep.** Offline selling (section 7) needs registered devices and per-device numbering. Superseded the earlier "drop" suggestion. |
| `invoice_print_events` | No reads or writes anywhere. | Keep if receipt printing is built (`OPS-02`); otherwise drop. |
| `tax_rates` | Seeded with 4 rows, never read. One foreign key points to it. | Keep until the VAT question is answered (`OPS-03`); drop if the café is non-VAT. |
| `variant_recipe_components`, `modifier_recipe_components`, `private.retired_*` | Recipe deduction is retired. Tables are empty in a fresh database but still referenced by older functions and tests. | Do not drop yet: AGENTS.md §6 requires a history check first. Flag to Brian. |
| `v_daily_profit_estimate`, `v_order_cogs` | Read by nothing. The first presents a "profit" figure the business rules say must not be shown as profit. | **Dropped** in `20261002220000`. |
| `v_product_sales`, `v_low_stock`, `v_expiring_inventory_lots`, `v_shift_summary` | Read by neither the app nor other SQL. | `v_low_stock` and `v_expiring_inventory_lots` are now read by Reports. `v_product_sales` and `v_shift_summary` were **dropped** in `20261002220000`; `get_shift_report` replaces the second. |
| `credit_notes` | Written by the refund functions, never read. | Keep (history); surface in order/refund detail (`POS-02`). |

### 4.2 Needed but missing

| Gap | Evidence | Task |
| --- | --- | --- |
| No functions to create, rename, reorder or archive menu, inventory or expense categories | No category function exists in any migration | `CAT-01` |
| No functions to manage discount types | Only `get_pos_discount_types` exists | `DIS-01` |
| Nothing ever writes `supplier_items` | Zero inserts in migrations; the app only reads it | `INV-01`, `PUR-01` | *Addressed 3 October 2026: written at receiving (`20261002240000`).*
| No way to read `audit_logs` | 13 write sites, no view, function or screen | `TRACE-01` | *Addressed 3 October 2026: `get_audit_log` and the Audit Log screen.*
| No screen or function to edit `business_profile` or `system_settings` | Seeded once, read by a few functions | new; raise with Brian | *Addressed 3 October 2026: Business Details screen (`20261002250000`).*
| `update_supplier` takes `null`/`0` defaults for contact, email, address and terms | Function signature; matches the `SUP-01` report | `SUP-01` |
| Checkout request ID exists in the database but the app sends null | `supabase_order_repository.dart` (`E08`) | `POS-01` |
| Reports have no custom date range, pagination or export | Views are per-day; app limits to 7/30 days and top 10 | `REP-01`–`REP-05` |

## 5. Changes made

| Date | Change | Why | Evidence |
| --- | --- | --- | --- |
| 2026-10-02 | Added `CLAUDE.md` (`74b6e60`) | Commands and architecture notes for AI-assisted work | links and claims checked against source |
| 2026-10-02 | Added this log | Record of the path to readiness | — |
| 2026-10-02 | `showSettledDialog` in `lib/widgets/common/app_dialog.dart`; `showPrototypeDialog` and the two raw `showDialog` calls now use it (`c4d1ed6`) | F-06: dialogs completed while still animating out, so callers disposed controllers the closing dialog was still using | `test/app_dialog_test.dart` fails without the change and passes with it; live re-run of Receive Stock → Add Item did not crash |
| 2026-10-02 | Dashboard refresh callback uses a block body (`94c6d98`) | F-09/F-07: the arrow callback returned a Future, which `setState` rejects in debug builds before marking the screen dirty, so the dashboard never redrew | `test/dashboard_refresh_test.dart` fails without the change and passes with it; live check after posting an expense |
| 2026-10-02 | `AuthGate` refreshes an already loaded profile in place (`bc72e72`) | F-17: every auth event showed the loading screen and unmounted the app | analyzer and existing tests only; no automated test (needs an initialised Supabase client) |
| 2026-10-02 | Migration `20261002132705_business_date_helper.sql`: `business_today()` replaces every `current_date`; expense and supplier-bill date defaults use it (`aca52a7`) | S-01: the server date is UTC, a day behind Manila until 08:00 | pgTAP `10_business_date.test.sql`, 9 of 9 passing; no public function or view contains `current_date` afterwards; applied to the hosted test project |
| 2026-10-02 | Migration `20261002134000_checkout_request_id.sql`: `create_order`, `place_order`, `place_order_v2` return a stored order only to its creator, return a since-refunded sale instead of failing, and take an advisory lock per request (`aca52a7`) | POS-01 / S-06, server side | pgTAP `11_checkout_request_id.test.sql`, 9 of 9 passing; applied to the hosted test project. The advisory lock itself is not tested: that needs two concurrent sessions |
| 2026-10-02 | App sends a request ID with every checkout and recovers after a lost response (`a955e52`): `CheckoutAttempt`, `newRequestId`, `CheckoutSavedException` in `lib/models/pos_checkout.dart`; `findOrderByRequestId` on `OrderRepository`; POS screen logic | POS-01, app side: the app sent null, so a sale that committed just before the connection dropped could be charged twice | `test/checkout_request_id_test.dart` (4 tests, including a simulated lost response on the POS screen: two submissions, one request ID, one order); live sale stored a request ID (order `#8`) |
| 2026-10-02 | Migration `20261002150000_request_ids_for_posting_functions.sql`: `client_requests` table, two internal helpers, and an optional `p_client_request_id` on shift start and end, cash movements, refunds (`process_refund`, `process_refund_items`), stock release, adjustment, disposal, count, goods receipt, supplier payment and expense creation (`62b9d20`) | S-06: a retry after a lost response posted these twice | pgTAP `12_posting_request_ids.test.sql`, 33 of 33 passing; existing files `01`–`11` unchanged in result; applied to the hosted test project; no old overloads remain (12 functions, one signature each) |
| 2026-10-02 | Every posting form sends a request ID (`5d8b726`): one ID per form instance, passed through the repository interfaces to the functions above | S-06, app side | `flutter analyze` clean, 28 Flutter tests pass; one live cash movement (`PAY_IN` ₱20) stored a `client_requests` row linked to it |
| 2026-10-02 | Migration `20261002160000_close_direct_write_paths.sql`: all client write policies and write grants removed from 30 transactional tables; delete policies and delete grants removed from 20 master-data tables; `set_updated_at()` revoked from clients | S-14, S-16, S-19: posted records could be inserted, edited or deleted through the Data API, bypassing every function | pgTAP `13_direct_write_paths.test.sql`: 10 of 13 fail before the migration, 13 of 13 pass after; files `01`–`12` unchanged; `08_api_security_hardening` now 18 of 18 on the hosted project; write policies on the test project went from 98 to 48, none on transactional tables; app loads and reads with no permission errors |
| 2026-10-02 | Migration `20261002170000_auditable_edits_and_voids.sql` (`ac9e7b7`): `update_expense` writes the row before and after to `audit_logs`; `void_expense` requires a reason and stores it with who and when; `update_supplier` changes only the fields it is given; new `void_stock_out`, `void_stock_count`, `void_goods_receipt` | S-04, S-05, `SUP-01` (database side), `INV-02` (partly) | pgTAP `14_auditable_edits_and_voids.test.sql`, 39 of 39; files `01`–`13` unchanged; applied to the hosted test project |
| 2026-10-02 | Suppliers carry separate contact person, phone, email, address, payment terms and notes in the model, repository and forms; archiving sends the status alone (`8879246`) | `SUP-01` (app side), F-12 | `test/supplier_editor_test.dart`: renaming through the real form sends every other detail back unchanged |
| 2026-10-02 | `showReasonDialog`; void actions for expenses, goods receipts, supply releases and inventory counts (`43fe0ff`) | S-04/S-05 (app side): a function without a way to reach it is not a finished workflow | `test/reason_dialog_test.dart` (2 tests); live: `SO-1` voided from the app, stock went 50 → 100 in both lot and ledger, the original movement and a `REVERSAL` remain, one audit row written |
| 2026-10-02 | Migration `20261002180000_category_and_discount_management.sql` (`e6aafe4`): category list/create/update/reorder functions over the three category tables; discount types gain till-enabled flag, fixed or adjustable value, maximum and validity dates, with create and update functions; the till list and checkout use them instead of three hard-coded codes | `CAT-01`, `DIS-01`, S-13 | pgTAP `15_category_and_discount_management.test.sql`, 41 of 41; files `01`–`14` unchanged; applied to the hosted test project |
| 2026-10-02 | Categories and Discounts screens under Menu & Products; fixed-value promotions cannot be edited at payment; receipts and order details show subtotal and a named discount line (`951e0ff`) | `CAT-01`, `DIS-01`, F-08 (`POS-02`, discount part) | `test/catalog_management_test.dart` (4 tests); live: both screens load real data, a test category was added from the app |
| 2026-10-02 | Every list query asks for ascending order explicitly (`a8fa006`) | F-18: the Supabase client sorts descending by default and 32 queries gave no direction, so lists were reversed | live: the till now shows Coffee first, in category order; before, it started with Baked Goods |
| 2026-10-02 | Migration `20261002190000_modifier_management.sql` (`8ec00fb`) and the modifiers dialog and Manage menu (`6fc11d8`): group names need not be unique; attach, detach and reorder functions; a group library; a required group with no active options no longer blocks checkout; labelled actions instead of icon-only buttons | `MOD-01`, S-07 | pgTAP `16_modifier_management.test.sql`, 23 of 23; `test/modifier_management_test.dart` (3 tests) |
| 2026-10-02 | `DataTableCard` stacks each row with its column headings when the table does not fit a narrow screen (`6fc11d8`) | `UX-03`, F-01, F-15: status and action columns were off-screen on phones in all 19 tables | `test/responsive_widgets_test.dart`: the action button is inside a 360 px screen; the table stays a table at 1200 px |
| 2026-10-02 | Migration `20261002200000_business_report.sql` (`c66a462`): `get_business_report(from, to)` and a matching `get_dashboard_summary` | `FIN-01`, `REP-01`–`REP-04`, S-02, S-03 | pgTAP `17_business_report.test.sql`, 22 of 22: daily, item, category and payment rows each add up to the summary; Manila day boundary; refund-only and expense-only days; stock movement identity |
| 2026-10-02 | Reports screen rebuilt on that report with any date range and copy-to-spreadsheet; Finance Overview reads the same report | `REP-01`–`REP-05`, `FIN-01` | `test/reporting_model_test.dart` and `test/reports_screen_test.dart` (6 tests), including formula-safe export and a 360 px layout check |
| 2026-10-02 | Migration `20261002210000_offline_sales_sync.sql` (`6f0f4c7`): `sync_offline_order` posts a sale made offline under its request ID, dates the order, payment, invoice, stock movements and status history at the time of sale, lets stock go negative for that call only (transaction-local setting `app.offline_sync`, read by the stock guard and by FEFO consumption), and writes an audit row for the sync and another when the till's total differs from the recorded total | Offline till, server side (section 7) | pgTAP `18_offline_sales_sync.test.sql`, 16 of 16; files `01`–`17` unchanged; applied to the hosted test project |
| 2026-10-02 | Offline till in the app: `OfflineOrderRepository` (`lib/data/offline/`) wraps the server repository, keeps the menu, options, payment methods, discounts, open shift and signed-in profile on the device, stores a sale that cannot reach the server and replays it oldest-first under the same request ID; `OfflineStatusBanner` above every page; offline receipt notice; a sign-out warning and a block on closing a shift while sales are unsent | Offline till, app side | `test/offline_order_repository_test.dart` (18 tests) and `test/offline_till_widget_test.dart` (a sale on the real till screen with the server unplugged, then refused, then accepted) |
| 2026-10-02 | `errorText()` in `lib/core/error_text.dart`, used wherever a screen showed `error.toString()` (43 places) | Screens showed class names such as `ClientException: Failed to fetch` when the connection dropped | analyzer and the existing 63 tests; not separately tested |
| 2026-10-02 | Migration `20261002220000_shift_report_and_unused_objects.sql`: `get_shift_report(shift)` and `list_shifts(from, to)`; six unused views and three unused functions dropped | Shift (Z) report, which every commercial POS has and this app lacked; dead-code removal | pgTAP `19_shift_report.test.sql`, 20 of 20; all 19 files pass with it; applied to the hosted test project |
| 2026-10-02 | Shifts screen under Sales & Finance for every role (cashiers see their own shifts); the shift report opens from the list and automatically after a shift is closed, with a copy button | Same | `test/shift_report_test.dart` (5 tests, at 1300 px and 360 px) |
| 2026-10-02 | Dead Dart code removed: five mock repositories and `mock_data.dart` (805 lines), ten repository methods no screen calls, four unused `copyWith` methods and `dialogField` | Requested clean-up; the mocks shipped sample data inside the app | `flutter analyze` clean; 66 tests pass |
| 2026-10-02 | Till details: categories keep the order management set; "Amount Received" follows the total until the cashier types in it; receipts and order details show the size, the chosen options and the note of each line (`OrderLine` widget) | F-11 (rest), `POS-02` (options part), category order after F-18 | analyzer and existing till tests; not separately tested |
| 2026-10-02 | Migration `20261002230000_accounts_and_audit_log.sql`: `bootstrap_first_admin(email)` and a role guard that lets the database owner through; a trigger that keeps at least one active administrator; `profiles.email` follows the sign-in email (existing rows corrected); audit triggers on 11 master-data tables recording only the fields that changed; `get_audit_log(from, to, search)` | `AUTH-01`, S-10, S-11, F-04, S-15, `TRACE-01` | pgTAP `20_accounts_and_audit_log.test.sql`, 19 of 19; applied to the hosted test project; afterwards no profile email differs from its sign-in email |
| 2026-10-02 | Audit Log screen under Administration with date range and search; entries read as plain sentences ("Product size changed: Large · Price: 100.00 → 120.00") | `TRACE-01` | `test/audit_log_test.dart` (4 tests, at 1300 px and 360 px) |
| 2026-10-02 | Migration `20261002240000_reversals_trace_and_supplier_items.sql`: `void_supplier_bill_payment` (a linked negative payment), `void_lot_disposal` (a linked `REVERSAL` movement), the business report takes reversed write-offs off the losses, the transaction trace keeps voided documents with their reason, a trigger records each supplier's package size and latest cost in `supplier_items` (existing receipts backfilled), `check_stock_consistency()` | S-05 (rest), `TRACE-01`, `INV-01`, F-14, S-09 | pgTAP `21_reversals_trace_and_supplier_items.test.sql`, 27 of 27; all 21 files pass; applied to the hosted test project, where the consistency check returns no rows |
| 2026-10-02 | App: Reverse action on write-offs in Stock History; Recent Supplier Payments table with Reverse in Finance Overview; voided and reversed rows marked in Transaction Traceability; receiving and release forms fill in the remembered package size and last cost | Same | `test/reversals_and_package_memory_test.dart` (6 tests). The forms themselves were not exercised by a widget test |
| 2026-10-03 | The app loads the permission codes of the signed-in role and every destination and action checks `profile.can('…')`; `isCashier` is gone (commit "Gate each screen on a named permission") | `SEC-01`: "not a cashier" was treated as "may do everything" | `test/app_user_profile_test.dart` (4 tests): unknown roles and inactive accounts get nothing |
| 2026-10-03 | Migration `20261002250000_business_settings.sql`: `update_business_profile` and `update_shift_cash_rules`; direct writes to `business_profile` and `system_settings` removed | Receipt header and shift cash rules had no way to be edited (section 4.2) | pgTAP `22_business_settings.test.sql`, 12 of 12; all 22 files pass; applied to the hosted test project |
| 2026-10-03 | Business Details screen under Administration; receipts, the sidebar and the offline cache use the saved name, address, phone and TIN (`ReceiptHeader`, `BusinessProfileScope`); starting a shift asks for the opening cash and enforces it when the rule is on | Same; and the till had no way to enter opening cash at all, so turning the rule on would have blocked every shift | `test/business_profile_test.dart` (5 tests, at 1300 px and 360 px) |
| 2026-10-03 | `DataTableCard` never scrolls sideways: when the columns do not fit, each row becomes labelled values, one, two or three across depending on width. Status columns widened; status codes shown as words (`PARTIALLY_PAID` → "Partially Paid"); every dropdown fits its field | Seen live at 1024 px and 1280 px: tables hid their status and action columns behind a sideways scroll on tablets, the target device. F-13, F-16 | `test/responsive_widgets_test.dart` (tablet case added); live at 1024 px and 1280 px |
| 2026-10-03 | One money format everywhere (`₱1,540.50`, `-₱200.00`); receipts carry date and time; order details and receipts show the refunded amount; an ordinary size ("Regular") is not printed after the product name; one-tap cash amounts at payment; products are compact rows on a phone and the phone tab shows the cart count and total; the phone app bar shows the business name | Design pass after the live check | `test/till_helpers_test.dart` (4 tests), `test/till_phone_layout_test.dart` |
| 2026-10-03 | Hold and continue an order on the till (`HeldOrder`, `HeldOrdersStore`): a cart with its table or customer name is set aside on the device and picked up later at the current menu prices; a product removed from the menu meanwhile is left out and reported | Open tickets: a table that is still ordering had to be paid at once or lost | `test/held_orders_test.dart` (3 tests). Device-local by design: nothing is posted, no stock moves and no report shows it until it is paid, and another device cannot see it |
| 2026-10-03 | Copy Receipt on both receipt dialogs (`receiptText`) | A receipt could not leave the screen; printing is undecided (`OPS-02`) | `test/till_helpers_test.dart` |
| 2026-10-03 | `supabase/functions/create-employee/index.ts` assigns the new employee's role through `update_employee_profile` as the requesting administrator, instead of updating `profiles` with the service key | Read of the code against the database guards: `protect_profile_privileges` refuses a role change from a caller with no user, which is what the service key is, so the function would create the sign-in, fail to assign the role, and delete the sign-in again | Deployed on 3 October 2026 (next row). Charlie then created a Cashier account from User Management: the profile is `CASHIER` / `ACTIVE` with its email, and the audit log records Charlie, not a blank actor, as the person who set the role |
| 2026-10-03 | `android/app/src/main/AndroidManifest.xml` declares the `INTERNET` permission; app name set to "Street Bowl Café" on Android, iOS and web instead of `sbc_management_system` / "A new Flutter project." | **Release blocker found by reading the manifests:** only the debug and profile manifests had the permission, so a release build installed on the tablet could not reach the server at all | `flutter build web --release` compiles. The Android build itself was **not run**: no Android SDK on this machine |
| 2026-10-03 | `create-employee` deployed to the test project with `supabase functions deploy create-employee` (asked for by Charlie) | Needed to create Cashier and Manager accounts and test those roles | Function listed as `ACTIVE`, version 1, `verify_jwt` on; a request without a sign-in is refused with 401. Charlie created a Cashier account through it the same day (previous row) |
| 2026-10-03 | `showPrototypeDialog` builds its dialog from plain layout widgets instead of `AlertDialog`; status badges in tables are left-aligned instead of stretched | **Reported by Charlie:** the New Purchase Order form went blank after adding an item. `AlertDialog` measures its content's intrinsic size and the line list uses a `LayoutBuilder`, which cannot be measured; the same applied to every shared dialog with width-adaptive content | Reproduced live, then fixed and re-run live: PO-15 created, approved and received (GR-127, 10 pc, ₱150). Regression test in `test/responsive_widgets_test.dart`. |
| 2026-10-03 | A Material 3 redesign (theme, navigation drawer, shared components; commit `a63527f`) was made and then reverted in full (`57c6d01`) | Charlie did not like the result and is handing the visual design to Claude Design. The app's look is back to the state before that commit | `git diff 5696eee HEAD` is empty for the app; 96 tests pass |
| 2026-10-03 | [HANDOVER.md](HANDOVER.md): summary for Brian of what changed, how to try it, decisions to check, how it was tested and what is open | Charlie asked for a handover to Brian | — |
| 2026-10-03 | Report export as files: Download CSV for the whole report and each section on Reports, and for the filtered list on Transaction Traceability and the Audit Log (`lib/core/export/`). CSV files carry a UTF-8 byte-order mark so Excel shows ₱ and é, quote cells with commas, and neutralise text that starts like a formula. Every copy button (reports, shift report, receipt) now says when copying fails instead of showing nothing | Charlie asked whether export worked. It only copied text to the clipboard, which some browsers refuse silently, and there was no file to download | `test/report_export_test.dart` (5 tests); web release build compiles; live: the download buttons appear and Copy for Sheets wrote to the clipboard. Downloading a file was not clicked in the review browser. On Android the app still copies only: saving or sharing a file there needs a plugin (`share_plus` or similar), which is a dependency decision |

The first three rows are Flutter-only changes; the rest add thirteen database migrations and the app code that uses them. `flutter analyze`: no issues. `flutter test`: 101 passed. pgTAP: 22 files, 439 assertions, all passing in rolled-back trial runs against the hosted test project. The fixes were observed in debug mode on web; a release build and the Android tablet have not been tested.

### Test accounts

Three sign-ins exist on the hosted test project, one per role, all `ACTIVE`:

| Role | Email | Created |
| --- | --- | --- |
| Administrator | demo@demo.com | first-admin bootstrap, 2 October 2026 |
| Cashier | cashier@demo.com | User Management through `create-employee`, 3 October 2026 |
| Manager | manager@demo.com | User Management through `create-employee`, 3 October 2026 |

The passwords are in [TEST_ACCOUNTS.md](TEST_ACCOUNTS.md), committed on purpose so Brian can sign in to the test project in each role at handover (Charlie's decision, 3 October 2026). They work only on the test project and share one password; they must not be reused on a project with real data.

### Live check on 3 October 2026

Run as Administrator against the hosted test project, in the browser pane at 1280 × 800 and 1024 × 768. Each action below was performed in the app and its result read from the screen.

| Checked | Result |
| --- | --- |
| Sale of one Hot Coffee, cash, table T9 | Order `#149` saved; receipt shows the business name and address, date and time, invoice `SI-00000004`. Order numbers jump because rolled-back test runs consume the sequence (see "How the database changes were tested") |
| Shift report for the open shift | Gross ₱1,420, discounts ₱41, refunds ₱162, net ₱1,217; payments Cash ₱1,167 + Other ₱50 = ₱1,217; expected cash ₱1,187 = 0 + 1,329 − 162 + 20. Checked by hand against the orders |
| Supplier payment of ₱200, then reversed | Bill left Payables when paid, returned at ₱200 owed when reversed; both entries listed, marked Reversed and Reversal; the trace shows both with the reason |
| Write-off of 1 Coca-Cola reversed | History shows the original marked Reversed and a +1 Reversal; usable stock 17 → 18 |
| Order for table T5 held, continued, paid with the ₱200 quick-cash button | Held (1) appeared and the cart cleared; Continue restored the line and table; order `#150` saved with ₱200 received and ₱80 change; the receipt shows date and time and offers Copy Receipt |
| Audit Log | Lists sales, the voided release, cash movements and the test category with who and when |
| Business Details, Shifts, Finance, Reports, Traceability, Menu, Discounts, Inventory screens | Load real data without errors at both sizes |
| Second pass after the purchase order report, at 800 px wide | Every form opened and, where marked, posted: purchase order → approve → receive (posted); goods receipt view; release supplies (posted SO-73); lot review and dispose form; inventory count (posted IC-58, no variance); stock adjustment form; add stock item; item details; add supplier; add expense (posted, then voided with a reason); add user form (not submitted: it needs a password); add and edit product; order actions and refund (order #150 refunded in full); cash movement and end shift forms (shift left open) |

Not checked live:

- Cashier and Manager were tested by Charlie on 3 October 2026, not by me. Charlie reported both working; the database shows both accounts active with the right roles.
- Phone width by hand. The browser pane emulates touch below 768 px and its clicks do not reach Flutter; phone layouts are covered by widget tests at 360–375 px only.
- Offline, by cutting the network. Covered by tests with a fake server only.
- A release build, and the Android tablet itself.

### Offline till status

What was built follows the split recommended in section 7: the till sells offline, the back office needs a connection.

How it behaves:

- While online nothing changes: a sale goes straight to the server and gets its order number.
- When the server cannot be reached (no network, a timeout after 15 seconds, a gateway error, an expired sign-in), the sale is stored on the device with its request ID and sale time, the cashier gets a receipt marked "Saved on this device", and the order shows in Orders as **Waiting to Sync** under a reference such as `OFFLINE-3FA91C`.
- The queue is sent every 30 seconds, whenever any till request succeeds again, before each new sale, and on **Send now** in the banner. Sales go oldest first. A new sale never jumps ahead of waiting ones.
- A sale whose answer was lost is queued too. Because it is replayed under the same request ID, the server returns the order it already stored, so it is never recorded twice.
- A sale the server refuses (for example no open shift, or an archived product) stays on the device as **Needs Attention**. The banner turns red and its Review dialog shows the reason with **Send again** and **Remove**. Remove asks for confirmation and deletes the sale from the device only.
- A shift can be opened offline. It is opened on the server, under its own request ID, before the first queued sale is sent.
- The till opens offline for a user who has signed in on that device before: the profile and role are kept on the device, the server still checks every action at sync.
- Stock levels kept on the device are stale, so the cached menu shows "Stock not checked offline" and does not block a sale. The server accepts the sale and stock for that item may go below zero.

Decisions taken, to be confirmed:

| Decision | Chosen | Alternative not taken |
| --- | --- | --- |
| Device storage | `shared_preferences` (already installed as a dependency of the Supabase client; now listed directly) holding JSON | SQLite. It would add a native dependency and a schema to migrate; the queue is a short list and the cache is a few hundred rows |
| Prices | The server re-prices the sale from the current menu and audits any difference from what the till charged (`OFFLINE_SALE_TOTAL_DIFFERENCE`) | Trusting the device's prices. That would let a tampered device set its own prices |
| Receipt numbers | Assigned by the server at sync; the customer's offline receipt carries the `OFFLINE-` reference | Per-device number ranges. Needed only if an official receipt must be printed while offline |
| Age limit | A sale older than 7 days is refused and must be entered by a manager | No limit |

What does not work offline, by design: voids, refunds, cash pay-in and pay-out, closing a shift, and every back-office screen. Each shows "No connection to the server" rather than failing silently.

Not done:

- No screen lists the audit rows for offline sales that oversold stock or whose total differed. They are in `audit_logs` only (see the audit viewer item). *The Audit Log screen added on 3 October 2026 lists them; search for "offline".*
- Offline was verified with a fake server in tests. It was not tested by cutting the network on a real tablet.
- Sales wait on the device of the user who made them. A different user signing in on that device does not see or send them.
- A cash sale re-priced higher than the cash tendered is refused at sync and lands in Needs Attention.

### Accounts, audit and reversals status

Decisions taken, to be confirmed:

| Question | Chosen | Why |
| --- | --- | --- |
| How is a supplier payment undone? | A second, negative payment linked to the first | Every existing total (bill balance, bill status, reports, trace) stays correct with no other change, and nothing is deleted |
| How is a stock write-off undone? | A `REVERSAL` movement linked to the write-off; the report subtracts it on the day of the reversal | Same principle as refunds: history is added to, never edited |
| Can a manual stock adjustment be voided? | No. A wrong adjustment is corrected by another adjustment | An adjustment is already a correction with a reason and an author; a void of a correction adds nothing |
| Who may run the first-admin bootstrap? | Only someone with the database password, in the SQL editor, and only while no active administrator exists | The app must never be able to grant itself administration |
| What is audited? | Sales, refunds, shifts, cash, stock documents (as before) plus every change to products, sizes, options, discounts, payment methods, suppliers, stock items, staff accounts and settings | S-15: price and role changes left no trace |

Not done:

- The audit log has no export and loads at most 1,000 entries per search.
- "Manager authorization" on refunds and discounts is still the signed-in user approving their own action (S-08). It is safe only while cashiers do not hold those permissions, which is the case today.
- Stock availability is still summed from the whole ledger at each sale (S-17). The indexes it needs already exist; a maintained balance is a later change if sales volume makes it slow.

### Dead code removed

How it was found: for Dart, every repository method was checked for a caller in `lib/screens`, `lib/widgets` or `lib/app.dart`, and every public member of a model was deleted on trial and kept deleted only if `flutter analyze` stayed clean. For the database, each public function and view was checked for a reference in the app, in another function's body, in a trigger, in a policy and in another view (query against the hosted project's catalog).

| Removed | Why it was dead |
| --- | --- |
| `lib/data/mock_data.dart`, `mock_expense_repository.dart`, `mock_supplier_repository.dart`, `mock_user_repository.dart`, `mock_inventory_repository.dart` | Nothing in the app used them. Two tests only tested the inventory mock itself; they were removed and the file renamed `test/inventory_models_test.dart` |
| `mock_order_repository.dart` | Used only as a base class by tests. Moved to `test/support/fake_order_repository.dart` without the sample data |
| `OrderRepository.createOrder`, `updateOrder`, `getOrderById` | The Supabase versions threw `UnsupportedError`; no screen called them |
| `ExpenseRepository.getExpenseById`, `InventoryRepository.createInventoryItem` / `updateInventoryItem`, `SupplierRepository.deleteSupplier`, `UserRepository.createUser` / `updateUser` / `deleteUser` | No caller. The screens use the newer methods (`createEmployee`, `updateEmployee`, item creation with initial stock, archive instead of delete) |
| `copyWith` on `UserRecord`, `ExpenseRecord`, `InventoryItem`, `OrderItem`; `dialogField` | No caller |
| Views `v_daily_sales`, `v_product_sales`, `v_product_sales_daily`, `v_daily_profit_estimate`, `v_order_cogs`, `v_shift_summary` | Superseded by `get_business_report` and `get_shift_report`; the profit view showed a figure the business rules forbid. `07_reporting_traceability_alignment.test.sql` read one of them and now reads the business report instead, with the same four expectations |
| Functions `place_order` (first version), `update_order_item_quantity`, `remove_order_item` | An order-editing flow the till never used; checkout is `place_order_v2` only |

Deliberately kept:

- `variant_recipe_components`, `modifier_recipe_components` and the `private.retired_*` functions. AGENTS.md §6 requires a history check before recipe objects are removed, and Brian's own database may hold rows the test project does not. Both tables are empty on the test project.
- `devices`, `invoice_print_events`, `tax_rates`, `credit_notes`: unused today but tied to open business decisions (receipt printing, VAT) or to history.
- `rls_auto_enable()`: not created by any migration in this repository, so it is not ours to drop.
- `AppSpacing` constants that are not referenced yet: design tokens, not logic.
- AGENTS.md said to keep mock repositories under the `MockXRepository` pattern. Its two sentences on this were changed to say test fakes live in `test/support/`. Flag for Brian.

### How the database changes were tested without Docker

Docker is not installed, so `supabase test db` could not run. Instead each migration and test file was executed against the hosted test project with `supabase db query --linked`, inside a transaction that ends in a deliberate error so that nothing is committed. Results on 2 October 2026:

| File | Result |
| --- | --- |
| `10_business_date` and `11_checkout_request_id` (new) | 9 of 9 and 9 of 9 |
| `12_posting_request_ids` (new) | 33 of 33 |
| `13_direct_write_paths` (new) | 13 of 13 (10 of 13 fail before its migration) |
| `14_auditable_edits_and_voids` (new) | 39 of 39 |
| `15_category_and_discount_management` (new) | 41 of 41 |
| `16_modifier_management` (new) | 23 of 23 |
| `17_business_report` (new) | 22 of 22 |
| `01`, `04`, `05`, `06`, `07`, `09` with the new migrations | all assertions pass (22, 12, 10, 13, 12, 14) |
| `02`, `03` with the new migrations | pass (35, 20) once the `TEST` rows from section 3a are removed inside the transaction; on the populated database they fail before and after the migrations, because they select "the latest" refund item or stock-out by random UUID order |
| `08_api_security_hardening` | 17 of 18, before and after: see S-19 |

This is equivalent in content to the CI run but is not the CI run. Database CI has not executed for these changes.

Side effect: identity sequences do not roll back, so these trial runs consumed order numbers 2 to 7 on the test project. The next real order was `#8`.

| ID | Finding | Status |
| --- | --- | --- |
| S-19 | *(Fixed 2 October 2026 in `20261002160000`.)* On the hosted project, `authenticated` could execute `set_updated_at()`. The repository's own test 10 in `08_api_security_hardening` therefore fails there. Low risk: it is a trigger function and cannot be called through the API, but the hosted project's default privileges differ from the local CI database, so "passes in CI" does not prove the hosted grants. | found |
| S-20 | pgTAP files `02` and `03` pick rows with `order by id desc limit 1` on random UUIDs. They are only reliable on an empty database. | found |

### Report definitions (FIN-01) — decided on 2 October 2026, to be confirmed by management

Charlie asked for industry-standard choices to be made so work could continue. These are the definitions now used by the Dashboard, Finance Overview and Reports. They follow what commercial POS systems report. They are a recommendation that the café and Brian should confirm; changing one later means changing one database function.

| Measure | Definition |
| --- | --- |
| Gross sales | Completed sales at menu prices, including priced modifiers, before discounts |
| Discounts | Discounts given on those sales |
| Refunds | Money refunded, counted on the day the refund was made |
| Net sales | Gross sales − discounts − refunds |
| Average order | (Gross sales − discounts) ÷ completed orders |
| Business day | The calendar day in the café's time zone (`business_profile.timezone`, Asia/Manila) |
| Expenses | Posted expenses by their expense date |
| Net sales less expenses | Exactly that. It is labelled as not being profit, because it leaves out stock purchases and losses |
| Stock received, paid to suppliers, cost of stock lost | Shown beside sales, never added to expenses or to each other |

A sale on Monday that is refunded on Tuesday is a Monday sale and a Tuesday refund. The Refunds table shows the original sale day for each refund.

Export: every table, and the whole report, can be copied as tab-separated text and pasted into Google Sheets or Excel. This is the "importable export" the README names as the minimum. There is no file download and no direct Sheets synchronisation (`OPS-04`).

Not done in reporting:

- The older views `v_daily_sales`, `v_product_sales_daily`, `v_product_sales`, `v_daily_profit_estimate`, `v_order_cogs` and `v_shift_summary` used the old definitions. They were dropped in `20261002220000` (see "Dead code removed").
- "Today" and the other presets use the device's date. On a device set to another time zone they would differ from the café's day.
- Transaction Traceability is unchanged: last 30 days, 500 rows, posted documents only (`TRACE-01`). *Voided and reversed documents were added on 3 October 2026; the 30-day and 500-row limits remain.*
- No shift (end-of-day) report yet.

### CAT-01 and DIS-01 status

What management can now do without a developer:

- **Categories** (Menu & Products → Categories): add, rename, move up or down, archive and reactivate menu, inventory and expense categories. Names are unique ignoring case and spaces. Archiving a category that is in use is allowed and says how many records use it; those records keep the category, and it stops being offered for new ones. Nothing is reassigned or deleted.
- **Discounts** (Menu & Products → Discounts): add and edit promotions as a percentage or an amount, decide whether the till may change the value and up to what limit, set optional start and end dates, and switch a promotion off. The server applies a fixed promotion's own value whatever the till sends.

Found while doing this:

| ID | Finding | Status |
| --- | --- | --- |
| F-18 | Every list in the app was sorted in reverse. The Supabase client's `.order(column)` is descending unless `ascending: true` is passed, and 32 queries gave no direction. Effects seen earlier in this log: the till listed categories backwards, and the payment method list started with "Other" instead of Cash (part of F-11). | changed (`a8fa006`) |

Decisions left for Brian and the café, not made here:

- **Who may apply a discount.** Unchanged: it needs `discounts.apply`, and every promotion requires an authoriser with `discounts.manage`. Cashiers hold neither, so a cashier is still offered no discounts. New promotions follow the same rule. Opening discounts to cashiers, with or without a manager's approval at the till, is a business decision (`DIS-01`).
- **Statutory discounts** (Senior, PWD) cannot be enabled for the till or edited, by a database constraint, until the tax rules are confirmed (`OPS-03`).

Not done:

- The category chips at the till are still sorted alphabetically in the app; the products under them follow the managed order.
- A category with no active items does not appear as a chip at the till, because chips are built from the products on sale.
- Discount totals are not in reports yet. That waits on the report definitions (`FIN-01`, `REP-02`).
- "Amount Received" at payment still does not follow the total when a discount value is typed (rest of F-11). *Addressed 3 October 2026.*

### S-04 and S-05 status

How a void works: nothing is deleted. The function posts `REVERSAL` movements against the same lots the original movements touched, marks the document (`VOIDED` for releases, `CANCELLED` for counts and receipts) with the reason, the user and the time, and writes an audit row.

Rules that limit a void, each covered by a test:

- A goods receipt can be voided only while all the stock it added is still in its lots and its supplier bill has no payments. The unpaid bill is voided with it, a linked purchase order returns to the status its remaining receipts justify, and the supplier invoice number becomes available again.
- A count can be voided only while any stock it added is still there.
- A release can always be voided while it is posted.
- Voiding needs `inventory.adjust` (releases, counts) or `purchases.manage` (receipts). A cashier is refused.

Not done:

- **Disposals, manual adjustments and supplier bill payments still have no reversal.** A wrong disposal has to be corrected with a manual stock-in. *Addressed 3 October 2026 for disposals and supplier payments; adjustments are corrected by another adjustment (see "Accounts, audit and reversals status").*
- **Voided documents drop out of Transaction Traceability**, which lists only posted documents. The void is in the audit log and the inventory history, but management cannot see it in the trace screen (`TRACE-01`). *Addressed 3 October 2026.*
- **Posted expenses can still be edited**, now with a before-and-after audit row. Nothing in the app shows that history, and there is no rule yet for who may edit after posting.
- **`update_menu_variant` still overwrites every field it is given.** The menu form always sends them all, so nothing is lost today, but it is the same pattern as the supplier defect.
- **The void buttons sit in the last table column**, which is off-screen at phone width (same problem as F-15).
- **Existing suppliers created before this change** have their phone in the right column but no other details; nothing needed migrating on the test project.

### What S-14 did not change

- **Master data can still be created and edited directly** by an account with the matching permission (menu, suppliers, inventory items, categories, settings, roles). Only deleting it is closed. The app itself uses one such path: archiving an inventory item.
- **`profiles` keeps its direct update policy** for accounts with `users.manage`. Role changes are still guarded by a trigger, but the self-deactivation check in `update_employee_profile` can be bypassed this way.
- **Functions can still edit posted rows.** `update_expense` changing a posted amount without history (S-04) is a function, not a direct write, and is unchanged.
- **No trigger makes posted rows immutable.** The protection is the absence of client privileges, which is enough for the API but not against a future function that edits history.
- **`invoice_print_events` keeps its client insert policy**, by design, for print auditing.

### S-06 status

Every function that posts a sale, a payment, a refund, a stock movement, a shift event or an expense now accepts a request ID, and the app sends one.

Limits that remain:

- **The ID lives in memory.** Checkout keeps it in the POS screen; other forms create one when they open. Reloading the page, or closing a form and opening it again, starts a new ID. Offline selling (section 7) needs IDs stored on the device.
- **Only the POS screen tells the cashier what happened** after a lost response. The other forms simply become safe to save again; they do not yet explain that the first attempt may have been saved (`UX-04`).
- **Concurrency is untested.** Each function takes an advisory lock per request so two simultaneous submissions queue, but that needs two database sessions to prove and was not exercised.
- **`void_order`, `approve_refund_item_restock`, `approve_purchase_order` and the master-data functions have no request ID.** The first three already refuse a second application; master-data edits are repeatable without harm.
- **`client_requests` grows without limit.** One small row per posted request; it needs a retention rule before long-term use.
- The request log returns the stored document on replay even if it has since changed, for example a shift that was later closed.

## 6. SQL audit (all 38 migrations, 10,852 lines, read in full on 2 October 2026)

The schema is stronger than the app built on it: UUID keys, name and price snapshots on order lines, `numeric` money, lot-level FEFO, a stock ledger, permission-checked `SECURITY DEFINER` functions and a default-deny API. The findings below are what stands between that and a system a café can rely on. Nothing here has been changed yet.

### 6.1 Correctness and data integrity

| ID | Finding | Where | Recommendation |
| --- | --- | --- | --- |
| S-01 | *(Addressed 2 October 2026, see section 5.)* **Business dates used the server's UTC date.** `current_date` decides expiry (usable vs expired) and is the default for expense and supplier-bill dates. Manila is UTC+8, so between midnight and 8 a.m. the database is still on yesterday. The dashboard, by contrast, converts to Asia/Manila correctly. | `consume_inventory_fefo`, `create_and_post_stock_out`, `v_inventory_stock`, `v_inventory_catalog`, `approve_refund_item_restock`, `create_expense`, `create_and_post_goods_receipt` | One `business_today()` helper reading `business_profile.timezone`; replace every `current_date`. |
| S-02 | **Refunds are dated two ways.** `v_daily_sales` and `v_product_sales_daily` subtract a refund on the original sale date; `get_dashboard_summary` subtracts it on the refund date. | views vs function | Pick one basis with management and label the other explicitly (`FIN-01`). |
| S-03 | **"Gross sales" is already net of discounts** (`sum(total_amount)`), and no view exposes pre-discount sales or discount totals. | `v_daily_sales`, `get_dashboard_summary` | Report `subtotal`, `discount_amount`, `total_amount`, refunds and net separately (`FIN-01`, `REP-02`). |
| S-04 | *(Addressed for expenses and suppliers 2 October 2026; see "S-04 and S-05 status".)* **Posted records were edited in place.** `update_expense` can change the amount, date and supplier of a posted expense with no history; `void_expense` needs no reason and records no actor or time; `update_supplier` and `update_menu_variant` overwrite every column, including ones the caller did not send. | `20260930142754`, `20260922183339`, `20260923002740` | Patch semantics (`coalesce` to the existing value), plus an audit row for every change to a posted record (`SUP-01`). |
| S-05 | *(Addressed for receipts, releases and counts 2 October 2026; see "S-04 and S-05 status".)* **Posted stock and purchasing documents could not be corrected.** Statuses `CANCELLED`/`VOIDED`/`VOID` exist for goods receipts, stock-outs and supplier bills, but no function sets them, and counts, disposals and supplier payments have no reversal at all. | whole schema | Reversal functions that post opposite ledger movements and keep the original (`INV-02`). |
| S-06 | *(Addressed 2 October 2026, see section 5.)* **Only checkout was retry-safe, and the app did not use it.** `orders.client_request_id` and `payments.idempotency_key` exist; refunds, stock-outs, counts, disposals, shift start/end, cash movements and supplier payments have no request key. Receipts and expenses are protected indirectly by the duplicate supplier-reference check. | all mutating RPCs | A request-ID parameter and unique column on every posting function (`POS-01`). Required for offline. |
| S-07 | **A modifier group name can exist only once in the whole system** (`modifier_groups.name unique`), and `create_modifier_group_for_menu_item` always creates a new group. A second product cannot have its own "Size" or "Add-ons" group, and groups cannot be shared. | `20260922130003`, `20260923005301` | Drop the global uniqueness or add an "attach existing group" function (`MOD-01`). |
| S-08 | **"Manager authorization" is self-authorization.** `process_refund_items` and `place_order_v2` pass `auth.uid()` as `authorized_by`; the guard triggers only check that this user holds the permission. | `20260923011712`, `20260923013054` | Acceptable only if cashiers never hold `orders.refund`/`discounts.apply`. For cashier-initiated refunds, add a second-person approval (manager PIN) (`DIS-01`, `SEC-01`). |
| S-09 | **Two sources of stock truth.** On-hand is the sum of `stock_movements`; usable and expired are sums of `inventory_lots.remaining_quantity`. Nothing checks that they agree. | `v_inventory_stock` | A reconciliation check in the pgTAP suite and a scheduled query; or derive both from lots. |
| S-10 | **The first admin cannot be created the documented way**, and an admin can change their own role and lock the system out of administration. | `protect_profile_privileges`, `update_employee_profile` | A one-time bootstrap function and a "last active admin" guard (`AUTH-01`). |
| S-11 | `profiles.email` is copied from `auth.users` only on insert. | `handle_new_auth_user` | Also sync on email change. |
| S-12 | Migrations `20260923012529` and `20260923013054` are identical, and several schema migrations edit demo rows by SKU (`PRD-005`, `PRD-006`, `PRD-008`, `INV-001`). `seed.sql` creates products and opening stock although it is described as reference data. | migrations, seed | Leave applied migrations alone; for the café's real setup, split reference data from sample data (`DOC-01`). |
| S-13 | *(Discount codes addressed 2 October 2026; the `CASH` code remains.)* Discount codes (`PROMO_PERCENT`, `PROMO_FIXED`, `MANUAL`) and the cash method code (`CASH`) were hard-coded inside functions. | `place_order_v2`, `get_pos_discount_types`, `end_shift` | A flag column (`is_pos_enabled`, `is_cash`) instead of literals, so management can add a discount without a migration (`DIS-01`). |

### 6.2 Security

| ID | Finding | Recommendation |
| --- | --- | --- |
| S-14 | *(Addressed 2 October 2026, see section 5.)* **Financial history could be hard-deleted through the API.** The original `FOR ALL` management policies were split into insert/update/delete policies, so an account with the matching permission can `DELETE` or directly `UPDATE` rows in `expenses`, `purchase_orders`, `supplier_bills`, `stock_counts`, `shifts`, `invoice_sequences`, `system_settings` and the menu tables without going through any function. The app does not do this, but the database allows it. | Remove update/delete policies from transactional tables; keep writes behind functions; add triggers that reject changes to posted rows. |
| S-15 | **The audit trail is thin and unreadable.** `audit_logs` records about a dozen events (shift, checkout, refund, receipt, stock-out, count, restock). It records nothing for price or menu changes, user role or status changes, expense edits, supplier edits or settings, and no screen reads it. | Audit triggers on master data and posted records; a management audit view (`TRACE-01`). |
| S-16 | *(Addressed for transactional tables 2 October 2026.)* `authenticated` still held table-level `select, insert, update, delete` on every table that existed at migration `0007`; only RLS stands between a signed-in user and each table. The final default-deny migration tightened `anon` and future objects, not these. | Revoke write grants on tables that are function-only. |

### 6.3 Performance

| ID | Finding | Recommendation |
| --- | --- | --- |
| S-17 | **Stock availability is recomputed from the whole ledger on every use.** `v_inventory_stock` sums all of `stock_movements`; `v_pos_menu` joins it; and `guard_order_item_stock_availability` queries `v_pos_menu` once per order line during checkout. Fine today, slower every month. | A maintained per-item balance, or compute usable stock from open lots only. |
| S-18 | `next_invoice_number` locks a single row, so every checkout queues behind it. Fine for one till; incompatible with offline devices. | Per-device sequences (section 7). |

### 6.4 Missing objects (confirmed by the full read)

Category management functions (`CAT-01`); discount-type management (`DIS-01`); any writer for `supplier_items` (`INV-01`); editing for `business_profile` and `system_settings`; an audit reader (`TRACE-01`); date-range report functions and exports (`REP-01`–`REP-05`); a shift report (`v_shift_summary` exists but is unused); reversal functions (S-05).

## 7. Offline operation (requirement set by Charlie on 2 October 2026)

This changes the documented baseline: README and AGENTS.md treat offline as outside scope pending its own decision (`OPS-02`). It is recorded here as a decision to confirm with Brian and the café before build work starts.

Why the current design cannot work offline: every sale is one online function call; the server assigns the order number, the invoice number and all timestamps with `now()`; prices are re-read from the live menu when the order is inserted; a shift must be open on the server at that moment; and insufficient stock rejects the sale.

Recommended scope, which is also how Loyverse divides it: **the till works offline; the back office stays online.** Selling, payments, shift open/close and cash movements are queued on the device. Purchasing, counts, expenses, menu editing, users and reports need a connection.

What it takes:

| Area | Change |
| --- | --- |
| Device storage | A local database on the tablet (SQLite) holding the menu, modifiers, discounts, payment methods and a stock snapshot, plus an outbox of unsent transactions. This adds a dependency and a local data layer, which AGENTS.md §2 says needs a team decision. |
| Identity of records | The device creates the UUIDs for orders, lines and payments. A new `sync_order(jsonb)` function accepts them and is idempotent on `client_request_id`. |
| Time | Functions accept the device's `occurred_at`; `completed_at` stops being `now()`. |
| Prices | The server accepts the price and discount the customer was actually charged, validates them against the menu version, and flags differences instead of re-pricing. |
| Numbering | Register devices (`devices` table already exists) and number receipts per device, for example `T1-000123`; `invoice_sequences` gains a device column. |
| Stock | A sale already made offline cannot be refused. The sync accepts it, lets stock go negative for that item and lists it for a manager to resolve. |
| Shifts and cash | Shift open, close and cash movements carry device timestamps and request IDs; the sync must accept an order whose shift has since closed. |
| Sign-in | A cached session and a local PIN so a cashier can open the till without a connection; cached permissions; server remains the authority at sync. |
| Master data sync | `updated_at` and soft-delete markers on every reference table (several have neither today) so the device can fetch only what changed. |
| User-visible state | "Offline, 3 sales waiting", sync progress, and a manager list of sales that synced with differences. |
| Tests | Lost-connection checkout, duplicate sync, two devices selling the last item, clock skew, shift closed before sync. |

Order of work: S-06 (request IDs) and S-01 (business time) come first because offline depends on both.

## 8. Compared with a commercial POS (Loyverse)

Left column: where the app stood on 2 October 2026 before this work. Right column: where it stands now.

| Capability | Loyverse | Before | Now |
| --- | --- | --- | --- |
| Sell offline and sync later | yes | no | yes for sales and opening a shift; voids, refunds, cash movements and closing need a connection |
| Items, variants, modifiers | yes | yes, with limits | yes; shared modifier groups, reordering |
| Category management | yes | read-only | yes |
| Discounts managed by the owner | yes | three hard-coded types | yes, with fixed or adjustable values, limits and validity dates. Senior and PWD discounts stay off until the tax rules are confirmed |
| Receipt showing discounts and modifiers | yes | no discount line, no options | yes, with business header, date and time, and a copy-as-text button. No printing or email (`OPS-02`) |
| Open tickets (save and pay later) | yes | no | partly: an order can be held on the device and continued; it is not shared between devices and not recorded until paid |
| Split payments | yes | no | no. Switched off in settings |
| Shift open and close with cash report | yes | no report, no opening cash | yes: opening cash, shift report, shift history |
| Sales reports, any date range, export | yes | 7 or 30 days, top 10, no export | yes: by day, item, category, payment, discount, employee; copy to a spreadsheet. No file download |
| Stock tracking, purchase orders, counts | paid add-on | yes, no corrections | yes, with voids and reversals for every posted document |
| Audit trail readable by the owner | partly | written, never readable | yes, including price, role and settings changes |
| Employee PIN sign-in | yes | no | no. Email and password only |
| Customers and loyalty | yes | out of scope | out of scope |
| Multiple stores | yes | out of scope | out of scope |
| Lot-level expiry (FEFO), supplier bills and payables, expenses | no | yes | yes |

## 9. What is still open

Business decisions (cannot be settled in code):

1. Confirm the report definitions (gross before discounts; refunds on the refund date).
2. Senior citizen and PWD discounts, VAT status and what an official receipt must show (`OPS-03`). Until then statutory discounts are disabled and `tax_rates` is unused.
3. Whether cashiers may give discounts or refunds. Today they cannot; if they may, a second-person approval is needed (S-08).
4. Whether receipts must be printed, and on what printer (`OPS-02`).
5. Whether the offline decisions in "Offline till status" are acceptable, especially server re-pricing and server-assigned receipt numbers.
6. Whether the retired recipe tables may be dropped (needs Brian's history check).

Technical work not done:

1. Done 3 October 2026: Cashier and Manager accounts were created through `create-employee` and tested by Charlie. Still worth running once as the Cashier: a full shift (open with cash, sell, cash movement, close, shift report).
2. Build the Android release and test it on the tablet, including a real loss of network. The web release build compiles; the Android build has never been run here (no Android SDK). Before publishing, replace the application ID `com.example.sbc_management_system` and set up release signing.
3. Run CI. The GitHub workflow has never run for this branch because local Docker is not installed; the same pgTAP files were run against the hosted project instead.
4. Open tickets shared between devices (held orders are on one device only), split payments, PIN sign-in, receipt printing, file export of reports.
5. A maintained stock balance (S-17), per-device invoice numbering (S-18), a scheduled run of `check_stock_consistency()`.
6. Existing pgTAP files `02` and `03` still depend on an empty database (S-20).
7. Split reference data from sample data in `seed.sql` before the café's real setup (`DOC-01`, S-12). The hosted test project contains test rows named `TEST …` from this work.
