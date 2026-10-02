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
| F-05 | In New Order, the cart showed Chocolate Cake × 4 while the app warned "only has 2 available". Whether checkout rejects it has not been tested. | found, unverified | `POS-01` |

Not covered yet: any transaction (sale, refund, receiving, release, disposal, count, expense), tablet and desktop layouts, Cashier and Manager logins.

## 4. Database schema review (first pass)

Method: counted, for each of the 53 public tables and 26 views, the references in `lib/`, in the combined migration SQL (inserts, updates, reads) and in the pgTAP tests, then read the definitions of the outliers. This is a usage review of the migration text, not a full audit, and nothing has been dropped.

### 4.1 Present but unused — candidates to remove or to finish

| Object | What the review found | Recommendation |
| --- | --- | --- |
| `devices` | No reads or writes anywhere. Six foreign-key columns on other tables point to it. | Decide with `OPS-02` (offline/printing). Drop with its six columns if device tracking is declined; otherwise leave. |
| `invoice_print_events` | No reads or writes anywhere. | Same decision as `devices`. |
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

No application code or database schema has been changed yet.
