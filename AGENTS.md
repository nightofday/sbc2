# Development instructions — Street Bowl Café

Read this file, [README.md](README.md), and the relevant task in [TODO.md](TODO.md) before changing the repository. These instructions apply to the whole repository unless a more specific instruction applies.

## 1. Project stage and sources

This is an **integrated Flutter + Supabase development prototype**, not a mock-only UI and not a business-ready release. Preserve working behavior while closing documented gaps. Static/sample reports or seeded catalogs are not acceptable substitutes for required business workflows.

The current academic baseline is `IT12_M3_Angga_Ayco_Briones (1).pdf` (29 pages, uploaded 2 October 2026); see README for page references and superseded versions. It includes security/access rules and prototype figures. Preserve the distinction between documented requirements, implemented behavior, and verified outcomes; do not revive the earlier claim that those sections are empty.

For requirements, follow explicit task instructions, then recorded accepted business/consultation decisions and the README baseline. Use TODO acceptance criteria to determine what remains. The academic paper is evidence for the baseline, not a reason to undo later accepted practical-inventory decisions. If sources conflict materially, identify the conflict and resolve it before implementing the disputed behavior; continue unblocked work.

The team confirmed on 2 October 2026 that the use-case actors are Employee/Staff and Manager/Admin, and Supabase is the chosen backend. Firebase/Firestore and Cloud Run references in the paper are outdated. Update documentation accordingly; do not reopen backend selection or migrate to Firebase. Business actor groups do not require renaming or merging the existing CASHIER, MANAGER and ADMIN roles. Preserve their permission boundaries unless an explicit access-policy change is approved.

For visual design, use the approved Figma direction and existing theme/components. Figma does not override backend authorization or business correctness. Until an exact Figma file/version is linked, preserve the current design tokens and report uncertainty rather than inventing a redesign.

Existing code establishes architecture and conventions, but is not automatically correct. Documentation claims, mock values, and old “phase complete” labels are not proof of production behavior.

## 2. Scope and change discipline

- Identify the TODO/requirement IDs, current implementation, affected models/contracts, migrations, shared widgets, and dependent screens before editing.
- Implement the smallest **complete business flow** that satisfies acceptance. A UI-only form, unused RPC, or new table without the required workflow is not complete.
- Preserve folder structure, repository architecture, technology stack, naming, navigation model, and visual language. Do not replace the app, add a second backend, or conduct a repository-wide refactor to implement a local task.
- Supabase integration is already authorized and implemented. Extend it through existing boundaries; do not reintroduce the old prohibition on database work.
- New schema, methods, models, or reusable widgets are allowed when necessary for an approved requirement. Prefer additive, compatible changes and explain impact.
- A new state-management framework, ORM, routing framework, parallel data layer, or broad renaming requires a separate rationale and team decision. Routine changes within existing patterns do not need repeated approval.
- Add dependencies only for a concrete need after checking existing capabilities. Explain why; keep their scope small. No unrelated upgrades or formatting sweeps.
- Report unrelated defects with evidence/TODO IDs instead of silently mixing fixes into the current task.

## 3. Preserve the architecture

Required business-data flow:

**Screen → repository interface → repository implementation → Supabase Data API/RPC → PostgreSQL.**

| Location | Responsibility |
| --- | --- |
| `lib/main.dart` | Runtime initialization/configuration. |
| `lib/app.dart` | Repository construction, navigation and shared refresh wiring. |
| `lib/domain/repositories/` | Module contracts consumed by screens. |
| `lib/data/repositories/` | Data mapping, queries and RPC calls; existing mock implementations. |
| `lib/models/` | Records, inputs, serialization and domain-facing types. |
| `lib/screens/` | User interaction and presentation. |
| `lib/core/state/` | Existing refresh controllers and narrowly scoped shared state. |
| `lib/core/theme/` | Colors, typography, spacing and theme. |
| `lib/widgets/common/`, `lib/widgets/layout/` | Reusable controls, dialogs, tables, cards and shell. |
| `supabase/migrations/` | Versioned schema, views, RPCs and policies. |
| `supabase/functions/` | Existing server-side privileged operations. |

Use constructor injection and the existing StatefulWidget/FutureBuilder/ChangeNotifier patterns. Screens must not add business table queries, SQL, or persistent duplicate ledgers. Auth initialization, login, profile loading and sign-out currently access Supabase directly; keep that exception contained. Existing UI catches for `PostgrestException` are not permission to add business queries to widgets.

Multi-table writes, posting, payment/stock mutations, and authorization-sensitive calculations belong in transactional database functions. Keep authoritative totals and validation on the server; UI previews should agree with them. Repositories should not orchestrate non-atomic writes for one business transaction.

Extend existing interfaces before adapters/screens. Update all implementers and affected tests. Retain useful mock repositories for isolated tests; never silently fall back to mock success when a live operation fails. Not every module has a mock implementation; add one only if the task requires it.

## 4. Names and contracts

- Files/folders: `snake_case`; classes/types/widgets: `PascalCase`; methods/variables: `lowerCamelCase`; private Dart members: `_prefix`.
- Preserve established `XRepository`, `SupabaseXRepository`, `MockXRepository`, `XScreen`, `*Record`, `*Option`, and `*Input` patterns where they fit.
- Database tables/columns/functions: existing `snake_case`; existing SQL status codes remain uppercase unless a migration deliberately changes their contract. Keep database codes separate from user-facing labels.
- Relationships use stable IDs, not display names. Distinguish database UUIDs, document numbers, SKUs, and external receipt/reference numbers.
- Do not repurpose `productId` to mean an order-line ID in new code. If correcting existing ambiguous models, migrate the affected uses together and document the compatibility impact.
- Preserve persisted transaction snapshots. Renaming or archiving catalog/supplier data must not rewrite old transaction meaning.
- Preserve public signatures and RPC payloads unless the task requires changes; update every caller, parser, mock and test when changing them. Do not leave parallel “new”/“v2” application modules as an accidental second system. Existing versioned RPC names remain valid contracts.

## 5. Business invariants

- Single café branch and internal users are the baseline. Do not invent customer/supplier portals, payroll, full accounting, forecasting, or automatic external integrations.
- No recipe disclosure and no automatic measured ingredient deduction for prepared-to-order food/drinks. Price modifiers do not restore recipe tracking.
- Untracked grocery/ingredient purchases are expenses. Track countable supplies and finished goods in practical units. Finished-goods sale deductions must use the same inventory source seen by other modules.
- One receipt and one stock-out may each contain many items. Retain package conversion snapshots and base units; show the conversion to the user. No transaction-per-cup requirement.
- Expired quantities are not usable quantities. Preserve FEFO for usable perishable lots and deterministic allocation otherwise. Record disposal separately; do not erase a lot or count expiry exposure as a second loss.
- Posted transactions retain actor, timestamps, reason and source links. Corrections use an auditable void/reversal/adjustment appropriate to the workflow, not destructive edits to history.
- Purchases, supplier payments, operating expenses, stock consumption, and losses are distinct. Do not double-count them or label an incomplete cash/expense measure as full profit.
- Do not assume the cashier prepared the food. Preparation attribution is a separate requirement decision.
- Categories are managed reference data when the business needs to change them. Fixed statuses/permission codes are controlled workflow data, not arbitrary user categories.

## 6. Database changes and security

- Read relevant migrations in order, including later replacements of the same function/view; the first definition may not describe current behavior.
- Use the existing tables, lots, document headers/lines, permissions and RPCs before adding equivalents. Do not modify historical applied migrations to repair a deployed database; create a new forward migration using the supported CLI workflow.
- Test schema changes in an isolated local/staging environment. Do not reset, reseed, alter policies, create users, or deploy migrations to a hosted project as an incidental test. Follow the task's actual deployment authorization.
- New exposed tables need explicit grants and RLS; views/functions must preserve the intended permission boundary. Preserve default-deny execution grants, especially for privileged functions.
- Existing `SECURITY DEFINER` RPCs require explicit caller/permission checks, controlled search paths and narrow grants. Do not add definer privileges or relax policies to work around a denied request.
- Apply the current paper’s least-privilege intent: confidential financial summaries and expense/finance/user administration are restricted from cashiers; stock movements and report/supplier access require explicit permission; voids/refunds require management authorization. Document Employee/Staff and Manager/Admin as business actor groups mapped to existing roles; the actor labels alone do not authorize privilege changes.
- Backend authorization is mandatory even if a button is hidden. New UI access checks must use explicit supported roles/capabilities, never “not cashier means admin.” Unknown/inactive roles fail closed.
- Privileged service keys stay on the server. Never commit passwords, tokens, live database credentials or privileged keys. Flutter receives only its project URL and publishable client key.
- Preserve concurrency checks and transactional stock/payment invariants. Use request IDs and recovery semantics for operations that could be retried after an unknown outcome.
- Archive referenced master data rather than deleting history. Preserve fields that a partial edit does not change. Do not send placeholder text/null/default zero for unrelated existing data.
- Keep development seed data separate from verified café records. If changing `supabase/demo_seed.sql`, update its pgTAP fixture mirror and satisfy the existing CI comparison.
- Update the dictionary/ERD/security tests when schema or permissions change. Avoid proposing destructive cleanup of legacy recipe tables merely because current screens no longer use them; assess historical dependencies separately.

## 7. Reports and exports

- Build reports from operational tables/views/RPCs through `ReportingRepository` and existing module contracts. Do not create an independently editable reporting database.
- Define formulas and date attribution before implementation. Distinguish pre-discount sales, discounts, refunds, net sales, collections, expenses, purchases, payments and stock costs.
- Use the agreed Asia/Manila business dates even when a client has a different timezone. Specify inclusive user date ranges and consistent query boundaries.
- A current inventory snapshot must be labeled separately from period movements or historical balances. A loss report distinguishes recorded disposal from stock awaiting disposal.
- Totals must cover the full filtered result. Do not sum a first page, `.limit(...)` slice, or top-10 list and label it a complete report. Search and exports must work beyond current record caps.
- On-screen and exported reports share filters and calculation definitions. Preserve references, units, timestamps and numeric precision; handle CSV escaping and formula-like text safely.
- No completed Google Sheets solution claim without an actual export/import or approved integration test. Direct Sheets sync is not implied by CSV support.

## 8. UI/UX and responsiveness

- Reuse `AppColors`, `AppSpacing`, `AppTextStyles`, `AppTheme`, `AppPage`, `AppShell`, `AppDialog`/`showPrototypeDialog`, `DataTableCard`, `ResponsiveFilterBar`, and summary/card patterns where applicable.
- Keep the established Inter typography and red/orange/black/white/gray design. Do not add a second design system, old logo, or unrelated screen redesign.
- Preserve existing widget/helper names, including `showPrototypeDialog`, unless a separately justified cleanup is in scope.
- Use clear action labels and nearby explanations of units, conversions and references. Management features must be discoverable without hovering over unexplained icons.
- Standardize empty/loading/error/retry/saving states. Retain input on failure; prevent repeat submission; explain whether a transaction was saved before offering retry.
- Use stable IDs for selections and predictable sorting/filter state. Growing lists need searchable choices and data-layer pagination.
- Support phone, tablet portrait/landscape, and desktop constraints. Do not use a large fixed dialog width as the only layout solution. Required actions remain reachable with the keyboard open and enlarged text.
- Test complete changed screens, long names, large amounts, empty lists and validation messages. A shared widget passing an overflow test does not prove its consumers are usable.
- Changes to shared widgets/theme/navigation must explain which screens are affected and verify those consumers. Fix common layout behavior once when possible, without broadening the task into a full redesign.

## 9. Refresh and operational failure

Use existing refresh controllers/callbacks for dependent screens after successful mutations. Consider both emitting and receiving notifications. They are in-process notifications; do not describe them as multi-device real-time synchronization.

A remote-change strategy must also handle route return/resume, stale carts, request races and user-visible freshness. Backend stock/authorization checks remain the final guard. Do not discard a form merely because another page refreshed.

Handle configuration/initialization failure and distinguish browser bootstrap/renderer errors from Supabase failures. Offline operation, local queues and printer integration require their own scoped decisions and tests.

## 10. Verification and completion

For each task, verify the actual risk and its TODO acceptance criteria. Use focused tests; do not create tests that merely repeat implementation or perform unrelated test sweeps.

- Dart changes: format changed files, run `flutter analyze` and relevant `flutter test` coverage. Broaden to the suite when required by CI or shared impact.
- Database/security changes: apply the migration to an isolated test database, run relevant pgTAP/CI checks, test allowed/denied roles and transaction rollback/concurrency paths.
- UI changes: verify affected full screens at the TODO viewport matrix and actual target device; include long content, text scaling and keyboard interactions.
- Financial/report changes: reconcile a known dataset across source, screen, receipt and export, including refunds on a later date and periods with no sales.
- Docs-only changes: validate links, names, references, examples and diff. Flutter/database reruns are unnecessary unless an unresolved code concern requires them.
- If Flutter, Docker or another required tool is unavailable, state which tests were not run and the exact remaining validation route. A migration dry-run is not a database test. Never fabricate results.

Report what changed, why, affected requirement/task IDs, validation performed, and material remaining limitations. Update TODO status only with evidence. “Implemented,” “tested,” “business accepted,” and “deployed” are different states.

## 11. Git and team workflow

Inspect branch, status and recent commits first. Fetch the agreed integration branch before branching; do not assume `main` contains active integration work. The audit baseline is `brian/inventory-workflow-navigation`; confirm its current head for future tasks.

Preserve unrelated local changes. Do not hard-reset, clean, discard, or stage everything to resolve routine branch/patch issues. Review generated platform plugin changes individually; commit only those required by intentional dependency changes. Review `pubspec.lock` rather than always discarding it or always staging it.

Use focused branches/commits and PRs. Do not reapply an already-applied patch. Do not push or merge to `main`, deploy, or seed hosted data just because local tests pass. Follow the user's task authorization. Coordinate shared contract/migration changes among teammates before parallel implementation.

A useful task prompt is: “Read AGENTS.md, README.md and TODO.md. Implement task <ID> through the existing architecture. Inspect current code first, meet its acceptance criteria, preserve business invariants, and report verification and remaining limitations.”
