# Street Bowl Café Management System

A Flutter and Supabase application for Street Bowl Café's internal sales, inventory, purchasing, expenses, and management reporting.

**Status: integrated development prototype; not business-ready.** Database integration and automated checks do not establish that the café's requirements have been met. Master-data management, reports and exports, transaction presentation, usability, and operational acceptance still need work. The evidence and acceptance criteria are in [TODO.md](TODO.md). Development rules are in [AGENTS.md](AGENTS.md).

## Documentation baseline and review scope

This baseline was reviewed on **2 October 2026 (Asia/Manila)** against:

- **D1 — Current academic baseline:** *Development of a Centralized POS and Inventory Management System for Street Bowl Cafe*, `IT12_M3_Angga_Ayco_Briones (1).pdf`, 29 pages, uploaded 2 October 2026 (Asia/Manila). Company and existing processes: PDF pages 4–9; problems: page 12; objectives: pages 17–18; technology: pages 18–19; ERD/use case figures: pages 20–21; scope and limitations: pages 22–24; Security Plan and role-access table: pages 24–25; System Prototype figures: pages 26–29. Page references use PDF positions, not printed page labels. This team-held paper is not committed in this repository. It supersedes the 24-page `IT12_Angga_Ayco_Briones (2).pdf` used in the initial audit.
- **D2 — Accepted consultation decisions:** practical, countable inventory; multiple items per receipt and stock-out; package conversions; expiry priority; untracked ingredients recorded as expenses; no recipe disclosure or automatic ingredient deductions for prepared food.
- **D3 — Team review of 2 October 2026:** manageable categories, usable modifiers and discounts, complete reports, elimination of repeated spreadsheet entry, searchable interfaces, and responsive layouts.
- **C1 — Source audit:** `brian/inventory-workflow-navigation` at `d55ce33059a8206c035203dc932052cef3424f09`. The review examined Flutter screens, models, repository contracts and implementations, SQL migrations, seeds, tests, and CI definitions. It did not run a live browser, Flutter tests, or database tests during this documentation review.

This README summarizes the business baseline; it does not replace the academic paper or claim café sign-off. Later agreed consultation decisions refine the paper. The team confirmed on 2 October 2026 that Supabase is the chosen backend. The paper's Firebase/Firestore and Cloud Run references are outdated and will be updated; this is pending paper maintenance, not an unresolved backend decision. The current PDF includes a Security Plan, role-access table, and System Prototype figures; the earlier claim that these sections were empty no longer applies. Separate Implementation Plan and System Evaluation sections were not found in this version. Its security text still describes temporary demonstration accounts, which needs reconciliation with the integrated Auth implementation. Prototype figures document intended presentation, not proof of live functionality or completed evaluation.

## Business background

Street Bowl Café operates at Margarita Village Road, Bajada, Davao City. It serves coffee and other drinks, rice bowls, meals, snacks, and baked goods, including dine-in and takeaway customers. Orders also arrive through phone and Facebook Messenger; staff enter those transactions internally. Students, remote workers, and nearby customers form part of its audience.

The documented existing environment uses Loyverse POS, Google Sheets, receipts, physical stock checks, and manual records. The manager oversees finance, stock, suppliers, and staffing. Baristas and service staff handle customer orders and daily service. No formal corporate vision or mission was supplied; do not invent one.

### Problems the system must solve

| Business problem | Required outcome |
| --- | --- |
| Sales are repeatedly copied from Loyverse into Google Sheets. | Record once and generate consistent sales, expense, and management summaries from shared transactions. Provide an export that can be imported into Sheets without retyping. |
| POS availability can disagree with actual stock or kitchen availability. | Use usable stock for countable finished goods and a simple staff-maintained availability process for prepared items. Recheck eligibility at checkout. |
| Physical checks and stock movement records are fragmented. | One item catalog, traceable receipts/releases/counts, clear units, and accessible movement history. |
| Spoiled, expired, or damaged stock is logged separately. | Record losses by lot and reason and report quantities and recorded cost, separately from stock merely approaching expiry. |
| Financial information is maintained across tools. | Bring sales, refunds, expenses, purchasing, and supplier payments into clear, reconcilable summaries without counting the same cost twice. |
| Responsibility is difficult to trace. | Preserve the actor, timestamp, document, and source reference. The cashier who records an order must not automatically be described as the employee who prepared it. |

## Objectives and requirement identifiers

The general objective is to centralize the café's internal operations and reduce duplicate entry and repeated checking.

| ID | Baseline requirement | Evidence needed for acceptance |
| --- | --- | --- |
| R01 | Record orders, items, quantities, order type, payments, employee, date, and receipt. | A completed order and its receipt agree, including variants, modifiers, discounts, refunds, and payment references. |
| R02 | Track practical stock availability, movements, low stock, and damaged/spoiled/expired goods. | Receive, release, sell, dispose, and count test stock; reconcile opening quantity plus movements to closing quantity. |
| R03 | Record and retrieve business expenses and financial information. | Supplier/store, date, purpose, amount, and reference persist; corrections are traceable; purchases are not duplicated as expenses. |
| R04 | Produce sales, expense, inventory, and profit-related management reports. | Agreed formulas, date boundaries, detail drill-down, and loss summaries reconcile to source transactions. |
| R05 | Maintain suppliers, restocking records, and access according to employee responsibility. | Multi-item receiving and supplier history work; authorized actions succeed and unauthorized actions fail at the backend. |
| R06 | Reduce repeated manual transfer into Google Sheets. | Management can finish the agreed review within the app or import its exported report into Sheets without re-entering transactions. |
| R07 | Allow routine maintenance of categories, modifiers, and discounts. | An authorized manager completes supported setup through the UI without editing SQL or seed files. |
| R08 | Provide understandable, searchable, responsive workflows. | Staff finish real tasks on the café's tablet and agreed desktop sizes with readable labels and reachable actions. |

R01–R05 summarize the paper. R06 makes its spreadsheet-transfer problem measurable. R07–R08 incorporate the team's current feedback. These requirements are not marked complete merely because a related table or screen exists.

## Scope and business rules

### Included

Internal POS/orders, shifts and cash movements, menu products and variants, modifiers, promotional discount application, practical inventory and lots, purchasing and receiving, suppliers, operating expenses, management summaries, user accounts, and role-based access. Several of these remain partial; see the capability table below.

### Agreed inventory and expense workflow

1. Maintain countable supplies and finished goods with stable IDs and explicit units.
2. Receive several items in one goods receipt with supplier, supplier receipt/invoice number, date, quantities, package conversion, and costs. A purchase order is optional for direct purchases.
3. Record package movement practically: for example, receiving two boxes of 50 cups adds 100 base pieces; releasing one box records one release line equivalent to 50 pieces. Do not require a separate transaction per cup.
4. Release multiple supplies in one stock-out transaction. A release is stock leaving tracked storage for use, not a recipe-based deduction for each drink.
5. Allocate usable perishable lots by earliest expiry (FEFO); use a deterministic receiving order when expiry does not distinguish lots. Expired stock is not usable stock. Disposal is a separate recorded action.
6. Prepared-to-order food and drinks do not require recipes or measured ingredient consumption. Record difficult-to-track grocery/ingredient purchases as expenses.
7. Linked countable finished goods may deduct automatically on sale. Prepared-item availability must be maintained operationally; removing recipe tracking does not remove the need to mark an item unavailable.
8. Keep receiving, releases, disposal, counts, and adjustments traceable to their documents and users. Correct posted transactions through an auditable correction flow.
9. Keep tracked purchases in Purchasing. Supplier payment, purchase, inventory consumption, and operating expense represent different events and must not be added together as if they were the same expense.

### Roles

The confirmed use-case actors are **Employee/Staff** and **Manager/Admin**. These are business actor groups, not a requirement to collapse database roles. Employee/Staff covers operational staff; the existing `CASHIER` role implements the current POS staff access. Manager/Admin covers the existing `MANAGER` and `ADMIN` roles. This mapping does not grant every staff member every operational permission.

The current seed defines `ADMIN`, `MANAGER`, and `CASHIER`:

| Role | Intended responsibility | Current qualification |
| --- | --- | --- |
| Admin | Account administration, role assignment, and business administration. | Employee creation uses the administrator-only `create-employee` Edge Function. |
| Manager | Menu, purchasing, inventory, expenses, reports, and permitted employee administration. | Must not receive administrator privileges implicitly. |
| Cashier | POS, own shift, and permitted inventory visibility. | Current seed does not grant `discounts.apply`; cashier discount authorization needs an explicit business decision. |

The current paper requires least privilege, application and backend enforcement, no confidential financial summaries for cashiers, no cashier expense/finance/user-administration access, and management authorization for voids/refunds. Staff inventory movements are permitted only when specifically authorized; this is not blanket stock-management permission. Use the two confirmed actor labels in use-case documentation, and document the finer ADMIN/MANAGER permission distinction in the access matrix, especially employee creation and role assignment. Grouping actors does not itself authorize broader access.

The seed and database permission checks define implemented backend permissions. The UI currently relies heavily on `isCashier`/`!isCashier`; replacing that broad assumption with explicit capabilities is backlog work. Hidden navigation alone is not authorization.

### Outside the agreed baseline or awaiting a decision

Customer self-service ordering, supplier portals, Facebook/Loyverse automatic integration, multi-branch operations, payroll, general ledger accounting, official financial statements, forecasting, and automatic purchasing are outside the baseline. Payment method recording does not transfer money through an external wallet or bank.

Google Sheets **importable export** is the minimum proposed reporting deliverable; direct Google Sheets synchronization is a separate decision. Split payments, offline sales, receipt printer support, statutory discounts, and fiscal invoice requirements need business validation before implementation or any readiness claim. The current application requires connectivity; no offline transaction queue was found.

## Current capabilities and limitations

“Present” below means found in source, not accepted by the business.

| Area | Present in source | Missing or incomplete |
| --- | --- | --- |
| Categories | Database-backed menu, inventory, and expense category reads. | No category maintenance UI/contracts for create, rename, reorder, and archive. Filtering existing categories is not category management. |
| Menu and availability | Product/variant editing; prepared vs. finished-stock modes. | A clear daily availability workflow, better category sorting, and actual café setup validation. |
| Modifiers | Menu row's **Modifiers** action opens group and option create/edit; POS supports selections. | Discoverability, shared-group assignment/reuse workflow, and complete receipt presentation. |
| Discounts | Promotional discount selection during payment and database application logic. | Definition management UI, cashier approval policy, discount reporting, and statutory validation. POS RPC currently allows specific seeded codes. |
| Orders and receipts | Checkout, shifts, receipt dialogs, refunds, and finished-goods restock approval. | Persisted variant/modifier/discount detail presentation, printable output, and retry-safe checkout. |
| Inventory | Usable/expired/on-hand stock, lots, multi-item releases, disposal, counts, adjustments, and history. | Full searchable history beyond recent limits, loss summaries, master-data editing, and stronger detail navigation. |
| Purchasing/suppliers | Multi-item POs and direct/PO receiving, receipt details, bills, and supplier payments. | Safe structured supplier editing and reusable supplier/package setup. |
| Expenses | Database-backed capture and duplicate-reference checks. | Category management and categorized/exportable summaries. |
| Reports/finance | Last 7/30 days, sales, expenses, top 10 products, stock indicators, and transaction trace. | Custom dates, complete detailed reports, loss/cost summaries, payment/discount breakdowns, export, and reconciled date/formula semantics. |
| UI and responsiveness | Shared theme, adaptive navigation, filter bars, scrolling tables/dialogs. | Whole-screen and device validation; consistent labels, search, sorting, errors, and discoverable actions. |
| Security and quality | Auth, RLS, permission-checked RPCs, pgTAP tests, Flutter tests, and CI. | End-to-end evidence, account recovery, broader role/UI tests, deployment and restore rehearsal. |

**The spreadsheet-transfer problem is only partially addressed.** Sales and expenses share a database, but no CSV/XLSX/PDF report export or Google Sheets integration was found in `lib/` or `web/`. “Net After Expenses” currently subtracts posted expenses from net sales; it must not be presented as complete café profit. See `FIN-01`, `REP-01`–`REP-05` in [TODO.md](TODO.md).

## Architecture and data ownership

Keep the existing flow: **screen → repository interface → Supabase repository → Data API/RPC → PostgreSQL**. Operational records are the source for reports; do not create a second editable reporting ledger.

- `lib/main.dart`: runtime configuration and initialization.
- `lib/app.dart`: repository construction, role-based navigation, and refresh wiring.
- `lib/domain/repositories/`: module contracts.
- `lib/data/repositories/`: Supabase implementations and existing mock implementations.
- `lib/models/`: records, inputs, and parsing.
- `lib/screens/`: module UI, including auth, menu, inventory, purchasing, and reports.
- `lib/core/theme/`: colors, typography, spacing, and theme.
- `lib/core/state/`: existing `ChangeNotifier` refresh controllers.
- `lib/widgets/common/` and `lib/widgets/layout/`: shared controls and page layout.
- `supabase/migrations/`: ordered schema, views, policies, and transactional functions.
- `supabase/functions/create-employee/`: privileged employee creation on the server.
- `supabase/tests/database/`: pgTAP checks; `test/`: Flutter/model/widget checks.
- `database/`: ERD, dictionary, business validation, and setup/QA guidance.

Business writes spanning orders, payments, stock, or document posting belong in transactional RPCs. Repositories translate data; widgets do not own persistent business truth. Existing auth screens directly use Supabase Auth/profile access; keep that exception contained. Refresh controllers notify the current app instance; they are not cross-device synchronization.

## Technology and design

| Component | Implemented choice |
| --- | --- |
| Client | Flutter/Dart; `pubspec.yaml` requires Dart `^3.13.0`. |
| Data/auth | Supabase PostgreSQL, Auth, RLS, SQL views and RPCs; `supabase_flutter` dependency. |
| Privileged account creation | Supabase Edge Function using TypeScript/Deno. |
| State/composition | Stateful widgets, constructor-injected repositories, FutureBuilder, ChangeNotifier refresh. |
| Quality | Flutter analyzer/tests; Supabase CLI and pgTAP; GitHub Actions. Database CI pins CLI `2.109.1`; Flutter CI currently follows stable. |
| Development/demo | VS Code, Git/GitHub, Chrome web; Android tablet is the business target requiring validation. |
| Design | Existing Figma direction: Inter, red/orange, black/white, light-gray surfaces, shared sidebar/cards. |

Use the checked-in lockfile and record actual tool versions for reproducible testing. Scaffolded platform folders are not evidence of supported, tested releases. A Figma file/version still needs to be linked in the project documentation.

## Run locally

From a clean checkout of the agreed integration branch:

```powershell
git fetch origin
git switch brian/inventory-workflow-navigation
git pull --ff-only origin brian/inventory-workflow-navigation
flutter pub get
flutter run -d chrome --dart-define="SUPABASE_URL=https://YOUR_PROJECT.supabase.co" --dart-define="SUPABASE_PUBLISHABLE_KEY=YOUR_PUBLISHABLE_KEY"
```

If the local branch does not exist after fetching, use `git switch --track origin/brian/inventory-workflow-navigation`. Check `git status` first and preserve local work; stop on errors before running later commands.

Use an existing approved development project with matching migrations, reference data, and an active Auth user/profile. Employee creation additionally requires the deployed `create-employee` function. Seed scripts do not create login accounts. There is no supported `admin/123` login in the integrated branch. Supply only a publishable client key to Flutter; never a service-role key or database password.

Read [database setup](database/README.md) and [demo walkthrough](database/DEMO_WALKTHROUGH.md) before setting up an isolated database. Demo seeds contain sample master data and can update it when rerun; they are not verified café data and must not be applied to production as a repair step.

## Validation and release criteria

```powershell
flutter analyze
flutter test
```

Database checks require a working Docker-compatible runtime, or the repository's Database CI:

```powershell
npx supabase start
npx supabase test db
```

If container startup fails, local database tests have not run. A migration dry-run is not a substitute for tests. Review migrations against an isolated database before any hosted deployment. Use [INTEGRATION_QA.md](INTEGRATION_QA.md) and [security test plan](database/SECURITY_TEST_PLAN.md) as supporting material.

Business readiness requires all release-blocking TODO acceptance criteria, matching report/export totals, device evidence, secure roles, recovery rehearsal, and café approval of the baseline workflows. Testing can be divided among three members: POS/access; inventory/purchasing; expenses/reports. They must also perform one shared reconciliation scenario. Passing automated checks or finishing an earlier phase is not business acceptance.

## Development roadmap and supporting documents

Implement the ordered batches in [TODO.md](TODO.md): correctness and report definitions; master data; operational usability; complete reports/exports; responsive and acceptance hardening. Deliver each feature through the existing architecture and follow [AGENTS.md](AGENTS.md).

- [Business validation checklist](database/BUSINESS_VALIDATION_CHECKLIST.md)
- [Data dictionary](database/DATA_DICTIONARY.md)
- [ERD notes](database/ERD.md) and [editable ERD](database/ERD.drawio)
- [Integration plan](database/INTEGRATION_PLAN.md)
- [Presentation checklist](database/PRESENTATION_CHECKLIST.md)

Older documents include historical plans and completed-phase claims; reconcile them under `DOC-01` before treating them as acceptance evidence. The team's next implementation work should branch from the agreed integration head, not automatically from an older `main` branch.
