# Street Bowl Café Prototype Demo Walkthrough

This walkthrough demonstrates one connected source of truth across Purchasing,
Inventory, Expenses, POS, Finance and Reports. It is designed for an 8–12
minute presentation and uses realistic master data without fabricating completed
transactions.

## 1. Prepare the demonstration data

Run all migrations and the normal `supabase/seed.sql` first. The optional
`supabase/demo_seed.sql` then adds presentation suppliers, countable packaging
supplies, package conversions, coffee sizes and menu modifiers.

The demo script is safe to rerun. It deliberately does **not** create:

- Supabase Auth users or passwords;
- goods receipts, inventory lots or stock movements;
- completed orders, payments, refunds or expenses.

Those records should be created through the application during the demo so the
audience can see the real workflow and resulting cross-module updates.

For the hosted demo project, open the Supabase SQL Editor and run the contents
of `supabase/demo_seed.sql`. Running `npx supabase db push` does not run this
optional file.

For a fresh local project, the base seed runs with `npx supabase db reset`.
Then run `supabase/demo_seed.sql` against that local database using the SQL
Editor or a PostgreSQL client.

## 2. Prepare the users

Use existing Supabase Auth accounts. Do not put passwords in the repository.

| Account | Role | Used to demonstrate |
|---|---|---|
| Demo manager | ADMIN or MANAGER | Full management workflows and reports |
| Demo cashier | CASHIER | Restricted POS and stock-view access |

If the cashier account does not exist, an administrator can create it from the
Users module before the presentation. Use a temporary password of at least
eight characters and change it after the demo.

## 3. Use unique presentation references

Receipt/reference values are intentionally traceable and may be unique per
supplier. Use the current date and a sequence so repeated rehearsals do not
collide.

| Workflow | Example reference |
|---|---|
| Goods receipt | `DEMO-GR-20260930-01` |
| Grocery expense | `DEMO-EXP-20260930-01` |
| Stock-out | `DEMO-SO-20260930-01` |
| Supplier payment | `DEMO-PAY-20260930-01` |

Increase the final number for every rehearsal.

## 4. Recommended live demonstration

### Step 1 — Explain the dashboard and roles (about 1 minute)

1. Sign in with the manager account.
2. Show the grouped navigation and responsive layout.
3. Explain that role visibility is a convenience; the database also checks
   authorization before sensitive changes.
4. Open the Dashboard and state that its numbers come from the same transactions
   used by the operational modules.

### Step 2 — Receive multiple countable supplies (about 2 minutes)

1. Open **Purchasing → Goods Receiving**.
2. Select **Davao Packaging Supply**.
3. Enter a unique supplier receipt reference and the actual receipt date.
4. Add at least two lines, for example:

   | Supply | Purchase quantity | Purchase unit | Conversion |
   |---|---:|---|---:|
   | 16 oz Cold Cups | 2 | box | 50 pieces per box |
   | Kraft Meal Bowls | 2 | pack | 25 pieces per pack |

5. Post the receipt.
6. Point out that one receipt contains many items, each line creates a traceable
   inventory lot, and the package quantity is converted into base pieces.

Expected result: Inventory increases by 100 cups and 50 bowls and the receipt
appears in transaction traceability.

### Step 3 — Show inventory truth and multi-item release (about 2 minutes)

1. Open **Inventory → Stock Overview** and verify the received balances.
2. Open one item and show its lot/history entry with the goods receipt reference.
3. Open **Release Supplies**.
4. Add cups and bowls to one stock-out transaction, enter a purpose such as
   `Released to service counter`, and use a unique stock-out reference.
5. Post the transaction and return to Stock Overview.

Expected result: both supplies decrease together, one stock-out header contains
many lines, and Inventory History links each movement to the same document.

When an item has expiration dates, explain that usable stock is released by
first-expire, first-out (FEFO). Expired quantities remain visible but cannot be
released or sold until they are disposed of.

### Step 4 — Record untracked grocery ingredients as an expense (about 1 minute)

1. Open **Expenses → Add Expense**.
2. Select **Local Grocery / Supermarket**.
3. Choose the untracked grocery/ingredient category.
4. Enter a purpose such as `Milk, syrup and seasonings`, an amount, receipt date
   and a unique grocery receipt reference.
5. Save the expense.

Explain that these ingredients are intentionally not measured per millilitre or
deducted from recipes. The business records the purchase as a traceable expense,
which matches the consultation feedback and avoids inaccurate manual work.

### Step 5 — Process a POS sale (about 2 minutes)

1. Open **Orders / POS**.
2. Add a prepared item such as Chicken Bowl and choose an add-on.
3. Add one countable finished product such as Bottled Water or Coca-Cola.
4. Complete payment and open the receipt/order details.

Expected result:

- the bowl and add-on affect the order price but do not deduct secret recipe
  ingredients;
- the linked bottled finished good deducts one unit from Inventory;
- the order, payment, stock movement and report totals share the same source
  transaction.

### Step 6 — Show traceability and reports (about 1–2 minutes)

1. Open **Reports → Transaction Traceability**.
2. Search the order number, goods receipt reference, stock-out reference or
   expense reference created during the demo.
3. Open **Reports Overview** or **Sales & Finance** and use a period containing
   today's transactions.
4. Point out gross sale, refund, expense and net reporting behavior.

### Step 7 — Confirm cashier RBAC (about 1 minute)

1. Sign out and sign in with the cashier account.
2. Show that the cashier sees the operational POS/stock-view destinations but
   not management administration and financial workflows.
3. If time allows, explain that direct unauthorized database operations are
   rejected even when someone bypasses the navigation.

## 5. Optional demonstrations

- **Refund:** partially refund the bottled item. Restock only if the sealed
  physical product is actually returned and approved.
- **Physical count:** count several items in one session and post the variances
  as one traceable document.
- **Disposal:** choose the exact expired/damaged lot and provide a written
  reason; do not use stock-out for waste.
- **Purchase order:** create and approve a PO, receive only part of it, then
  receive the remainder and show the status progression.

## 6. Statements to avoid

The prototype is not yet a claim of:

- BIR or final regulatory compliance;
- production readiness or completed user acceptance testing;
- offline operation or automatic conflict resolution;
- automatic prepared-food recipe or ingredient deduction;
- finalized real suppliers, prices, opening balances or business policies.

State instead that this is an integrated functional prototype for business
validation, with traceable database-backed workflows and documented decisions
still requiring café confirmation.

## 7. Feedback to capture after the demo

- Which supplies are practical enough to count?
- What are the actual box/pack sizes and preferred units?
- Who may receive, release, dispose and adjust stock?
- Are purchase orders used, or is direct receiving the normal process?
- Which expenses and grocery purchases need separate categories?
- Which payment methods, receipt fields and refund approvals are required?
- Which reports are needed daily, weekly and monthly?

Record the answers in `database/BUSINESS_VALIDATION_CHECKLIST.md` before changing
the production design.
