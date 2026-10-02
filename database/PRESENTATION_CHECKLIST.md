# Prototype Presentation Checklist

Use this checklist for the final rehearsal and on presentation day.

## Before presentation day

- [ ] Use branch `brian/inventory-workflow-navigation` after the Phase 10 patch
  has been applied and pushed.
- [ ] Confirm Flutter CI and Database CI are green on the latest commit.
- [ ] Run `flutter pub get`, `flutter analyze` and `flutter test` locally.
- [ ] Confirm the hosted Supabase project has every migration in
  `supabase/migrations/`.
- [ ] Run the optional `supabase/demo_seed.sql` once in the hosted project's SQL
  Editor.
- [ ] Confirm one manager/admin account and one cashier account can sign in.
- [ ] Do not store or display passwords, service-role keys or database passwords.
- [ ] Prepare new date-based references for goods receipt, stock-out and expense.
- [ ] Rehearse the flow in `database/DEMO_WALKTHROUGH.md` once from start to end.
- [ ] Export or screenshot the core ERD from `database/ERD.drawio` for the slides.

## Runtime command

Use the project URL and **publishable/anon client key**, not the service-role
key. In PowerShell:

```powershell
flutter run -d chrome `
  --dart-define="SUPABASE_URL=https://YOUR_PROJECT.supabase.co" `
  --dart-define="SUPABASE_PUBLISHABLE_KEY=YOUR_PUBLISHABLE_KEY"
```

Replace both placeholders with values from the intended demo project. Keep the
key name `SUPABASE_PUBLISHABLE_KEY`; passing only a raw key without this name
will not configure the application.

## Thirty minutes before the demo

- [ ] Verify internet access and open the application in Chrome.
- [ ] Keep browser zoom at 100% and use a window size already checked for
  overflow.
- [ ] Sign in once as manager and refresh Dashboard, Inventory, Purchasing,
  Expenses and Reports.
- [ ] Verify Davao Packaging Supply, Local Grocery / Supermarket, demo packaging
  items, coffee sizes and modifiers are visible.
- [ ] Verify the receipt/reference numbers prepared for today have not already
  been used.
- [ ] Sign out and confirm the cashier account can also sign in.
- [ ] Close unrelated tabs, notifications and windows.
- [ ] Keep the ERD and walkthrough open in separate tabs for quick reference.

## Live demo order

- [ ] Manager login and dashboard.
- [ ] Multi-item goods receiving with package conversions.
- [ ] Inventory overview and per-item history.
- [ ] Multi-item stock-out/release.
- [ ] Grocery/ingredient expense with supplier and receipt reference.
- [ ] POS order containing a prepared item and a countable finished good.
- [ ] Transaction traceability and period report.
- [ ] Cashier login and restricted navigation.

## Expected proof points

- [ ] One goods receipt produces several inventory lines/lots.
- [ ] Package quantity converts correctly to base pieces.
- [ ] One stock-out releases several supplies atomically.
- [ ] Every displayed stock change links to a source document/reference.
- [ ] Prepared menu items do not deduct recipe ingredients.
- [ ] Countable finished goods deduct from the same inventory shown elsewhere.
- [ ] Grocery ingredients appear as traceable expenses instead of inventory use.
- [ ] Dashboard, Finance and Reports reflect operational transactions.
- [ ] Cashier access is visibly limited and database authorization remains the
  real enforcement boundary.

## Recovery plan

- [ ] If a reference is duplicated, increase its final sequence number and retry.
- [ ] If a page looks stale, navigate away and back or use its refresh action;
  do not create the same transaction twice.
- [ ] If Chrome disconnects, restart with the same `--dart-define` command.
- [ ] If the network or hosted database is unavailable, present the ERD and
  explain the rehearsed workflow; do not claim that screenshots are live data.
- [ ] Do not run `supabase db reset` against the hosted demo project.
- [ ] Do not apply a migration or change RLS during the presentation.

## After the presentation

- [ ] Save the professor/business feedback before implementing new changes.
- [ ] Separate confirmed requirements from interpretations and future ideas.
- [ ] Review whether demo transactions should be retained, voided or removed in
  the development project.
- [ ] Rotate any password or key that was accidentally exposed on screen.
- [ ] Update the business validation checklist and create follow-up issues.
