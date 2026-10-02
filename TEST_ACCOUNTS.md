# Test accounts

Sign-ins for the hosted Supabase **test** project `ybjyandkpgegrtthokgs`, one per
role, so the app can be tried in each role straight away. They exist only on
that test project; never reuse them on a project that holds real data.

| Role | Email | Password |
| --- | --- | --- |
| Administrator | demo@demo.com | Admin@2026! |
| Cashier | cashier@demo.com | Admin@2026! |
| Manager | manager@demo.com | Admin@2026! |

What each role should see:

- **Administrator:** everything, including role changes in User Management.
- **Manager:** everything the administrator sees, but cannot change anyone's role.
- **Cashier:** Dashboard, Orders / POS, Shifts (own only) and Stock Overview. No
  Finance, Purchasing, Expenses, Reports or Administration, and no Void or Refund
  on orders.

Run the app against the test project as described in `CLAUDE.md` (the project URL
and publishable key go in as `--dart-define` values).
