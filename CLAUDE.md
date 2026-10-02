# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Read these first

Street Bowl Café Management System: a Flutter + Supabase app for one café's internal sales, inventory, purchasing, expenses and reporting. It is an **integrated development prototype, not business-ready**.

- [AGENTS.md](AGENTS.md) is the authoritative rulebook (scope discipline, business invariants, database/security rules, UI rules, verification, git workflow). It applies to Claude too. This file does not restate it.
- [README.md](README.md) holds the business baseline, role definitions, and a table of what is present versus missing per module.
- [TODO.md](TODO.md) is the backlog. Work is identified by task ID (`POS-01`, `REP-03`, `SEC-01`, …) grouped into five ordered batches, each with acceptance criteria. Find the task ID before editing and report against it afterwards.

"Implemented", "tested", "business accepted" and "deployed" are different states here. Do not tick a TODO item without evidence, and do not describe a source-level change as verified behavior.

## Commands

```bash
flutter pub get
flutter analyze
flutter test                                              # whole suite
flutter test test/inventory_models_test.dart          # one file
flutter test test/reporting_model_test.dart --plain-name "substring of test name"
dart format <changed files>                               # format only what you touched
```

Run the app (web is the development target; an Android tablet is the business target):

```bash
flutter run -d chrome \
  --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=YOUR_PUBLISHABLE_KEY
```

Both values are read with `String.fromEnvironment` in `lib/main.dart`, so they are compile-time: there is no `.env` file, and omitting either one boots a "Supabase configuration is missing" screen instead of the app. Only the project URL and publishable key ever go to Flutter. Login needs an existing Auth user with a `profiles` row; seed scripts do not create accounts.

Database tests (pgTAP, need a Docker-compatible runtime):

```bash
supabase start        # or: npx supabase start
supabase test db
diff -u supabase/demo_seed.sql supabase/tests/database/fixtures/demo_seed.psql
supabase migration new <name>
```

The `diff` is a CI gate: `demo_seed.sql` and its fixture mirror must stay byte-identical, so edit both together. Database CI pins Supabase CLI `2.109.1`. Local setup order is every file in `supabase/migrations/` by filename, then `supabase/seed.sql` (reference data only), then optionally `supabase/demo_seed.sql`.

If Flutter, Docker or the Supabase CLI is unavailable, say which checks did not run. A migration dry-run is not a database test.

## Architecture

One enforced data path:

**Screen → `lib/domain/repositories/` interface → `lib/data/repositories/Supabase*` → Data API / RPC → PostgreSQL**

- **`lib/app.dart` is the single composition root.** It constructs all ten `Supabase*Repository` instances and passes them to screens by constructor. There is no DI container, router package or state-management library; screens are `StatefulWidget` + `FutureBuilder`. A new module is wired here.
- **Navigation indices are positional.** `_buildAuthenticatedApp` builds `pages` through a local `destination()` closure that assigns `destinationIndex = pages.length` at call time, inside role-conditional blocks. The same screen therefore has a different index for a cashier than for a manager. Never hardcode an index; add destinations through the closure.
- **One screen class, several destinations.** `InventoryScreen` is mounted five times with different `InventoryView` values (overview, release, disposal, adjustment, history). A change to it affects all five sidebar entries.
- **Business logic lives in Postgres, not Dart.** Multi-table writes (checkout, refunds, receiving, stock release, counts, payments) are transactional SQL functions called with `_client.rpc(...)`. Reads usually go through `v_*` views. Repositories map rows to models; they must not orchestrate several writes for one business transaction, and totals shown in the UI are previews of server-computed values.
- **Migrations are append-only and later files redefine earlier objects.** The same function or view is often replaced several times across `supabase/migrations/`. Read them in filename order and treat the last definition as current. Never edit an applied migration; add a new one.
- **Authorization is in the database.** RLS plus explicit permission checks inside `SECURITY DEFINER` RPCs, with a default-deny Data API: a new table, view or function is unreachable from Flutter until a migration grants it. The UI gates on `profile.isCashier` / `!isCashier` in `lib/app.dart`, which is a known shortcut tracked as `SEC-01`. Hiding a button is not authorization, and new UI checks must name explicit roles rather than assume "not cashier means admin".
- **Auth is the one sanctioned exception to the data path.** `lib/screens/auth/auth_gate.dart` and the login screen query Supabase Auth and `profiles`/`roles` directly. Do not use that as precedent for business queries in widgets.
- **Refresh is in-process only.** `BusinessRefreshController` and `InventoryRefreshController` are `ChangeNotifier`s created in `lib/app.dart`; the inventory controller forwards to the business one. Screens take a `refreshListenable` to listen and an `onDataChanged` callback to emit. After adding a mutation, wire both sides. This is not multi-device sync.
- **Mocks cover five of the ten modules** (expense, inventory, order, supplier, user) and exist for isolated tests. They are never a runtime fallback: a failed live call must surface as an error, not mock success.
- **`supabase/functions/create-employee/`** is a Deno Edge Function and the only place a privileged key is used, for administrator-only account creation.

## Domain rules that look like bugs but are deliberate

These are settled business decisions. Do not "fix" them.

- **No recipes.** Prepared-to-order food and drinks do not deduct ingredients, and modifiers change price only. Legacy recipe tables remain in the schema for historical reasons; recipe deduction is retired and must not be restored.
- **Only countable stock is inventory.** Untracked groceries and ingredients are recorded as expenses. Linked countable finished goods do deduct on sale.
- **Expired quantity is not usable quantity.** On-hand, usable and expired are three separate figures. Usable perishable lots allocate first-expire-first-out; disposal is its own recorded action.
- **Package conversions are snapshotted.** Receiving two boxes of 50 adds 100 base pieces as one line. Never require a transaction per unit.
- **History is never destroyed.** Archive master data and correct posted documents through void, reversal or adjustment flows that keep actor, timestamp and reason.
- **Purchases, supplier payments, operating expenses, stock consumption and losses are distinct events.** Do not sum them together or label "net after expenses" as profit.
- **Report dates use Asia/Manila**, whatever the client timezone, and totals must cover the whole filtered result rather than a `.limit(...)` page.
- **Types:** money is `numeric(14,2)`, quantities and conversion factors are `numeric(14,4)`. No floating point for currency.

## Branches

The documentation and both CI workflows refer to an integration branch, `brian/inventory-workflow-navigation`, as the audit baseline and the base for new work. That branch does not exist on this remote, which has only `main` with a single commit. Confirm the intended base with the team before assuming either one. Do not push or merge to `main`, deploy migrations, or seed a hosted project without explicit authorization.
