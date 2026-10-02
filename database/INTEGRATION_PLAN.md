# Flutter / Supabase Integration Plan

Do not connect every screen directly to Supabase.

## Phase 1 — Database only

1. Create Supabase project.
2. Run migrations.
3. Run seed.
4. Create one test Auth user manually.
5. Assign that user the ADMIN role and ACTIVE status through SQL for initial bootstrap.
6. Test schema and RLS before changing Flutter.

## Phase 2 — Infrastructure

Add:

```text
lib/
  data/
    datasources/
      supabase/
        supabase_client_provider.dart
  data/
    repositories/
      supabase_order_repository.dart
      supabase_inventory_repository.dart
      supabase_expense_repository.dart
      supabase_supplier_repository.dart
      supabase_user_repository.dart
      supabase_shift_repository.dart
```

Keep existing interfaces under:

```text
lib/domain/repositories/
```

## Phase 3 — Authentication and shift gate

Flow:

```text
Login
  ↓
Supabase Auth
  ↓
Load profile + role
  ↓
Cashier
  ↓
Orders route
  ↓
Check current_open_shift_id()
  ├─ none → Start Shift
  └─ exists → Orders content
```

Managers may be routed to Dashboard.

## Phase 4 — Orders

Recommended sequence:

1. Create OPEN order.
2. Add order items and modifiers.
3. Apply discount snapshots.
4. Call `recalculate_order_totals`.
5. Call `checkout_order(orderId, paymentsJson)`.
6. RPC atomically:
   - validates active shift
   - validates payment total
   - deducts linked countable finished goods using FEFO
   - leaves prepared-to-order items untracked at ingredient level
   - stores payments
   - completes order
   - issues invoice
   - writes audit records

## Phase 5 — Inventory / procurement

1. Manage inventory master items.
2. Build suppliers.
3. Create optional purchase orders.
4. Record actual goods receipt.
5. Call `post_goods_receipt(receiptId)`.
6. System creates lots and stock movements.
7. Receive multiple supplies under one goods receipt.
8. Release multiple supplies under one stock-out transaction.
9. Store purchase/release package conversion (for example, 1 box = 50 pieces).
10. Display per-item movement history with its source document and external reference.

## Phase 6 — Expenses

Operating expenses and untracked ingredient/grocery purchases should use
`expenses` with date, supplier/grocery, purpose, amount, receipt/reference and
notes.

Inventory purchases should NOT be duplicated into `expenses`.

## Phase 7 — Reports and traceability

1. Use Manila business dates consistently for period filtering.
2. Show gross sold, refunded and net product quantities and sales.
3. Keep the operational tables as the source of truth; expose reporting views
   rather than creating duplicate reporting transactions.
4. Provide one management trace across sales, refunds, goods receipts,
   stock-outs, physical counts, expenses and supplier payments.
5. Preserve readable document numbers, external receipt/payment references,
   supplier/customer context, amount, employee and timestamp where applicable.

## Phase 8 — Refunds

Manager-authorized refunds call `process_refund`.

The database supports partial refund quantities.

Do not automatically add refunded prepared food back to inventory.

## Phase 9 — Offline-first tablet support

Do this after the online version is stable.

Recommended behavior:

- Local queue/database on tablet.
- UUID generated client-side.
- `client_request_id` / `idempotency_key` prevent duplicate sync.
- Menu and inventory reference data cached locally.
- Unsynced orders clearly marked.
- Fiscal/invoice behavior during offline mode must be validated before production.
