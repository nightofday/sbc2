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
| `create-employee` Edge Function | not deployed | staff accounts cannot yet be created from the app |

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
| `v_daily_profit_estimate`, `v_order_cogs` | Read by nothing. The first presents a "profit" figure the business rules say must not be shown as profit. | Drop or replace when `FIN-01` defines the measures. |
| `v_product_sales`, `v_low_stock`, `v_expiring_inventory_lots`, `v_shift_summary` | Read by neither the app nor other SQL. | Either wire into reports (`REP-02`, `REP-04`) or drop. |
| `credit_notes` | Written by the refund functions, never read. | Keep (history); surface in order/refund detail (`POS-02`). |

### 4.2 Needed but missing

| Gap | Evidence | Task |
| --- | --- | --- |
| No functions to create, rename, reorder or archive menu, inventory or expense categories | No category function exists in any migration | `CAT-01` |
| No functions to manage discount types | Only `get_pos_discount_types` exists | `DIS-01` |
| Nothing ever writes `supplier_items` | Zero inserts in migrations; the app only reads it | `INV-01`, `PUR-01` |
| No way to read `audit_logs` | 13 write sites, no view, function or screen | `TRACE-01` |
| No screen or function to edit `business_profile` or `system_settings` | Seeded once, read by a few functions | new; raise with Brian |
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

The first three rows are Flutter-only changes; the rest add four database migrations and the app code that uses them. `flutter analyze`: no issues. `flutter test`: 28 passed. The fixes were observed in debug mode on web; a release build and the Android tablet have not been tested.

### How the database changes were tested without Docker

Docker is not installed, so `supabase test db` could not run. Instead each migration and test file was executed against the hosted test project with `supabase db query --linked`, inside a transaction that ends in a deliberate error so that nothing is committed. Results on 2 October 2026:

| File | Result |
| --- | --- |
| `10_business_date` and `11_checkout_request_id` (new) | 9 of 9 and 9 of 9 |
| `12_posting_request_ids` (new) | 33 of 33 |
| `01`, `04`, `05`, `06`, `07`, `09` with the new migrations | all assertions pass (22, 12, 10, 13, 12, 14) |
| `02`, `03` with the new migrations | pass (35, 20) once the `TEST` rows from section 3a are removed inside the transaction; on the populated database they fail before and after the migrations, because they select "the latest" refund item or stock-out by random UUID order |
| `08_api_security_hardening` | 17 of 18, before and after: see S-19 |

This is equivalent in content to the CI run but is not the CI run. Database CI has not executed for these changes.

Side effect: identity sequences do not roll back, so these trial runs consumed order numbers 2 to 7 on the test project. The next real order was `#8`.

| ID | Finding | Status |
| --- | --- | --- |
| S-19 | *(Fixed 2 October 2026 in `20261002160000`.)* On the hosted project, `authenticated` could execute `set_updated_at()`. The repository's own test 10 in `08_api_security_hardening` therefore fails there. Low risk: it is a trigger function and cannot be called through the API, but the hosted project's default privileges differ from the local CI database, so "passes in CI" does not prove the hosted grants. | found |
| S-20 | pgTAP files `02` and `03` pick rows with `order by id desc limit 1` on random UUIDs. They are only reliable on an empty database. | found |

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
| S-04 | **Posted records are edited in place.** `update_expense` can change the amount, date and supplier of a posted expense with no history; `void_expense` needs no reason and records no actor or time; `update_supplier` and `update_menu_variant` overwrite every column, including ones the caller did not send. | `20260930142754`, `20260922183339`, `20260923002740` | Patch semantics (`coalesce` to the existing value), plus an audit row for every change to a posted record (`SUP-01`). |
| S-05 | **Posted stock and purchasing documents cannot be corrected.** Statuses `CANCELLED`/`VOIDED`/`VOID` exist for goods receipts, stock-outs and supplier bills, but no function sets them, and counts, disposals and supplier payments have no reversal at all. | whole schema | Reversal functions that post opposite ledger movements and keep the original (`INV-02`). |
| S-06 | *(Addressed 2 October 2026, see section 5.)* **Only checkout was retry-safe, and the app did not use it.** `orders.client_request_id` and `payments.idempotency_key` exist; refunds, stock-outs, counts, disposals, shift start/end, cash movements and supplier payments have no request key. Receipts and expenses are protected indirectly by the duplicate supplier-reference check. | all mutating RPCs | A request-ID parameter and unique column on every posting function (`POS-01`). Required for offline. |
| S-07 | **A modifier group name can exist only once in the whole system** (`modifier_groups.name unique`), and `create_modifier_group_for_menu_item` always creates a new group. A second product cannot have its own "Size" or "Add-ons" group, and groups cannot be shared. | `20260922130003`, `20260923005301` | Drop the global uniqueness or add an "attach existing group" function (`MOD-01`). |
| S-08 | **"Manager authorization" is self-authorization.** `process_refund_items` and `place_order_v2` pass `auth.uid()` as `authorized_by`; the guard triggers only check that this user holds the permission. | `20260923011712`, `20260923013054` | Acceptable only if cashiers never hold `orders.refund`/`discounts.apply`. For cashier-initiated refunds, add a second-person approval (manager PIN) (`DIS-01`, `SEC-01`). |
| S-09 | **Two sources of stock truth.** On-hand is the sum of `stock_movements`; usable and expired are sums of `inventory_lots.remaining_quantity`. Nothing checks that they agree. | `v_inventory_stock` | A reconciliation check in the pgTAP suite and a scheduled query; or derive both from lots. |
| S-10 | **The first admin cannot be created the documented way**, and an admin can change their own role and lock the system out of administration. | `protect_profile_privileges`, `update_employee_profile` | A one-time bootstrap function and a "last active admin" guard (`AUTH-01`). |
| S-11 | `profiles.email` is copied from `auth.users` only on insert. | `handle_new_auth_user` | Also sync on email change. |
| S-12 | Migrations `20260923012529` and `20260923013054` are identical, and several schema migrations edit demo rows by SKU (`PRD-005`, `PRD-006`, `PRD-008`, `INV-001`). `seed.sql` creates products and opening stock although it is described as reference data. | migrations, seed | Leave applied migrations alone; for the café's real setup, split reference data from sample data (`DOC-01`). |
| S-13 | Discount codes (`PROMO_PERCENT`, `PROMO_FIXED`, `MANUAL`) and the cash method code (`CASH`) are hard-coded inside functions. | `place_order_v2`, `get_pos_discount_types`, `end_shift` | A flag column (`is_pos_enabled`, `is_cash`) instead of literals, so management can add a discount without a migration (`DIS-01`). |

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

| Capability | Loyverse | This app today |
| --- | --- | --- |
| Sell offline and sync later | yes | no (section 7) |
| Items, variants, modifiers | yes | yes; modifier groups cannot share a name (S-07) |
| Category management | yes | read-only (`CAT-01`) |
| Discounts managed by the owner | yes | three hard-coded types, no management screen (`DIS-01`) |
| Receipt showing discounts and modifiers; print or email | yes | on-screen only, discount line missing (F-08, `POS-02`, `OPS-02`) |
| Open tickets (save an order and pay later) | yes | schema supports `OPEN` orders; the app always pays immediately |
| Split payments | yes | schema supports it; switched off |
| Shift open/close with cash report | yes | open, close and cash movements exist; no shift report |
| Sales reports by item, category, employee, payment type, discount; any date range; export | yes | last 7 or 30 days, top 10 products, no export (`REP-01`–`REP-05`) |
| Stock tracking, low-stock list, purchase orders, counts | paid add-on | present; no low-stock or loss report, no corrections (S-05) |
| Employee PIN sign-in and per-employee sales | yes | email and password only |
| Customers and loyalty | yes | deliberately outside the baseline |
| Multiple stores | yes | deliberately single-branch |
| Lot-level expiry (FEFO), supplier bills and payables, expense records | no | yes — this is where the app already does more |

