# Street Bowl Café Database V1

This package is a production-oriented database foundation for the Street Bowl Café Management System.

## Chosen stack

- Flutter client
- Supabase backend platform
- PostgreSQL database
- Supabase Auth
- PostgreSQL Row Level Security (RLS)
- PostgreSQL RPC/functions for critical transactions

The Flutter application should continue to use the repository pattern:

```text
Screen
  ↓
Repository Interface
  ↓
Supabase Repository
  ↓
Supabase Data API / RPC
  ↓
PostgreSQL
```

Do not place SQL or direct database logic inside Flutter screens.

## Business assumptions locked into this version

- One café branch only.
- The system may replace Loyverse if accepted by the business.
- Tax registration is currently unknown.
- Inventory tracks practical countable supplies and countable finished goods.
- Untrackable ingredients and grocery purchases are recorded as expenses rather than measured after every use.
- Menu items may have multiple variants.
- Menu items and variants can opt in/out of inventory tracking.
- Prepared-to-order menu variants do not store recipes or automatically deduct ingredients.
- Modifiers may change price but do not deduct ingredients.
- A stock-in/goods receipt contains one or more supply lines.
- A stock-out transaction contains one or more supply lines.
- Purchase/release packaging uses an explicit conversion, such as one box equals 50 pieces.
- Perishable stock is released by first-expire, first-out (FEFO).
- Dine-in uses a typed table number; there is no table-reservation/floor-plan module.
- No permanent customer master database is required.
- Order records may keep customer/delivery information as transaction snapshots.
- The schema supports multiple payments on one order so split payment can be enabled later without redesigning the database.
- Online payments can store provider/reference information.
- Shift opening/closing cash is supported but optional until validated with the business.
- Purchase orders are supported but not mandatory. Direct supplier receiving is also supported.
- Supplier credit and partial supplier payments are supported but optional.
- Inventory purchases are kept separate from operating expenses.
- Waste, spoilage, damage, expiration, and manual adjustments are recorded as stock movements.
- Full and partial refunds are supported.
- A refund does not automatically put food back into inventory. Any approved physical stock return must be recorded explicitly.
- Thermal printing is treated as a client/device concern; invoice print events and printer metadata can still be audited.
- Tablet use is expected. UUID primary keys and idempotency fields are used to make later offline-first synchronization easier.

## Important production caveats

This schema is intentionally much closer to a real production system than the current Flutter prototype, but deployment still requires:

1. Business validation of shift procedures, supplier workflow, and actual payment methods.
2. Confirmation of VAT / non-VAT registration and BIR requirements.
3. Proper Supabase Auth user provisioning.
4. Final RLS testing.
5. Device/offline synchronization design.
6. Backup/restore testing.
7. Printer integration and invoice layout validation.
8. Real-world user acceptance testing.

Do not claim BIR compliance from this schema alone.

## Installation order

Run all files in `supabase/migrations/` in filename order, then run:

```text
supabase/seed.sql
```

`seed.sql` contains reference/master data only. It does not create an Auth user.

For a presentation environment, optionally run `supabase/demo_seed.sql` after
the base seed. It is safe to rerun and adds realistic master data only. Create
the actual receipts, stock releases, expenses and sales through the application
using [`DEMO_WALKTHROUGH.md`](DEMO_WALKTHROUGH.md).

Presentation resources:

- [`ERD.md`](ERD.md) — complete logical ERD and cardinality explanation;
- [`ERD.drawio`](ERD.drawio) — editable core ERD for diagrams.net/draw.io;
- [`DEMO_WALKTHROUGH.md`](DEMO_WALKTHROUGH.md) — 8–12 minute integrated demo;
- [`PRESENTATION_CHECKLIST.md`](PRESENTATION_CHECKLIST.md) — rehearsal and recovery checklist.

## Automated database tests

The pgTAP regression tests in `supabase/tests/database/` cover cashier
authorization, shift cash handling, POS checkout, finished-good deduction,
multi-item stock-out, packaging conversion, FEFO, partial refunds with explicit
restocking, partial purchase-order receiving, transaction traceability and API
security boundaries. The suite also proves that the optional presentation seed
is repeatable, preserves the no-recipe rule and does not fabricate transaction
history. Security checks include anonymous-access denial, RLS on
public tables, invoker-security views, protected helper functions and explicit
Flutter RPC grants.
Every test runs inside a transaction and rolls back its isolated fixtures.

From the repository root, run:

```bash
supabase start
supabase test db
```

The same commands run in `.github/workflows/database_ci.yml` for integration
branch pushes and pull requests.

## Recommended branch

Example:

```bash
git checkout main
git pull origin main
git checkout -b brian/supabase-database
```

Then copy this package into the repository.

Recommended target structure:

```text
sbc_management_system/
  database/
    README.md
    ERD.md
    DATA_DICTIONARY.md
    BUSINESS_VALIDATION_CHECKLIST.md
  supabase/
    migrations/
    seed.sql
```

## Security rule

Never place a Supabase `service_role` key inside the Flutter application.

The public Data API is default-deny: anonymous users have no access to the
business-data schema, and new database objects receive no client privileges
until a migration explicitly grants them. RLS and internal RPC authorization
remain required even when an object has been granted to `authenticated`.

Manager-created staff accounts should eventually be provisioned through a trusted server or Supabase Edge Function using the Admin API.

## Money and quantity types

- Money: `numeric(14,2)`
- Inventory quantities: `numeric(14,4)`
- Packaging conversion quantities: `numeric(14,4)`

Avoid floating-point types for currency.

## Historical integrity

Business records use soft-deactivation where practical. Historical orders, payments, invoices, stock movements, expenses, and audit records should not be hard-deleted during normal application use.
