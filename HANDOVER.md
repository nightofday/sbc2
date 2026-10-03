# Handover to Brian

From Charlie, 3 October 2026. Work done with Claude Code over 2–3 October 2026.

You asked me to make the app usable for the café. This is what changed, how to try it, what I decided on your behalf, and what is still open. The full record, with evidence for every change, is in [READINESS_LOG.md](READINESS_LOG.md).

## Where the work is

| | |
| --- | --- |
| Repository | `nightofday/sbc2`, branch `charlie` (I have no write access to `bbriones559657/sbc2`) |
| Based on | your `main`, commit `59db8c8` |
| Size | 52 commits, 166 files, about 26,500 lines added and 2,300 removed |
| Merged anywhere? | No. Nothing was pushed or merged to `main` on either repository |
| Database | 13 new migrations, applied **only** to a separate hosted test project (`ybjyandkpgegrtthokgs`). Your projects were not touched |

The documentation names `brian/inventory-workflow-navigation` as the base branch, but that branch does not exist on your remote, so I branched from `main`. Tell me if the work should be rebased onto another branch.

## Try it in five minutes

1. Run the app against the test project:

   ```bash
   flutter run -d chrome \
     --dart-define=SUPABASE_URL=https://ybjyandkpgegrtthokgs.supabase.co \
     --dart-define=SUPABASE_PUBLISHABLE_KEY=sb_publishable_TTKpkE6cHbKgT9YA6oUxSQ_AUWrkBmk
   ```

2. Sign in with one of the accounts in [TEST_ACCOUNTS.md](TEST_ACCOUNTS.md) (administrator, manager, cashier). They exist only on the test project.
3. Things worth trying:
   - **Orders / POS → New Order:** start a shift with opening cash, sell, use the quick cash buttons, hold an order and continue it, copy the receipt.
   - **Shifts:** open the shift report; end a shift and it opens automatically.
   - **Purchasing:** purchase order → approve → receive. Then **Finance Overview → Recent Supplier Payments**: pay a bill and reverse the payment.
   - **Inventory History:** reverse a write-off.
   - **Reports:** any date range; Download Whole Report (CSV) saves a file that opens in Excel or Google Sheets. Transaction Traceability and the Audit Log have the same button.
   - **Administration → Audit Log:** every price, role and settings change, with before and after values.
   - Sign in as the cashier to see what that role can and cannot reach.

The test project contains test data from this work (names starting with `TEST`, orders `#149`–`#151`, PO-15 and so on). Order and document numbers jump because database tests run inside rolled-back transactions, which still use up the sequences.

## What changed

### Fixed

- **Crashes and stale screens:** dialogs crashed while closing; the dashboard did not redraw after changes; every sign-in refresh reloaded the whole app and threw away an open cart.
- **Blank forms:** the shared dialog went blank when its content adapted to its width. It showed up in the purchase order form after adding an item.
- **Reversed lists:** every list was sorted backwards. The Supabase client sorts descending unless told otherwise, and 32 queries gave no direction.
- **Wrong business date:** dates used the server's UTC date, a day behind Manila until 8 a.m. They now use `business_today()` (Asia/Manila).
- **Double posting:** a lost response could post a sale, refund, stock movement or payment twice. Every posting function now takes a request ID and every form sends one.
- **Direct writes:** posted records could be inserted, edited or deleted directly through the Data API. Those write paths are closed; changes go through the functions only.
- **Android release build:** it had no internet permission, which only the debug manifest declared.
- **`create-employee` Edge Function:** it updated the role with the service key, which the profile guard refuses. It now assigns the role as the requesting administrator. It is deployed to the test project, and Charlie has created a cashier and a manager with it.

### Added

| Area | What it does |
| --- | --- |
| Offline till | The till keeps selling when the connection drops. Sales are stored on the device with their request ID and sent later, oldest first, and are never recorded twice. A shift can be opened offline; the till reopens offline for someone who has signed in on that device before. A banner shows the offline state and any sale the server refused |
| Corrections | Void with reason for expenses, goods receipts, supply releases and stock counts. Reversal of supplier payments (a linked negative payment) and of stock write-offs (a linked `REVERSAL` movement). Voided documents stay visible in Transaction Traceability with their reason |
| Reports | One `get_business_report(from, to)` behind Reports, Finance and the Dashboard, with written sales definitions. Any date range |
| Export | CSV export of the whole report, each report section, Transaction Traceability and the Audit Log. In the browser it downloads the file; on Android and iOS it opens the share sheet (save, email, Google Drive). Copy-for-spreadsheet buttons remain, and every copy button now says when copying fails |
| Shifts | Opening cash at shift start, a shift (Z) report, and a Shifts screen with expected cash, counted cash and the difference |
| Audit log | Changes to prices, menu, options, discounts, suppliers, stock items, staff accounts and settings are recorded with before and after values. A screen reads them |
| Menu | Category management, promotional discount management (fixed or adjustable, limits, validity dates), modifier management (shared groups, reordering) |
| Till | Hold and continue orders, quick cash amounts, options and notes on receipts, date and time on receipts, copy receipt as text, refunded amounts on orders |
| Purchasing | Supplier contact details as separate fields; receiving remembers each supplier's pack size and last cost |
| Accounts | `bootstrap_first_admin(email)` for the first administrator (SQL editor only), a guard that keeps one active administrator, profile emails that follow the sign-in email |
| Settings | A Business Details screen for the receipt header (name, address, TIN) and the shift cash rules |
| Permissions | Every screen and action checks a named permission (`profile.can('menu.manage')`) instead of "not a cashier" |
| Layout | Tables no longer scroll sideways on tablets. When columns do not fit, each row becomes labelled values. On a phone the till shows products as compact rows |

### Removed

- Mock repositories and `mock_data.dart`. They shipped sample data in the app, and only tests used one of them; that one moved to `test/support/`.
- Repository methods no screen called.
- Six unused reporting views and three unused functions: the first `place_order`, `update_order_item_quantity` and `remove_order_item`. No stored data was removed.

## Decisions I made that you should check

| Decision | What I chose | Where to read more |
| --- | --- | --- |
| Offline selling | Built it, although README and AGENTS.md treat offline as out of scope pending a decision (`OPS-02`). Charlie set it as a requirement | READINESS_LOG §5 "Offline till status", §7 |
| Offline prices | The server re-prices an offline sale from the current menu and records any difference from what the till charged in the audit log | same |
| Offline receipt numbers | Assigned by the server at sync; the offline receipt carries an `OFFLINE-` reference | same |
| Report definitions | Gross is before discounts, refunds count on the refund date, net = gross − discounts − refunds | READINESS_LOG "Report definitions" |
| Wrong stock adjustment | Corrected by another adjustment; no separate void | READINESS_LOG "Accounts, audit and reversals status" |
| Held orders | Kept on the device that held them, not in the database, and in no report until paid | READINESS_LOG §5 |
| AGENTS.md | Two sentences about mock repositories now say test fakes live in `test/support/` | `git diff 59db8c8 charlie -- AGENTS.md` |
| Test credentials | Committed in `TEST_ACCOUNTS.md` on purpose, for the test project only | — |

I kept your retired recipe tables. AGENTS.md asks for a history check before removing them, and only you can do that.

## New dependencies

| Package | Why | Note |
| --- | --- | --- |
| `shared_preferences` | Stores the offline sales queue and the till's cached data on the device | Was already installed as a dependency of `supabase_flutter`; now listed directly |
| `web` | Saves export files in the browser | Same: already installed, now listed directly |
| `share_plus` | Opens the share sheet for export files on Android and iOS | New. Charlie approved it on 3 October 2026 |

## How it was tested

- **Flutter:** `flutter analyze` is clean and 102 tests pass. They include a simulated lost connection at checkout, an offline sale replayed to a fake server, a report shared as a CSV file, and layouts at 360, 800 and 1280 px.
- **Database:** 22 pgTAP files with 439 assertions, all passing. Docker is not installed on Charlie's machine, so each file ran against the hosted test project inside a transaction that was rolled back. The method is in READINESS_LOG "How the database changes were tested without Docker".
- **In the app:** Charlie and I clicked through every form as an administrator, on the test project. Charlie checked the cashier and manager roles.

**Not tested:**
- An Android device or an Android build (no Android SDK here). That includes the share sheet for exports and whether `share_plus` builds with your Android settings.
- A real loss of network.
- The GitHub CI workflows, which have never run on this branch.

## Before this goes near real data

1. Review the branch, ideally as a pull request into your integration branch.
2. Run CI. Locally, run `supabase test db`, and diff `supabase/demo_seed.sql` against `supabase/tests/database/fixtures/demo_seed.psql`. Both were changed together and should be identical.
3. Apply the 13 migrations from `20261002132705` to `20261002250000` in order on a fresh project, then deploy `create-employee`.
4. Set up the first administrator with `select public.bootstrap_first_admin('email');`.
5. Change the application ID `com.example.sbc_management_system`, set up release signing, and test a release build on the tablet, including pulling the network.
6. Split the sample data out of `seed.sql` (`DOC-01`).

## Still open

**Business decisions:**
- The report definitions.
- Senior citizen and PWD discounts, VAT, and what an official receipt must show (`OPS-03`).
- Whether cashiers may give discounts or refunds (today they cannot).
- Receipt printing (`OPS-02`).
- The offline choices above.

**Work not done:**
- Open tickets shared between devices.
- Split payments.
- PIN sign-in.
- Receipt printing.
- A maintained stock balance and per-device invoice numbers.
- Fixing pgTAP files `02` and `03`, which assume an empty database.

**Design:** the visual design is unchanged from yours. Charlie is handing the visual design to Claude Design. A Material 3 restyle was tried and reverted in full.
