# Standalone Migration Guide

This guide explains how to turn this repo from an Actual Budget HTTP client into a standalone iOS app that:

1. First stores the user’s budget locally on-device with no Actual server requirement.
2. Later adds a thin iCloud persistence wrapper so that same local budget can sync across the user’s Apple devices.
3. Imports bank data directly from SimpleFIN without relying on an Actual router or HTTP wrapper.
4. Can import from an Actual Budget backup SQLite file.

This is intentionally written as an implementation playbook, not a high-level brainstorm. Follow the sections in order. Each section ends with a clear test checkpoint so you can stop, verify, and only then continue.

---

## 0. What exists today

Before changing anything, understand the current architecture:

- `iOSApp/Shared/AppState.swift` stores `baseURLString`, `apiKey`, `syncId`, and `budgetEncryptionPassword` in `UserDefaults`.
- `iOSApp/Networking/DemoDataService.swift` powers the current sample/demo mode.
- `iOSApp/Features/Onboarding/OnboardingView.swift` is a server login screen.
- `iOSApp/Features/Settings/SettingsView.swift` exposes those server settings again.
- `iOSApp/Networking/ActualAPIClient.swift` is the app’s core data layer. Every screen depends on it.
- `iOSApp/Networking/APIEndpoints.swift` hardcodes the HTTP wrapper routes.
- `iOSApp/Features/Dashboard/DashboardView.swift`, `AccountsView.swift`, `TransactionsView.swift`, `AllTransactionsView.swift`, `BudgetView.swift`, and `TransactionEditor.swift` all create `ActualAPIClient` directly.
- `iOSApp/Features/Accounts/AccountsView.swift` also makes a raw `GET /accounts/{id}/balance` request outside the main client.
- `swagger.json` describes the current HTTP-wrapper API contract.

Important conclusion:

- This app is not “partly standalone.”
- It is currently a native UI shell around a remote Actual-compatible HTTP API.
- To become standalone, you must replace the storage layer, the sync model, and the bank sync path.

---

## 1. The target architecture

Do not try to preserve the current architecture and just “swap the URL.” That will produce a fragile mess.

Build toward this architecture:

- `AppState` becomes app/session state, not server-credential state.
- A `BudgetStore` persists all domain data locally on-device.
- A `BudgetRepository` exposes read/write operations used by the UI.
- A `BudgetCalculator` derives dashboard and monthly budget values from local data.
- A `SimpleFINClient` talks directly to the SimpleFIN endpoints.
- A `SimpleFINImportCoordinator` maps downloaded SimpleFIN accounts and transactions into local budget records.
- Later, an optional `BudgetPersistenceAdapter` wraps that same local store and mirrors it to iCloud.

Use this mental model:

- Current app: `SwiftUI -> HTTP client -> Actual wrapper -> Actual server`
- Phase 1 target: `SwiftUI -> repository -> local SQLite store`
- Phase 2 target: `SwiftUI -> repository -> local SQLite store -> iCloud wrapper`

---

## 2. Key product decision you must lock first

Do this before writing code.

Decision:

- Treat the budget as a local SQLite-backed app dataset first, and only later wrap it in iCloud persistence.

Why this is the correct choice for this repo:

- The app is currently tightly coupled to a remote HTTP backend, so the first hard problem is replacing that backend with a trustworthy local source of truth.
- Local-first lets you debug the budget engine, transaction CRUD, budget math, and SimpleFIN import without mixing in iCloud coordination bugs yet.
- Once the local store is stable, an iCloud wrapper can sync the exact same SQLite file or app-owned package instead of forcing a second architecture rewrite.
- Actual backups are already SQLite-based, so a local SQLite store makes backup import much more direct.

Do not choose this unless you have a strong reason otherwise:

- Do not use `UserDefaults` for budget storage.
- Do not use a pile of JSON files with ad-hoc file locking.
- Do not start with CloudKit-only records unless you want to redesign the whole domain model around record sync and conflict resolution.

Recommended phase 1 file format:

- A single app-owned SQLite file such as `budget.sqlite`
- Plus a tiny metadata sidecar such as `budget-metadata.json` if needed

Recommended phase 2 iCloud wrapper format:

- Promote that local store into a package such as `My Budget.actualbundle`
- Inside it, store:
  - `budget.sqlite`
  - `metadata.json`
  - optionally `attachments/`

Why this split is better:

- Phase 1 keeps the standalone rewrite simpler.
- Phase 2 can adopt Apple’s file package pattern without forcing document APIs into every early step.

Test checkpoint:

- You can explain, in one sentence, that phase 1 uses one local SQLite budget as the source of truth, and phase 2 only adds iCloud replication around it.

---

## 3. External constraints you should design around

These facts matter for the implementation:

- Actual’s official API docs say the official supported programmatic API is the Node package `@actual-app/api`, not a native Swift SDK.
- Actual’s API docs also note `init()` can run in local-only mode, which is useful conceptually, but this repo is pure Swift and does not already embed the JS runtime or Actual core.
- SimpleFIN’s protocol is direct and simple:
  - User gets a setup token.
  - App base64-decodes it to a claim URL.
  - App `POST`s the claim URL once.
  - App receives an access URL with embedded Basic Auth credentials.
  - App `GET`s `/accounts?version=2`.
- SimpleFIN Bridge expects low request volume and says the intended rate is about 24 requests or fewer per day.
- SimpleFIN currently exposes at most 90 days per request window.
- Actual’s SimpleFIN docs say Actual’s built-in SimpleFIN support currently pulls at most 90 days of data and updates roughly once every 24 hours.

Practical implication:

- Do not poll SimpleFIN aggressively.
- Build an importer that is idempotent and remembers the last successful sync window.

---

## 4. Migration strategy

Do not rewrite the app all at once.

Use this order:

1. Add new abstractions while the old app still works.
2. Build local storage and calculators behind those abstractions.
3. Replace one screen at a time to read from the local repository.
4. Remove demo mode, server onboarding, and server settings only after all screens are local.
5. Add import from Actual backup SQLite files.
6. Add SimpleFIN import after local storage is stable.
7. Add iCloud persistence last as a thin wrapper around the proven local store.

This order matters because:

- If you remove the old networking layer first, you will break every screen.
- If you add SimpleFIN before local persistence exists, you will have nowhere trustworthy to store imported data.
- If you add iCloud too early, you will waste time debugging sync and file coordination before you know the local budget engine is correct.

---

## 5. New folder structure to create

Create these new groups in `iOSApp`:

```text
Data/
  Persistence/
  Repository/
  Importing/
  Migration/
  Sync/

Domain/
  Models/
  Services/
  Calculators/

Features/
  BudgetSelection/
  BankConnections/
```

Recommended new files:

```text
iOSApp/Data/Persistence/BudgetStore.swift
iOSApp/Data/Persistence/SQLiteBudgetStore.swift
iOSApp/Data/Persistence/LocalBudgetFileManager.swift
iOSApp/Data/Repository/BudgetRepository.swift
iOSApp/Data/Repository/LocalBudgetRepository.swift
iOSApp/Data/Importing/SimpleFINClient.swift
iOSApp/Data/Importing/SimpleFINModels.swift
iOSApp/Data/Importing/SimpleFINCredentialStore.swift
iOSApp/Data/Importing/SimpleFINImportCoordinator.swift
iOSApp/Data/Migration/ActualBackupSQLiteImporter.swift
iOSApp/Data/Migration/ActualHTTPMigrationImporter.swift
iOSApp/Data/Sync/ICloudBudgetSyncAdapter.swift
iOSApp/Domain/Calculators/BudgetCalculator.swift
iOSApp/Domain/Calculators/DashboardCalculator.swift
iOSApp/Features/BudgetSelection/BudgetSelectionView.swift
iOSApp/Features/BankConnections/BankConnectionsView.swift
```

You do not need all business logic on day one, but create the structure first so the migration stays organized.

Test checkpoint:

- Project builds after creating empty stubs for the new files and adding them to `project.yml`.

---

## 6. Build local storage first and postpone iCloud

This is a deliberate change from the original plan.

Do not add iCloud first.

Why:

- iCloud is not the core product rewrite. Local storage is.
- You can validate most of the migration in simulator and on-device without any Apple container setup.
- Importing from an Actual backup SQLite file becomes much easier if your local store already exists.

Phase 1 storage target:

- One app-owned SQLite file in the app’s Application Support directory

Suggested location:

- `Application Support/Budgets/default/budget.sqlite`

Create:

- `LocalBudgetFileManager.swift`

Responsibilities:

- Resolve the Application Support path
- Create the budget directory if missing
- Return the SQLite file URL
- Handle backup/export paths later

Important:

- Keep the file path deterministic.
- Do not hide the active budget behind random temporary files.

Test checkpoint:

- On first launch, the app can create `budget.sqlite` in Application Support and reopen it after relaunch.

---

## 7. Replace server-centric `AppState`

Current problem:

- `AppState` is basically a server session object.

Target:

- `AppState` should describe the local app session.

Delete or deprecate these properties:

- `baseURLString`
- `apiKey`
- `syncId`
- `budgetEncryptionPassword`
- `isDemoMode`

Replace them with something like:

```swift
@Published var selectedBudgetID: String
@Published var selectedBudgetDisplayName: String
@Published var currencyCode: String
@Published var currentTheme: Theme
@Published var onboardingState: OnboardingState
```

Define `OnboardingState` roughly like this:

```swift
enum OnboardingState {
    case noBudgetSelected
    case creatingBudget
    case openingBudget
    case ready
}
```

Also add a long-lived repository handle:

```swift
@MainActor
final class AppState: ObservableObject {
    @Published var repository: BudgetRepository?
}
```

Why:

- Views should not keep reconstructing storage clients from raw strings.
- The selected budget should become a real application session.

Test checkpoint:

- App compiles with `AppState` no longer containing server credentials or demo-mode state.
- Root flow can distinguish “no budget selected” from “budget open.”

---

## 8. Build the local budget file layer

This is the most important foundational step.

Start with a plain local file layer, not `UIDocument`.

Create `LocalBudgetFileManager.swift`.

Responsibilities:

- Own the local budget file URL for the active budget.
- Create the directory structure for the active budget.
- Create a new empty SQLite file when needed.
- Return helper URLs for:
  - `budget.sqlite`
  - `budget-metadata.json`
  - exported backups

Implementation approach:

1. Use Application Support, not Documents, for the active working database.
2. Create one folder per budget, even if v1 only supports one budget.
3. Save small app-owned metadata in JSON if needed.
4. Keep this layer dumb. No SQL logic here.

Suggested layout:

```text
Application Support/
  Budgets/
    default/
      budget.sqlite
      budget-metadata.json
```

Do not skip this manager. If file URL handling is spread across views or repositories, the app will become impossible to reason about.

Test checkpoint:

- App can create a new empty local budget directory and reopen the same budget after relaunch.

---

## 9. Choose and implement the local persistence engine

You have two realistic options:

Option A:

- SQLite directly

Option B:

- SwiftData or Core Data backed by SQLite

Recommended for this repo:

- SQLite directly, with a thin Swift wrapper.

Why I recommend SQLite directly here:

- The app already thinks in terms of explicit tables and ledger data.
- A plain local `budget.sqlite` file is straightforward.
- You avoid SwiftData + iCloud edge cases while still using iCloud document sync for the whole file.
- Imported transaction deduplication and manual SQL migrations are easier to reason about.

Create `SQLiteBudgetStore.swift`.

Initial tables you need:

- `accounts`
- `categories`
- `payees`
- `transactions`
- `budget_months`
- `budget_category_groups`
- `budget_category_values`
- `simplefin_connections`
- `simplefin_account_links`
- `import_runs`
- `app_metadata`

Minimum fields to carry over from the current app:

- `accounts`: `id`, `name`, `offbudget`, `closed`, `sort_order`, `balance_current`
- `categories`: `id`, `name`, `group_id`, `is_income`, `hidden`
- `payees`: `id`, `name`, `category_id`, `transfer_account_id`
- `transactions`: `id`, `account_id`, `date`, `amount`, `payee_id`, `payee_name`, `category_id`, `notes`, `imported_id`, `transfer_id`, `cleared`, `pending`, `source`
- `budget_months`: derived cache if you choose to materialize monthly summaries
- `simplefin_connections`: connection/account metadata plus last sync timestamps
- `simplefin_account_links`: mapping from SimpleFIN account IDs to local account IDs
- `import_runs`: last success, window start, window end, error summary

Very important design choice:

- Add a `source` column to transactions with values like `manual`, `simplefin`, `migration`.

Also add uniqueness constraints:

- `transactions.id` as primary key for local transactions
- `transactions.imported_id` plus `account_id` unique when present
- `simplefin_account_links(simplefin_account_id)` unique

Why:

- Idempotent imports are impossible without stable keys.

Test checkpoint:

- You can create the SQLite database in Application Support.
- A unit test can insert and read back one account, one category, one payee, and one transaction.

---

## 10. Define repository interfaces before moving any screen

Create a protocol:

```swift
protocol BudgetRepository {
    func fetchAccounts() async throws -> [Account]
    func fetchCategories() async throws -> [Category]
    func fetchPayees() async throws -> [Payee]
    func fetchTransactions(accountId: String, since: String?) async throws -> [Transaction]
    func fetchAllTransactions(since: String?) async throws -> [Transaction]
    func fetchAccountBalance(accountId: String) async throws -> Int
    func createTransaction(_ transaction: Transaction) async throws
    func updateTransaction(_ transaction: Transaction) async throws
    func deleteTransaction(id: String) async throws
    func createAccount(name: String, offbudget: Bool) async throws -> String
    func fetchBudgetMonth(_ month: String) async throws -> BudgetMonth
    func fetchBudgetMonthCategoryGroups(_ month: String) async throws -> [BudgetMonthCategoryGroup]
}
```

Then create:

- `LocalBudgetRepository`

During transition, you may temporarily also create:

- `RemoteActualRepository`

That temporary adapter can wrap the existing `ActualAPIClient` so you can migrate screen by screen.

Why this step matters:

- Right now every view knows too much about how data is fetched.
- The repository layer is the seam that lets you replace the backend without rewriting every screen twice.

Test checkpoint:

- `DashboardView` can be made to accept a repository injected from `AppState` without changing its visible behavior yet.

---

## 11. Move all client creation out of views

This is the first real refactor to do in the UI layer.

Current anti-pattern:

- Every major screen has a private `client()` helper that builds `ActualAPIClient`.

Files to refactor:

- `iOSApp/Features/Dashboard/DashboardView.swift`
- `iOSApp/Features/Accounts/AccountsView.swift`
- `iOSApp/Features/Transactions/TransactionsView.swift`
- `iOSApp/Features/Transactions/AllTransactionsView.swift`
- `iOSApp/Features/Transactions/TransactionEditor.swift`
- `iOSApp/Features/Budget/BudgetView.swift`

Steps:

1. Add `@EnvironmentObject private var appState: AppState`.
2. Add a local computed property:

```swift
private var repository: BudgetRepository {
    guard let repository = appState.repository else {
        fatalError("Repository missing")
    }
    return repository
}
```

3. Replace all `client().fetch...` calls with `repository.fetch...`.
4. Replace the custom raw balance request in `AccountsView` with `repository.fetchAccountBalance(accountId:)`.

Do this before implementing the local repository in full if needed by using a temporary remote adapter.

Test checkpoint:

- All screens compile without importing or constructing `ActualAPIClient` directly.

---

## 12. Rebuild onboarding around budget selection, not server login

Current onboarding is wrong for the standalone app because it asks for:

- Base URL
- API key
- Sync ID
- Encryption password

Delete that entire mental model.

Replace `OnboardingView` with a local-first flow:

Screen 1:

- “Choose or Create Budget”

Buttons:

- `Create New Local Budget`
- `Open Existing Budget`

New flow details:

1. User taps `Create New Local Budget`.
2. App asks for a budget name.
3. `LocalBudgetFileManager` creates the local budget folder and `budget.sqlite`.
4. App opens the local store.
5. App seeds starter data:
   - default categories
   - default budget groups
   - zero starter accounts if you want
6. App stores a persistent identifier for the selected local budget.
7. App transitions to the main app.

Also add:

- `BudgetSelectionView` for switching between multiple budgets later.

Test checkpoint:

- Fresh install on a real device can create a new budget and reach the main tabs with no server credentials anywhere.

---

## 13. Rebuild settings around local budget status and bank connections

Current settings are dominated by server connection fields. Remove them.

Replace the “Connection” card in `SettingsView` with:

- Current budget name
- Local budget path or identifier
- Last local save timestamp
- Button to switch budget
- Button to export/share budget file
- Button to open bank connections
- Button to clear local selection if needed

Keep:

- Theme
- Currency
- Logs

Add:

- “Open in Files” or “Reveal Budget Folder” if useful
- “Rebuild Derived Data” debug action
- “Run SimpleFIN Sync Now” debug action
- Later, after phase 2, add:
  - iCloud sync status
  - last iCloud sync timestamp

Test checkpoint:

- Settings no longer shows `Base URL`, `API Key`, `Sync ID`, or encryption password fields.

---

## 14. Implement local domain calculations

Today, several values are effectively computed by the remote Actual layer. In standalone mode you must compute them locally.

Create:

- `DashboardCalculator`
- `BudgetCalculator`

Responsibilities of `DashboardCalculator`:

- spent today
- spent this month
- spent last month
- recent non-transfer transactions
- total balance across account groups

Responsibilities of `BudgetCalculator`:

- monthly totals
- per-group totals
- per-category balances
- `toBudget`
- `incomeAvailable`

Important product truth:

- The current app only reads budget month summary data.
- It does not yet expose full Actual-style budget editing behavior.
- That means you can start by computing read-only monthly summaries from local tables.

Good implementation path:

1. Store monthly category budget assignments in `budget_category_values`.
2. Compute spent amounts from transactions by category and month.
3. Compute category balances as `budgeted - spent` plus carryover when applicable.
4. Materialize a `BudgetMonth` and `[BudgetMonthCategoryGroup]` value for the UI.

Be careful here:

- Transfer transactions should not be treated as spending.
- Income categories should be separated from spending categories.
- Dates must be normalized to `yyyy-MM-dd`.

Test checkpoint:

- `BudgetView` renders correctly using local calculated month data.
- `DashboardView` numbers match manual expectations for a seeded sample budget.

---

## 15. Seed starter data for new budgets

A new blank budget with zero categories is a bad first-run experience.

Create a seeding service:

- `BudgetSeeder.swift`

Seed at minimum:

- Core category groups
- A few starter categories
- One default payee if useful
- App metadata like schema version and created timestamp

Suggested starter groups:

- Income
- Fixed Expenses
- Flexible Spending
- Savings
- Debt

Store a schema version in `app_metadata`.

Why:

- You will need schema migrations later.

Test checkpoint:

- Creating a new budget results in a usable dashboard, budget view, and transaction editor without any manual database setup.

---

## 16. Implement safe local write transactions

Do not let repository writes happen without telling the persistence layer that the database changed.

Pattern to use:

1. Repository begins a SQLite transaction.
2. Repository writes.
3. Repository commits.
4. Repository informs a persistence coordinator that the database changed.
5. The persistence coordinator updates `lastModifiedAt`, triggers backup/export hooks if needed, and later gives iCloud sync something deterministic to watch.

You can implement a callback from store to the persistence coordinator, for example:

```swift
var onDidMutate: (() -> Void)?
```

Then after successful commits:

```swift
onDidMutate?()
```

Why:

- If you skip centralized mutation tracking, later backup, export, and iCloud sync behavior will become unreliable.

Test checkpoint:

- After editing a transaction, quitting the app, and reopening on the same device, the change persists.

---

## 17. Add local integrity checks before adding iCloud

Do not wait until iCloud exists to think about corruption and recovery.

Minimum local safety policy:

- Run `PRAGMA integrity_check` when opening the database in debug builds.
- Keep a rolling local backup copy before destructive migrations.
- Store schema version and last successful open timestamp in metadata.
- Refuse to continue if the active database is unreadable.

Recommended recovery behavior:

- If integrity check fails, duplicate the broken file to a recovery folder.
- Show a clear error screen.
- Offer import from backup SQLite or reset/create new budget.

Why:

- If the local store is not resilient, wrapping it in iCloud will only spread corruption faster.

Test checkpoint:

- A corrupted copy of `budget.sqlite` is detected and fails safely instead of crashing the app.

---

## 18. Implement native SimpleFIN credentials handling

This is the second major foundation after local storage.

Do not store the SimpleFIN access URL in plain `UserDefaults`.

Create:

- `SimpleFINCredentialStore.swift`

Store secrets in Keychain.

What to store:

- Access URL returned from the claim step
- Optionally a display name for the connection in local DB

What not to store in plaintext:

- Full access URL in logs
- Setup token after claiming

Recommended security behavior:

- Immediately discard the setup token once the claim succeeds.
- Redact the username/password portion of the access URL in logs.
- Keep a stable local `connection_id` that references the Keychain item.

Decide whether credentials should sync across devices:

- Easiest v1: no cross-device credential sync, require re-linking on each device.
- Better UX later: support iCloud Keychain-synchronized credentials.

Recommended v1:

- Keep credentials device-local.

Why:

- It is simpler and safer.
- The local budget can later sync across devices even if the bank connection must be re-authorized per device.

Test checkpoint:

- You can save, load, and delete a SimpleFIN access credential from Keychain in a unit or integration test.

---

## 19. Build the native SimpleFIN linking flow

Create a new feature:

- `BankConnectionsView`

Primary user flow:

1. User taps `Link SimpleFIN`.
2. App explains the flow in plain language.
3. App opens `https://bridge.simplefin.org/simplefin/create` in Safari or an in-app browser.
4. User completes the SimpleFIN setup flow and copies the setup token.
5. User returns to the app and pastes the setup token.
6. App decodes the token from Base64 to a claim URL.
7. App `POST`s the claim URL once.
8. App receives the access URL.
9. App saves the access URL in Keychain.
10. App immediately calls `/accounts?version=2&balances-only=1`.
11. App shows discovered bank accounts and lets the user map them to local budget accounts.

Recommended UI:

- Section: linked institutions
- Section: discovered remote accounts awaiting mapping
- Button: sync now
- Last synced timestamp
- Error display for `errlist`

Why use `balances-only=1` first:

- It is cheaper and faster.
- The latest SimpleFIN protocol added it in v2.

Do not do this:

- Do not fetch all transactions before the user maps accounts.
- Do not repeatedly claim the same token.
- Do not bury `errlist` errors in debug logs only. The SimpleFIN docs explicitly say to show them to end users.

Test checkpoint:

- With a real or demo setup token, the app successfully claims an access URL and shows discovered remote accounts.

---

## 20. Implement `SimpleFINClient`

Create models for:

- account set
- connection
- account
- transaction
- structured errors

Use protocol version 2.

Client methods you need:

```swift
func claimAccessURL(from setupToken: String) async throws -> URL
func fetchAccountSet(accessURL: URL, balancesOnly: Bool, startDate: Date?, endDate: Date?, accountIDs: [String]?) async throws -> SimpleFINAccountSet
```

Implementation details:

1. Decode setup token using Base64.
2. Validate that the decoded string is a URL.
3. Send `POST` with empty body to the claim URL.
4. Save the returned access URL.
5. For reads, strip credentials from the URL before logging.
6. Use Basic Auth embedded in the access URL.
7. Call `/accounts?version=2`.
8. Support:
   - `balances-only=1`
   - `start-date`
   - `end-date`
   - repeated `account` filters

Normalize incoming data:

- Convert numeric strings like `"100.23"` into integer minor units for your app.
- Convert Unix timestamps into local `yyyy-MM-dd` strings before insert.
- Preserve remote `id` values for deduplication.

Test checkpoint:

- A test fixture or demo token can round-trip through `claimAccessURL` and `fetchAccountSet`.

---

## 21. Add account mapping tables and UI

You need an explicit mapping layer between SimpleFIN accounts and local budget accounts.

Create local table:

- `simplefin_account_links`

Suggested fields:

- `id`
- `connection_id`
- `simplefin_account_id`
- `simplefin_account_name`
- `simplefin_conn_id`
- `local_account_id`
- `created_at`
- `updated_at`
- `last_balance_amount`
- `last_balance_date`

User actions needed:

- Link to existing local account
- Create a new local account from the remote account
- Unlink account

Recommended mapping defaults:

- Match by normalized account name if there is exactly one obvious match
- Otherwise force manual confirmation

Never auto-link aggressively. Bad account mappings are worse than extra taps.

Test checkpoint:

- User can map each discovered SimpleFIN account to a local budget account and reopen the app later with mappings preserved.

---

## 22. Implement the SimpleFIN import coordinator

Create:

- `SimpleFINImportCoordinator.swift`

Responsibilities:

- schedule sync windows
- fetch account sets
- update balances
- insert new transactions
- skip duplicates
- record import status
- surface user-friendly errors

Recommended sync algorithm:

1. Load all linked SimpleFIN accounts.
2. Compute a sync start date per link:
   - first import: last 90 days
   - later imports: `max(lastSuccessfulSync - 3 days, 90 days ago)`
3. Fetch only the mapped account IDs from SimpleFIN when possible.
4. Update local account balances from `balance` and `balance-date`.
5. For each remote transaction:
   - derive stable `imported_id`, for example `simplefin:\(connectionID):\(accountID):\(transactionID)`
   - if that imported ID already exists, update mutable fields if needed
   - else insert a new local transaction
6. Mark pending transactions distinctly if SimpleFIN provides them
7. Save an import run record

Why overlap by 3 days:

- Some institutions revise recent transactions.
- The overlap lets you update recently changed transactions while still deduplicating by `imported_id`.

Add safeguards:

- one sync at a time
- cancellation support
- backoff after repeated auth errors

Test checkpoint:

- Running sync twice in a row does not duplicate transactions.

---

## 23. Decide how imported transactions should look in the UI

Do not leave this unspecified.

Recommended behavior:

- Imported SimpleFIN transactions appear in the same ledger as manual transactions.
- Keep `source = simplefin`.
- Leave category blank by default unless you later add auto-categorization.
- Allow the user to edit category, notes, and payee display name locally.
- Preserve the remote description in a raw imported field if you want.

Add fields if useful:

- `raw_import_description`
- `pending`
- `posted_at`
- `transacted_at`

Important:

- Imported transactions should still be editable without losing their external identity.

Test checkpoint:

- Imported transactions show in `TransactionsView`, `AllTransactionsView`, and `DashboardView` exactly like manual ones, apart from any explicit imported badge you choose to add.

---

## 24. Implement a standalone sync schedule

Without the Actual router, your app is responsible for deciding when bank sync happens.

Recommended schedule:

- Run a lightweight SimpleFIN sync when app becomes active if:
  - at least 12 hours passed since last success
  - there is at least one linked account
- Allow manual `Sync Now`
- Never background-poll aggressively

Why:

- Matches the documented SimpleFIN usage pattern better.
- Avoids rate-limit trouble.

Potential implementation hook:

- observe scene phase in `ActualAccountsApp.swift`

Pseudo-flow:

```swift
.onChange(of: scenePhase) { _, newValue in
    if newValue == .active {
        Task { await appState.maybeRunBackgroundSync() }
    }
}
```

Test checkpoint:

- Returning to foreground after enough time triggers one sync attempt and updates balances or transactions.

---

## 25. Add migration import from the old Actual-backed app

This is optional for “fresh standalone app” support, but strongly recommended if existing users matter.

Create:

- `ActualHTTPMigrationImporter.swift`

Goal:

- Let a user import their existing budget one final time from the old Actual HTTP backend into the local standalone store.

Do not keep this as a permanent architecture dependency.

Make it a one-time migration tool:

1. Present a temporary import screen in settings or onboarding.
2. Ask for old `Base URL`, `API Key`, `Sync ID`, optional encryption password`.
3. Use the existing `ActualAPIClient` to fetch:
   - accounts
   - categories
   - payees
   - transactions by account
   - budget month/category groups for enough recent months to seed read-only budget summaries
4. Insert them into the local store.
5. Mark all inserted transactions with `source = migration`.
6. Save a migration completion flag in the local budget metadata.
7. Remove the temporary credentials from memory as soon as import finishes.

This importer is the only place where keeping `ActualAPIClient` temporarily makes sense.

Test checkpoint:

- A real existing budget can be imported into a newly created local budget and opened without any server dependency afterward.

---

## 26. Add iCloud persistence only after local mode is done

This section is intentionally late in the guide.

Only start this once:

- local CRUD works
- local budget calculations work
- backup SQLite import works
- SimpleFIN import works
- demo mode is removed

Goal:

- Add a thin persistence wrapper so the local budget can be read on another Apple device.

Recommended design:

- Keep the live working database local in Application Support.
- Add an `ICloudBudgetSyncAdapter` that mirrors the active budget package to iCloud.
- On open, the adapter can pull the newest mirrored package down locally.
- On mutation, the adapter can schedule an upload or package refresh.

Recommended phase 2 package format:

- `My Budget.actualbundle`
- contains:
  - `budget.sqlite`
  - `metadata.json`

Files to add or update:

- `iOSApp/Data/Sync/ICloudBudgetSyncAdapter.swift`
- `iOSApp/project.yml`
- `iOSApp/Resources/ActualAccounts.entitlements`
- `iOSApp/SummaryWidget/SummaryWidgetExtension.entitlements`

Steps:

1. Replace the placeholder team ID in `iOSApp/project.yml` with a real Apple Developer team ID.
2. Turn on iCloud capability for the main app target.
3. Turn on iCloud capability for the widget target only if the widget later needs direct iCloud reads.
4. Add an iCloud container identifier such as `iCloud.com.actual.accounts`.
5. Add ubiquity entitlements.
6. Implement export of the local active budget into the iCloud package.
7. Implement import/refresh from the iCloud package back into the local active budget.
8. Add conflict detection and visible recovery UI.

Important:

- Treat iCloud as synchronized persistence, not as your live primary SQL file in v1.
- That separation is what keeps the rollout simple.

Test checkpoint:

- Edit data on device A, wait for sync, then open on device B and see the same budget after the adapter refreshes the local copy.

---

## 27. Remove the Actual HTTP layer after migration is proven

Only do this after the standalone path is working.

Delete or archive:

- `iOSApp/Networking/ActualAPIClient.swift`
- `iOSApp/Networking/APIEndpoints.swift`
- `swagger.json` if it is no longer relevant

Also remove all remaining mentions of:

- `x-api-key`
- `syncId`
- `budget-encryption-password`
- `/banksync`

Update:

- `README.md`

New README should describe:

- standalone local-first app
- optional iCloud budget sync wrapper
- direct SimpleFIN support
- optional import from old Actual-backed setups and backup SQLite files

Test checkpoint:

- `rg -n "baseURLString|apiKey|syncId|budgetEncryptionPassword|ActualAPIClient|APIEndpoints|x-api-key|banksync" iOSApp README.md` returns no production references other than migration code you intentionally keep.

---

## 28. Update logging and redaction rules

Current logging redacts the base URL. That no longer solves the right problem.

Files to update:

- `iOSApp/Shared/AppLogger.swift`
- `iOSApp/Shared/NetworkLogger.swift`

New redaction targets:

- SimpleFIN access URL credentials
- any pasted setup token
- any future iCloud file bookmarks or package identifiers

Recommended changes:

- Replace `redactionBaseURLString` with a list of secret patterns.
- Add specific redaction helpers for:
  - URLs containing embedded credentials
  - tokens
  - authorization headers

Test checkpoint:

- Failure logs do not leak SimpleFIN secrets.

---

## 29. Widget changes

Current widget data flow uses `SharedDataManager` and app groups. That can stay.

What changes:

- The widget should read summary values produced from the local repository, not from remote API results.
- If the selected budget changes, the app should rewrite shared summary values immediately.

You do not need the widget to open the SQLite file directly in v1.

Recommended v1:

- Keep the widget simple.
- Have the main app compute and publish:
  - spent today
  - currency code

Test checkpoint:

- Widget still updates after local transaction edits with no network dependency.

---

## 30. Testing plan by phase

Use this exact order.

Phase 1 tests:

- Project builds with new folders and protocols.
- No UI behavior changed yet.

Phase 2 tests:

- Local budget file path resolves.
- New local budget can be created and reopened.

Phase 3 tests:

- SQLite schema initializes.
- CRUD works for accounts, categories, payees, transactions.

Phase 4 tests:

- Repository-backed dashboard, accounts list, and transactions screens work locally.

Phase 5 tests:

- New onboarding creates and opens budgets.
- Settings no longer references server configuration.

Phase 6 tests:

- Budget calculations render correctly for seeded data.

Phase 7 tests:

- SimpleFIN setup token claim works.
- Account discovery and mapping work.

Phase 8 tests:

- Import is idempotent.
- Repeat sync does not duplicate rows.
- Auth and structured errors surface to users.

Phase 9 tests:

- Existing Actual-backed user can run one-time import and then disconnect from server entirely.

Phase 10 tests:

- Backup SQLite import works against the included `My-Finances-0275c5e/db.sqlite` sample or another real backup.

Phase 11 tests:

- iCloud wrapper syncs the local budget across devices without changing local CRUD behavior.

Phase 12 tests:

- App builds and runs after deleting the old HTTP client layer.

---

## 31. Suggested implementation order at the file level

If you are delegating this to a cheap coding agent, tell it to do these chunks one by one and stop after each chunk.

Chunk 1:

- Add empty local storage/repository/import files.
- Add `LocalBudgetFileManager`.

Chunk 2:

- Implement local budget bootstrap and file resolution.
- Replace onboarding with local budget creation/opening.

Chunk 3:

- Implement SQLite schema and repository read methods.
- Switch `DashboardView` and `AccountsView` to repository reads.

Chunk 4:

- Switch transaction screens and editor to local CRUD.

Chunk 5:

- Implement budget calculators.
- Switch `BudgetView`.

Chunk 6:

- Remove demo mode and sample data code paths.
- Implement backup SQLite import.

Chunk 7:

- Implement `BankConnectionsView`, `SimpleFINCredentialStore`, `SimpleFINClient`.

Chunk 8:

- Implement account mapping and import coordinator.

Chunk 9:

- Add one-time old-Actual import flow.

Chunk 10:

- Add iCloud entitlements and sync adapter.

Chunk 11:

- Remove obsolete networking code.
- Update docs and cleanup logs.

This order minimizes breakage and keeps every chunk testable.

---

## 32. Common mistakes to avoid

- Do not try to keep the current server onboarding and just hide it.
- Do not let views keep constructing storage clients directly.
- Do not store SimpleFIN secrets in `UserDefaults`.
- Do not import SimpleFIN transactions without stable dedupe keys.
- Do not add iCloud before local storage is stable.
- Do not fetch SimpleFIN too often.
- Do not auto-link bank accounts aggressively by fuzzy name matching.
- Do not delete the old HTTP layer before the local repository is proven.
- Do not assume the widget needs direct DB access in v1.

---

## 33. What “done” looks like

The migration is complete when all of the following are true:

- A new user can install the app, create a local budget, and use the app without any Actual server.
- Transactions, balances, dashboard metrics, and budget summaries all come from the local store.
- SimpleFIN accounts can be linked directly from the app without an Actual router.
- Running SimpleFIN sync updates balances and imports transactions without duplicates.
- The app can import an Actual backup SQLite file into the standalone format.
- Old users can optionally import their prior Actual-backed budget into the standalone format.
- The app can later sync that local budget to another Apple device through the iCloud wrapper.
- The repo no longer depends on Actual HTTP wrapper endpoints for normal operation.

---

## 34. Source notes that informed this plan

These sources are worth keeping in mind while implementing:

- Apple `UIDocument` docs: document-based apps should subclass `UIDocument`, and iCloud document handling relies on coordinated reads and writes.
- Apple iCloud design guide: iCloud document storage requires proper entitlements, coordinated file access, and conflict handling; file packages are recommended for multi-part documents.
- Actual API docs: the official supported API is the Node package `@actual-app/api`; the documented `init()` config defaults to local-only mode conceptually, but that does not give this Swift app a native storage engine for free.
- Actual SimpleFIN docs: SimpleFIN support in Actual requires recent versions and typically syncs up to 90 days with roughly daily updates.
- SimpleFIN protocol and Bridge developer docs: the flow is setup token -> claim URL -> access URL -> `GET /accounts?version=2`, with structured `errlist` errors and modest request-rate expectations.

If you want a concise summary of the whole migration in one sentence:

- Replace “server-backed Actual client screens” with “repository-backed local budget screens,” then plug direct SimpleFIN import into that local repository and add iCloud sync only after local mode is solid.

---

## 35. Import from an Actual Budget backup SQLite file

You asked for this explicitly, and because this repo already includes a real backup at `My-Finances-0275c5e/db.sqlite`, this should be part of the main implementation, not an afterthought.

Create:

- `iOSApp/Data/Migration/ActualBackupSQLiteImporter.swift`

Goal:

- Read an Actual backup SQLite file directly and transform it into this app’s local schema without using any HTTP API.

Why this is attractive:

- It avoids needing a live Actual server.
- It works offline.
- It uses a format you already have in the repo.

Important schema facts from the included backup:

- Main tables: `accounts`, `categories`, `category_groups`, `payees`, `transactions`, `zero_budgets`, `reflect_budgets`
- Useful views: `v_categories`, `v_payees`, `v_transactions`
- Actual stores dates in mixed formats depending on table and view:
  - `transactions.date` is integer-like in the raw table
  - `v_transactions.date` is normalized for consumer use

Recommended import source:

- Prefer reading from the `v_*` views where possible:
  - `v_categories`
  - `v_payees`
  - `v_transactions`

Why:

- The views already resolve tombstones and some mappings.
- Importing from raw tables like `transactions`, `category_mapping`, and `payee_mapping` forces you to re-implement more of Actual’s internal normalization.

Recommended import order:

1. Open the backup database read-only.
2. Read category groups from `category_groups` where `tombstone = 0`.
3. Read categories from `v_categories`.
4. Read accounts from `accounts` where `tombstone = 0`.
5. Read payees from `v_payees`.
6. Read transactions from `v_transactions`.
7. Read budget allocations from `zero_budgets`.
8. Store a source marker such as `source = backup-import`.

Suggested field mappings:

- Actual `accounts.id` -> local `accounts.id`
- Actual `accounts.name` -> local `accounts.name`
- Actual `accounts.offbudget` -> local `accounts.offbudget`
- Actual `accounts.closed` -> local `accounts.closed`
- Actual `accounts.balance_current` -> local `accounts.balance_current`
- Actual `v_categories.id` -> local `categories.id`
- Actual `v_categories.group` -> local `categories.group_id`
- Actual `v_payees.transfer_acct` -> local `payees.transfer_account_id`
- Actual `v_transactions.account` -> local `transactions.account_id`
- Actual `v_transactions.category` -> local `transactions.category_id`
- Actual `v_transactions.payee` -> local `transactions.payee_id`
- Actual `v_transactions.imported_id` -> local `transactions.imported_id`
- Actual `v_transactions.transfer_id` -> local `transactions.transfer_id`
- Actual `v_transactions.imported_payee` -> local raw import description or payee fallback field

Handling dates:

- Normalize every imported transaction date to `yyyy-MM-dd` before insert.
- If you read from `v_transactions`, verify the exact stored format first.
- If a raw integer date appears in `YYYYMMDD` form, convert it before storing.

Handling transfers:

- Preserve `transfer_id`.
- Preserve transfer payees through `transfer_acct` mappings.
- Do not count transfers as spending in your calculators.

Handling budget allocations:

- `zero_budgets` appears to hold month/category budget assignments.
- Import:
  - `month`
  - `category`
  - `amount`
  - `carryover`
- Convert those rows into your local `budget_category_values` table.

Suggested UI flow:

1. User taps `Import Actual Backup`.
2. User picks a `.sqlite` file with `UIDocumentPickerViewController`.
3. App copies it into a temporary sandbox file.
4. Importer opens it read-only.
5. Importer validates required tables/views exist.
6. Importer shows a preview:
   - account count
   - transaction count
   - date range
7. User confirms import.
8. Import runs inside one local transaction.
9. App shows success summary and opens the imported budget.

Validation checks before import:

- `accounts` table exists
- `v_transactions` view exists
- `v_categories` view exists
- `v_payees` view exists
- database opens read-only without integrity errors

Recommended implementation detail:

- Build a small mapper struct for each source row type instead of writing one giant import method.

For example:

```swift
struct ActualBackupAccountRow { ... }
struct ActualBackupCategoryRow { ... }
struct ActualBackupPayeeRow { ... }
struct ActualBackupTransactionRow { ... }
```

Test checkpoint:

- The importer can successfully read `My-Finances-0275c5e/db.sqlite`, display a preview, and import it into the app’s local store without a server.

---

## 36. Cleanup

You asked to remove the existing sample data and demo toggle. Do this after local storage is working and before declaring the standalone migration done.

Files to remove or rewrite:

- `iOSApp/Networking/DemoDataService.swift`
- `iOSApp/Features/Onboarding/OnboardingView.swift`
- `iOSApp/Features/Settings/SettingsView.swift`
- `iOSApp/Shared/AppState.swift`
- every `isDemoMode` branch in repository/client code

Concrete cleanup steps:

1. Remove `isDemoMode` from `AppState`.
2. Remove the `Use Demo Mode` action from onboarding.
3. Remove the `Enable Demo Mode` toggle from settings.
4. Delete all `if isDemoMode { ... }` branches from `ActualAPIClient` during the migration away from that client.
5. Remove any repository or storage paths that create fake transactions, fake accounts, or fake categories.
6. Replace demo-first empty states with real empty states:
   - “No accounts yet”
   - “No transactions yet”
   - “Create your first account”
7. Update README text that currently recommends demo mode.
8. Delete `DemoDataService.swift` once nothing references it.

Why this matters:

- Demo mode hides real bugs in the local data layer.
- A standalone app should have one real path, not one real path plus one fake path.

Verification command:

- `rg -n "DemoDataService|isDemoMode|Use Demo Mode|Enable Demo Mode" iOSApp README.md`

Expected result:

- No production references remain.

Final cleanup pass after everything else:

1. Remove unused imports left over from networking-only code.
2. Remove `swagger.json` if you no longer need the old HTTP wrapper contract.
3. Remove obsolete README sections about configuring a remote Actual server.
4. Search for stale wording like:
   - `Actual server`
   - `Base URL`
   - `API Key`
   - `Sync ID`
5. Verify the app still builds after deleting dead code.

Test checkpoint:

- There is no demo toggle, no sample-data path, and no dead demo code left in the repo.
