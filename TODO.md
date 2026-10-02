# Business-readiness backlog

Reviewed **2 October 2026, Asia/Manila** against `brian/inventory-workflow-navigation` commit `d55ce33059a8206c035203dc932052cef3424f09`. The requirements reference was refreshed to `IT12_M3_Angga_Ayco_Briones (1).pdf` (29 pages, uploaded 2 October 2026). Source and requirements provenance are in [README.md](README.md). The source-code audit remains at the same commit; the document refresh is not a new runtime test. This is a source-based assessment, not a completed user-acceptance test or exhaustive security audit.

**All tasks below are open.** Checkboxes represent accepted outcomes, not whether related code exists. The review did not rerun Flutter, database tests, or the live application; those runtimes were unavailable in this review environment. No application or database changes are included in this documentation update.

## How to use this backlog

- **P0:** correctness/data-integrity risks to address before wider transaction testing.
- **P1:** required before claiming baseline business readiness.
- **P2:** conditional requirement or later improvement; settle the decision before release if the café depends on it.
- **Confirmed gap:** absent/incomplete in inspected source. **Source defect/risk:** concrete problematic code path; reproduce with a focused test. **Validation:** decision or behavior requiring evidence; not an assertion that it is broken.
- Close a task only with its requirement ID, implementation commit, automated/manual evidence, and reviewer. Record blockers explicitly. Do not turn a failed or unrun test into a pass.
- Start each implementation with [AGENTS.md](AGENTS.md). Scope changes to one coherent task or dependent group; preserve repositories, models, shared theme, and database transaction boundaries.

## Evidence index

Paths are relative to the repository. Search the named symbol as files evolve.

| Key | Inspected evidence |
| --- | --- |
| E01 | `lib/domain/repositories/{menu,inventory,expense}_repository.dart`: category reads but no category maintenance methods. Corresponding Supabase repositories read category tables. |
| E02 | `lib/screens/menu/menu_management_screen.dart`: `_showModifiers`, `_showModifierGroupEditor`, `_showModifierEditor`; `supabase_menu_repository.dart`: creation/update RPCs. |
| E03 | `lib/screens/orders/new_order_screen.dart`: promotional discount controls at payment; `supabase/migrations/20260923013054_pos_promotional_discounts.sql`: `get_pos_discount_types` restricts codes; `supabase/seed.sql`: cashier lacks `discounts.apply`. |
| E04 | `lib/screens/reports/reports_screen.dart`, `lib/models/reporting.dart`, `lib/data/repositories/supabase_reporting_repository.dart`: 7/30-day summaries, top 10 products, three inventory counters, no report export implementation found in `lib/` or `web/`. |
| E05 | `lib/screens/inventory/inventory_screen.dart`: history loads 250 movements and release list 100 records; item detail uses recent movements. `inventory_count_screen.dart` loads 100 counts. |
| E06 | `supabase_reporting_repository.dart`: transaction trace limit 500; `transaction_traceability_screen.dart`: local filtering and explicit recent-record subtitle. |
| E07 | `supabase/migrations/20260922130006_views.sql`: `v_daily_sales`; `20260930161554_reporting_traceability_alignment.sql`: `v_product_sales_daily`; `20260922183308_menu_cleanup_and_dashboard_summary.sql`: `get_dashboard_summary`. |
| E08 | `lib/data/repositories/supabase_order_repository.dart`: `placeOrder` sends null `p_client_request_id`; `_orderFromMap` loses variant/modifier/discount details; `lib/models/order_item.dart`: line total is unit price × quantity. |
| E09 | `lib/data/repositories/supabase_supplier_repository.dart`: `updateSupplier` sends null contact/email/address, zero terms, composite contact as phone; `20260922183339_expense_and_supplier_flutter_rpcs.sql`: `update_supplier` writes those values. |
| E10 | `lib/app.dart`, `lib/models/app_user_profile.dart`, `lib/screens/auth/auth_gate.dart`, `supabase/seed.sql`, `supabase/functions/create-employee/index.ts`: navigation vs. backend role/permission behavior. |
| E11 | `lib/core/state/business_refresh_controller.dart`, `inventory_refresh_controller.dart`, `lib/app.dart`, and `purchasing_screen.dart`: in-process refresh notifications and screen wiring. |
| E12 | `lib/widgets/common/{responsive_filter_bar,data_table_card,app_dialog,summary_card}.dart`, `lib/widgets/layout/{app_shell,app_page}.dart`, `test/responsive_widgets_test.dart`: shared responsiveness and three helper-widget scenarios. |
| E13 | `lib/main.dart`, `web/index.html`, `lib/screens/auth/login_screen.dart`: initialization before `runApp`, default web bootstrap, sign-in form. |
| E14 | `supabase/migrations/20260930142754_align_pos_menu_expense_workflow.sql`: prepared-item availability and expense validation; `20260929052203_align_practical_inventory_workflow.sql`: practical stock/expense rules. |
| E15 | `lib/domain/repositories/purchasing_repository.dart`, `supabase_purchasing_repository.dart`, `purchasing_screen.dart`: receiving contracts and manual package conversion; supplier-item mapping lives in the database. |
| E16 | `test/`, `supabase/tests/database/`, `.github/workflows/`: model/helper tests, pgTAP coverage, CI configuration. |

## Audit conclusions

| Concern | Finding |
| --- | --- |
| Categories cannot be created | Confirmed gap. Database category reads and filters exist; management workflow is missing. |
| Modifiers cannot be created | Creation/editing exists behind a menu row action. Treat this as a discoverability/completeness problem and validate access; do not build a duplicate backend. |
| Discounts are missing | Promotional application exists, but management UI is missing and cashier permission is intentionally absent in the seed. Confirm the approval policy before exposing it. |
| No stock history | History and per-item recent movements exist. Completeness, pagination, drill-down, and export are the gaps. |
| Expired/damaged reporting | Lot disposal and expired stock exist; dedicated loss summaries are absent from Reports. |
| Transfer to Sheets | Shared records reduce duplication, but no report export or Sheets integration was found. The baseline business problem remains only partly solved. |
| Responsive work is finished | Helper widgets and tests exist; they do not prove all screens/forms work at target device sizes. |
| Business readiness | Not established. Source defects, incomplete workflows, and missing business acceptance remain. |

## Batch 1 — Data integrity and agreed report definitions

### [ ] SUP-01 — Preserve supplier details during edit/archive

**P0 · Source defect · R05 · E09**

Current supplier models flatten contact information. Updating or archiving a supplier passes null for existing contact person, email, and address, resets terms to zero, and can replace notes with display text. The SQL function writes these values.

**Acceptance:** load a supplier with separate contact, phone, email, address, terms, notes, and item mappings; change only its name, then archive it. All unrelated values and historical links remain intact. Add a regression test for round-trip editing and archival. Extend the existing model/repository instead of adding a parallel supplier store.

### [ ] POS-01 — Make checkout retry-safe

**P0 · Source risk · R01 · E08**

Database request-ID support exists, but the Flutter call sends null. A transaction may commit before a network failure or failed read-back, leaving the user unsure whether to retry.

**Acceptance:** create and retain a request ID per checkout attempt, reuse it for recovery, and recover the committed receipt. Test a lost response, failed order reload, repeated submission, and simultaneous duplicate requests. Exactly one order/payment/stock deduction results. Verify backend ownership/authorization before returning any existing request result. A disabled button alone is insufficient.

### [ ] FIN-01 — Define and reconcile financial measures

**P0 · Source inconsistency + decision · R03/R04/R06 · E04/E07**

`v_daily_sales` calls the sum of final `total_amount` “gross_sales.” Refunds are attributed to the original sale date there and in product reporting, while Dashboard uses the refund's actual date. `netAfterExpenses` subtracts only posted expenses; it excludes tracked-stock costing and loss treatment. Product line values and order-level totals also need reconciliation around discounts.

**Acceptance:** agree a report glossary with management before changing formulas: pre-discount sales, discounts, net sales, refunds, collected payments, operating expenses, inventory purchases, supplier payments, stock consumption cost, loss cost, and the limits of any profit estimate. Specify whether each report follows transaction date or original-sale cohorts; label cohort reports explicitly. Use one Asia/Manila business-date convention independent of device timezone. Test a discounted sale on day A, partial refund on day B, refund-only day, expense-only day, month boundary, and supplier bill paid later. Dashboard, Finance, Reports, and export reconcile under the same selected basis. No double-counting purchases/payments/consumption/losses. Do not claim full accounting or invent recipe costs.

### [ ] POS-02 — Preserve receipt and order detail snapshots

**P1 · Confirmed gap · R01/R04 · E08**

Persisted order reads and `OrderItem` omit variant/modifier and discount details; receipt dialogs show reconstructed item totals without a full pricing breakdown.

**Acceptance:** order detail, immediate receipt, and reopened receipt show sold variant, selected modifiers and prices, quantity, subtotal, discount, final amount, payment/reference, cashier, time, and refund status as applicable. Values come from persisted snapshots. Changing a menu name/price or archiving a modifier must not change an old receipt. Test a priced add-on plus discount and partial refund; line breakdown reconciles to final total. Do not add unapproved statutory invoice claims.

### [ ] DOC-01 — Resolve requirements and documentation drift

**P1 · Confirmed drift · R01–R08 · E14/E16**

The team confirmed Supabase as the chosen backend on 2 October 2026; update the outdated Firebase/Firestore and Cloud Run references in the M3 paper. This is documentation maintenance, not a pending technology choice. It now contains a Security Plan, access table, and prototype figures, so these must not be described as missing. Its security narrative still describes temporary demonstration accounts, and its confirmed use-case actors are Employee/Staff and Manager/Admin. Document their mapping to the existing CASHIER, MANAGER and ADMIN permission roles. Separate Implementation Plan and System Evaluation sections were not found. Earlier AGENTS instructions allowed static reports and prohibited the now-existing backend. Supporting documents still mix plans, implementation statements, and validation checkmarks.

**Acceptance:** reconcile the academic paper, ERD, dictionary, integration/QA guides, and business validation checklist against the implemented design and accepted consultation decisions. Record which decisions were team/professor feedback versus café approval. Reconcile the existing security/account narrative and role table with code; maintain the prototype figures and check their consistency with the approved design. Confirm whether separate implementation/evaluation sections are required for the submission and supply actual plans/results where required, without fabricating evaluation evidence. Link the approved Figma file/version. Keep requirement IDs and the status distinction used here.

## Batch 2 — Maintainable master data and discoverable operations

### [ ] CAT-01 — Manage menu, inventory, and expense categories

**P1 · Confirmed gap · R07/R08 · E01**

**Acceptance:** managers create, rename, order, archive, and reactivate categories using the app. Reject blank and normalized duplicate names. Preserve stable IDs and historical records. Define reassignment or archive behavior for categories in use; never cascade-delete transactions. Empty setup offers a create-category path. POS and module filters reflect changes, including categories without current items, with no SQL editing. Enforce permissions in the backend. Keep separate category domains unless an approved requirement justifies sharing them; do not make lifecycle statuses arbitrary categories.

### [ ] MOD-01 — Complete modifier management and make it easy to find

**P1 · Partial feature · R01/R07/R08 · E02**

**Acceptance:** visibly labeled access to modifier groups/options; create/edit/archive options; required vs. optional, min/max, free vs. priced selection, and order are understandable. Support assigning/unassigning an existing group to a product where needed. Explain effects when editing a shared group. Test required selection, upper limits, inactive options, no available options, and persistence after reload. POS/backend enforce the same rules; snapshots survive edits. Reuse existing RPCs; do not restore ingredient recipes.

### [ ] DIS-01 — Manage promotional discounts and authorization

**P1 · Partial feature + decision · R01/R07 · E03**

**Acceptance:** agree whether cashier use requires a manager or an explicit permission; keep server checks authoritative. Add manager maintenance for approved percentage/fixed promotions, with validated bounds, active state, and any agreed eligibility/validity rules. Replace the fixed-code exposure limitation only with an explicit safe discount policy. Show discounts in checkout, receipts, refunds, and reports. Test absent permission, inactive/expired definitions if dates are supported, invalid amounts, and total/refund reconciliation. Never silently grant all cashiers unrestricted discount rights. Statutory discounts remain a separate validation item (`OPS-03`).

### [ ] INV-01 — Safely edit inventory master data and package definitions

**P1 · Incomplete workflow · R02/R05/R07 · E01/E05/E15**

The inventory screen offers add/archive, but routine master editing is not a complete visible flow. Package conversions are entered manually in operational forms; reusable supplier/package setup is incomplete.

**Acceptance:** edit name, category, reorder threshold, and permitted tracking settings; retain historical IDs and snapshots. Prevent changing base units/conversion history in ways that reinterpret existing movements. Maintain common packages (e.g. box of 50 cups), with a clear base-quantity preview. Receiving and release use saved defaults and explicit overrides where authorized. Test multiple package sizes for one item and reordering below threshold. Reuse `supplier_items`/existing units rather than hardcode seed-specific packages.

### [ ] AVAIL-01 — Make prepared-item availability operationally usable

**P1 · Workflow gap · R01/R02/R08 · E14/E02**

Prepared items are treated as untracked in the POS view. Product/variant active state exists, but the normal daily availability task is not clearly separated from catalog activation.

**Acceptance:** decide which staff may mark a prepared item unavailable and restore it, with clear reason/status. Expose a simple action; unavailable items cannot be checked out from a stale cart. Keep temporary availability distinct from permanently archiving a product in the user flow. Finished goods use usable stock and expiry rules. No measured milk/rice deduction or recipe disclosure. Record the agreed responsibility in README.

### [ ] PUR-01 — Complete receiving and supplier maintenance workflows

**P1 · Partial feature · R02/R05/R08 · E09/E15**

**Acceptance:** staff can find direct receiving without creating a PO, receive multiple lines, handle a partial PO delivery, and retrieve its source receipt and lots. Test duplicate supplier references, duplicate lines, invalid quantities, excess receipt attempts, expired deliveries, and failures mid-post. One receipt posts atomically. Supplier-item/package mappings can be maintained in the UI. Agree paid-at-purchase vs. later supplier-bill settlement, expose clear state, and prevent duplicate payment. Decide how cancelled POs and supplier returns are handled; do not claim those flows already exist.

### [ ] INV-02 — Review and correct posted releases/counts safely

**P1 · Partial feature/validation · R02/R05 · E05**

**Acceptance:** open a release/count to inspect its full lines, units, lot allocation, expected/count/variance, reason, user, and time. Test count conflicts with simultaneous sales/receiving so posting does not silently erase intervening movements. Provide a documented correction/reversal process with backend checks and links to the original record; do not directly edit movement balances. Enforce positive quantity, usable-stock limits, FEFO, and all-or-nothing multi-item posting.

## Batch 3 — Reports that answer the café's questions

Complete `FIN-01` definitions first. Reports and exports must use the same filtered data and definitions. A chart alone is not a report; a capped recent list is not a complete ledger.

### [ ] REP-01 — Shared reporting filters and complete result sets

**P1 · Confirmed gap · R04/R06/R08 · E04/E06**

**Acceptance:** Today, Yesterday, week/month presets and custom inclusive date range, with displayed Asia/Manila timezone and appropriate supplier/item/category/employee/status filters. Validate reversed ranges. Separate current stock snapshots from activity during the selected period. Paginate detail at the data layer with stable ordering and totals across the full filtered result, not only the current page or API row cap. Display period, generation time, row count, units/currency, and empty states. Changing the top-products view must not truncate exported full product detail.

### [ ] REP-02 — Sales, payment, discount, and refund reports

**P1 · Confirmed gap · R01/R04/R06 · E03/E04/E07**

**Acceptance:** summarize sales by date and product/category; show quantities, modifiers where relevant, discounts, refunds, net values, payment method totals, and employee/shift filters consistent with agreed access. Include drill-down to orders/refunds. Separate completed sales from voided/open transactions. Test multiple dates and refunds after the sale period; reconcile with receipt snapshots and cash/non-cash collections. Retain historic category meaning using the agreed snapshot policy.

### [ ] REP-03 — Expense and management financial reports

**P1 · Confirmed gap · R03/R04/R06 · E04/E07**

**Acceptance:** expenses by date/category/supplier/purpose, with receipt reference, status, actor, detail and totals; purchases/payables/payment summaries kept distinct. Support days with costs and no sales. Present “net sales less posted operating expenses” honestly until an agreed management profit estimate includes defined costs. Document inclusions/exclusions in the report itself. Verify a tracked stock purchase is not counted again as an operating expense or supplier payment expense.

### [ ] REP-04 — Expiry, damage, spoilage, and movement reporting

**P1 · Confirmed gap · R02/R04/R06 · E04/E05**

**Acceptance:** provide the report set below, with filters, complete details, totals, and source links. Amounts use recorded lot/base-unit costs; disclose missing costs rather than value them silently as zero. Do not add quantities across incompatible units.

| Report | Required information |
| --- | --- |
| Expiry exposure | Item, lot, supplier/receipt, expiry, remaining quantity/unit; separately current expired and near-expiry usable stock. |
| Recorded losses | Disposal date, item, lot, expired/damaged/spoiled reason, quantity/unit, recorded cost, user, source; totals by reason and period. |
| Stock movement ledger | Opening balance, receipts, sales deductions, releases, approved refund returns, losses, adjustments, closing balance per item; source documents and units. |
| Count variance | Count document/date, expected and counted stock, variance, resulting adjustment, reason, actor. |
| Reorder summary | Usable quantity, threshold, supplier/package options where maintained. |

An expired lot still on hand is exposure; posted disposal is a movement. Test that the same stock is not counted as two losses. Manual adjustments and loss movements must be visible even if no purchase/stock-out header exists.

### [ ] REP-05 — Export reports for Google Sheets without retyping

**P1 · Confirmed gap · R04/R06 · E04**

**Minimum deliverable:** UTF-8 CSV export for the agreed management report set. Direct Sheets sync is optional (`OPS-04`).

**Acceptance:** export complete filtered results with stable column names, document/reference IDs, numeric amounts, explicit units, dates, timezone, and clear currency context. Preserve Unicode, commas, quotes, and line breaks; protect spreadsheet formula-like text without corrupting legitimate numeric values. Match on-screen full-result totals exactly. Test a dataset larger than all current history limits and verify it is not silently truncated. Restrict export to authorized users. Management imports the file into Google Sheets and calculates the agreed totals without retyping transaction data. Record this end-to-end outcome. Agree any PDF/printable summary requirement separately; do not substitute screenshots for data export.

### [ ] TRACE-01 — Full history and source-document drill-down

**P1 · Confirmed limitations · R02/R04/R05 · E05/E06/E07**

Inventory history searches only the fetched 250 movements; trace searches at most 500 recent rows. Release/count lists are capped. The trace SQL includes sales, refunds, receipts, releases, counts, expenses, and supplier payments, but not every standalone disposal/adjustment/void or PO event. Trace entries are currently display rows, not a full document navigation workflow.

**Acceptance:** server-filtered, paginated search by document, external receipt, supplier, item, actor, date and event type; exact old-reference search works beyond recent limits. Open linked document/line/lot detail and distinguish reference numbers from entity IDs. Include agreed missing event types without counting both headers and their detail rows as duplicate financial events. Retain archived-item and supplier history. Do not imply the trace is a full audit log.

## Batch 4 — Consistency, access, and UI completion

### [ ] SYNC-01 — Keep open screens and multiple devices consistent

**P1 · Source limitation/validation · R01/R02/R08 · E11**

Current `ChangeNotifier` refresh affects only one running client. Purchasing emits changes but does not subscribe to the shared business refresh in the same way as several other pages.

**Acceptance:** define and test refresh on successful writes, route return/app resume, and remote changes using a proportionate approach within the existing architecture. Test manager availability changes while cashier POS is open, receiving while inventory is open, new supplier while purchasing is open, and a sale of the last item from two devices. Backend checkout prevents overselling even with stale UI. Expose refresh/stale/error states and avoid losing entered forms during refresh. No unsupported “real-time everywhere” claim.

### [ ] SEC-01 — Align visible actions with explicit backend permissions

**P1 · Source risk/validation · R05/R08 · E10**

Navigation mostly treats anyone who is not a cashier as management. This is not evidence of a backend bypass, but unknown/new roles could receive misleading UI. Employee creation is administrator-only even though manager user-management navigation exists.

**Acceptance:** deny unknown/missing roles by default; centralize explicit UI capability mapping to existing permission names; show only actionable controls. Test ADMIN, MANAGER, CASHIER, inactive user, missing role, and expired session. Check the M3 role table explicitly: cashiers receive no confidential financial summaries or expense/finance/user-administration access; reports/suppliers need specific authorization; stock movements need explicit permission; voids/refunds need management authorization. Use Employee/Staff and Manager/Admin as the confirmed business actors; document the mapping to CASHIER and to MANAGER/ADMIN respectively. Preserve finer permission distinctions unless a separate access-policy change is approved. Direct unauthorized RPC/table/export calls must fail. Test account deactivation and role changes during a session, including refresh. Preserve default-deny function grants and RLS; do not weaken policies to make a button work.

### [ ] UX-01 — Use café language and visible actions

**P1 · User feedback + source evidence · R07/R08 · E02/E03/E12**

**Acceptance:** review all module titles, actions, labels, helpers, status badges, and error text with a staff member. Explain “pack size,” “pieces per box,” “usable stock,” “recorded loss,” and “supplier receipt number” near the input. Keep identifiers and technical modes out of ordinary tasks unless needed. Make receiving, modifiers, discounts and reports findable through labeled actions. Distinguish archive, unavailable, void, refund, and dispose. Show previews for conversions and irreversible posting. Record observed task completion without coaching.

### [ ] UX-02 — Consistent search, filters, and ordering

**P1 · Partial feature · R04/R07/R08 · E01/E05/E06/E12**

**Acceptance:** searchable selectors for growing catalogs/suppliers; case-insensitive text search; clear filters; stable category/item ordering; clear no-results state; visible active filter/date scope. Add reusable sorting/pagination support to existing table patterns where needed. Search must cover all eligible records, not just a client-side recent slice. Preserve selection by ID after rename. Test long names, no categories, many categories, archived records, and repeated names in different domains.

### [ ] UX-03 — Validate complete screens across sizes

**P1 · User-reported problem; runtime reproduction pending · R08 · E12**

**Acceptance:** exercise every module and its longest dialog at 320×640, 360×800, 768×1024, 1024×768, 1366×768, and 1920×1080 logical-pixel viewports, plus the actual café tablet. Test enlarged text (up to 200%), browser zoom, touch, and the on-screen keyboard. No overflow exceptions, clipped required text, unreachable save/cancel buttons, or lost focus. Tables may scroll horizontally with clear affordance; forms and main actions must remain usable. Keep Inter/colors/components and current adaptive shell; fix shared primitives where possible, then screen-specific layouts. Save before/after evidence and full-screen widget tests for actual failures; three helper tests are insufficient.

### [ ] UX-04 — Recoverable errors and safe form submission

**P1 · Validation/source gap · R01/R02/R08 · E08/E12/E13**

**Acceptance:** distinguish loading, empty data, permission denial, connection loss, and server validation; show actionable messages with retry. Keep typed values on failures and prevent duplicate submission. Handle setup-fetch errors before opening dialogs as well as save errors. Avoid exposing raw SQL/stack messages to staff. Check focus order, keyboard submission, readable contrast, accessible labels, touch targets, and color-independent statuses.

### [ ] BOOT-01 — Recover from startup and renderer failures

**P1 · Source gap + reported incident · R08 · E13**

The user previously encountered a white screen when CanvasKit failed to download. Missing config is handled, but initialization exceptions before `runApp` and browser bootstrap failures need a recovery path.

**Acceptance:** visible startup progress, timeout/error/retry guidance for runtime configuration and initialization; test browser renderer asset failures separately because Dart UI cannot display before the renderer starts. Confirm an appropriate asset-hosting/cache strategy for the deployed build. Test the actual café network/browser. Do not make disabling antivirus or changing a developer browser flag the permanent operating procedure.

### [ ] AUTH-01 — Complete employee account lifecycle

**P1 · Incomplete workflow/validation · R05 · E10/E13**

**Acceptance:** document first-admin bootstrap, deployed employee-creation dependency, individual accounts, temporary-password handling, password change/reset or a verified administrator recovery process, inactive-user handling, and audit trail. Manager/admin privileges match business responsibility. Demonstrate recovery without shared passwords or exposing privileged keys. Automated function checks and a deployed smoke test must cover the allowed and denied creation flows.

## Batch 5 — Release evidence and conditional operations

### [ ] QA-01 — Test business outcomes across layers

**P1 · Coverage gap · R01–R08 · E16**

Existing tests provide useful model/helper and database coverage; they do not demonstrate whole user journeys, exports, or café acceptance.

**Acceptance:** add focused tests for the defects above, screen journeys for category/modifier/discount setup, receipt round-trip, and report/export reconciliation. Run CI on the implementation commit. Add two-session contention tests for checkout/receiving/counts; test row counts beyond API/history limits and error/retry handling. Record actual results and blocked tests. Keep automated correctness, visual usability, and business acceptance as separate evidence.

### [ ] OPS-01 — Reproducible build, staging, deployment, and recovery

**P1 · Validation gap · R01–R08 · E13/E16**

**Acceptance:** agree supported Flutter/Dart versions and pin/reproduce CI; retain intentional lockfile changes. Build the target web/Android artifact in CI where appropriate, verify environment configuration, migrations, required function deployment and real reference data in staging. Demonstrate database backup restoration in an isolated environment and recovery from a failed deployment. Record support owner, credentials handling, business data retention, expected load, and operating checklist. No production reset or blind seed reapplication. Review application metadata and residual sample wording before release.

### [ ] OPS-02 — Decide offline, printing, and delivery details

**P2 · Business decision · R01/R08**

**Acceptance:** confirm whether sales must continue without internet, required receipt printer/paper, split payment, and minimum delivery contact/address fields. Current POS enforces one payment method, receipt display is not print integration, and no offline queue was found. If essential for café use, promote the relevant task to P1 and implement/test it before release; otherwise document the accepted limitation and recovery process. Recording a sale's cashier does not prove preparation responsibility; decide whether simple preparation attribution is needed without inventing a kitchen workflow.

### [ ] OPS-03 — Validate statutory discounts and invoice expectations

**P2 · Business validation/release dependency · R01/R04**

**Acceptance:** obtain the café's applicable registration, receipt/invoice, tax, and statutory discount requirements and have the agreed calculations/output verified by a qualified reviewer. Record the decision before enabling those flows or using the system for official transactions. Existing generic promotional discounts and invoice-number fields are not evidence of compliance. This task does not authorize adding full tax accounting.

### [ ] OPS-04 — Decide whether direct Google Sheets synchronization is needed

**P2 · Optional extension · R06; depends on REP-05**

**Acceptance:** let management try the in-app reports and CSV import first. If direct sync is required, document destination, columns, update/correction semantics, permissions, duplicate prevention, retry behavior, and sync status before implementation. The system remains the transaction source of truth; do not create two independently editable financial ledgers. No credentials in Flutter or the repository.

## Shared acceptance scenario for the three testers

Use an isolated staging/demo environment and unique run references. Capture starting balances before testing; do not assume demo data is empty. Re-run after relevant fixes. System-generated document numbers should be recorded, not replaced with invented custom IDs; put test references only in supported reference/notes fields.

| Step | Owner | Scenario and proof |
| --- | --- | --- |
| 1 | Tester 2: stock/purchasing | Create categories/supplier/package through the UI, receive two boxes of 50 cups plus another supply in one receipt; verify 100 cup pieces added and source/lot links. |
| 2 | Tester 1: POS/access | Create or select a menu item with a priced modifier; set an approved promotion as manager; confirm permitted cashier behavior and blocked management actions. |
| 3 | Tester 1 + 2 | Sell a prepared drink and one linked finished good; only the finished good deducts automatically. Release one box of cups and another supply together; cups decrease by 50. |
| 4 | Tester 2 | Dispose a known quantity as damaged and another lot as expired; record a physical-count variance, verify FEFO and source-linked movements. |
| 5 | Tester 3: expenses/reports | Enter an untracked grocery purchase with store, purpose, date, amount and receipt. Confirm it is not duplicated as tracked purchasing. |
| 6 | Tester 1 + 3 | Refund part of a discounted sale on a later business date. Verify retained original receipt, refund amount, and chosen reporting date basis. |
| 7 | Tester 3 | Reconcile sales/payments/expenses/losses and per-item opening + signed movements = closing; export and import into Sheets with matching totals. |
| 8 | All | Repeat key tasks on the actual tablet and narrow viewport; two-device stale-stock test; lost-response checkout recovery; role denial; restore rehearsal. |

For each test save: requirement/task ID, tester, commit/environment, starting data, steps, expected result, actual result, document/reference numbers, screenshot/export, pass/fail/blocked, and issue link. Tester 3 can prepare expense/UI checks while waiting for the shared transactions; dependent reconciliation must use all members' completed records.

## Release gate

- [ ] P0 issues resolved with regression evidence.
- [ ] R01–R08 mapped to accepted P1 outcomes; outstanding conditional needs explicitly agreed.
- [ ] Management can maintain normal master data without a developer.
- [ ] Reports, receipts, source records, and exported totals reconcile; Sheets retyping is demonstrably reduced.
- [ ] Actual tablet, responsive layouts, discoverability, and two-device behavior accepted.
- [ ] Backend authorization, account recovery, and restore/deployment checks pass.
- [ ] Café representative confirms the operational workflow; professor/team review alone is not business acceptance.

No phase label, seed script, screenshot, or green test badge can substitute for these outcomes.
