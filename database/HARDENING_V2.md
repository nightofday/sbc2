# Database Hardening V2

The database branch now includes a second hardening layer on top of the initial V1 schema.

## Key changes

### Server-authoritative POS pricing

Flutter must not insert trusted price/total fields directly. Use create_order(), add_order_item(), update_order_item_quantity(), remove_order_item(), apply_order_discount(), and checkout_order().

### Inventory ledger

stock_movements is the authoritative stock quantity ledger. inventory_lots exists for expiry, FEFO consumption and cost traceability.

### Discount allocation

order_discount_items records which order lines received a discount. This supports Senior/PWD traceability, partial refunds, tax allocation and reporting.

### Role escalation protection

Managers may manage employee records but cannot assign ADMIN role unless they hold roles.manage.

### Purchase receiving

Posting a goods receipt validates expiry, creates lots and stock movements, then updates the Purchase Order to PARTIALLY_RECEIVED or RECEIVED.

### Supplier credit

Supplier bill payments automatically move bill status from UNPAID to PARTIALLY_PAID to PAID.

### Refunds

Refund amounts are calculated by PostgreSQL from the original sale instead of being trusted from Flutter. Partial and cumulative refunds remain supported.

### Direct-write lockdown

Sensitive client writes are removed for order pricing/totals, modifier pricing, discount amounts, stock movement ledger, inventory lots, and supplier bill payments. Trusted RPCs own these operations.

## Migration order

Run 0001_core.sql through 0007_rls.sql, then 0008_hardening_structure.sql and 0009_hardened_business_functions.sql. Run supabase/seed.sql last.

Do not execute these on a real production project until the acceptance test plan passes in a development Supabase project.