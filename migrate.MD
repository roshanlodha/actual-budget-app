# Standalone Migration Implementation Playbook: Agent Prompts

This document contains a series of highly detailed, step-by-step prompts to guide an AI coding agent through the migration of this app from a remote Actual Budget HTTP client to a native, local-first standalone iOS app.

Each prompt is self-contained and ensures that the app compiles and runs successfully at the end of each phase.

---

## Prompt 1: Database Setup and Local File Management (Phase 1)

### Objective
Create a low-level, type-safe SQLite database wrapper using the built-in system SQLite library (`import SQLite3`), and a file manager to handle localized file storage within the application support directory.

### Files to Create / Modify
- **[MODIFY]** [project.yml](file:///Users/roshanlodha/Documents/actual-budget-app/iOSApp/project.yml)
- **[NEW]** [SQLiteDB.swift](file:///Users/roshanlodha/Documents/actual-budget-app/iOSApp/Data/Persistence/SQLiteDB.swift)
- **[NEW]** [LocalBudgetFileManager.swift](file:///Users/roshanlodha/Documents/actual-budget-app/iOSApp/Data/Persistence/LocalBudgetFileManager.swift)
- **[NEW]** [BudgetSeeder.swift](file:///Users/roshanlodha/Documents/actual-budget-app/iOSApp/Data/Persistence/BudgetSeeder.swift)

### Step-by-Step Instructions

1. **Modify `project.yml`**:
   Add the new `Data` directory to the target source folders under `ActualAccounts` so XcodeGen compiles them:
   ```yaml
       sources:
         - path: App
         - path: Features
         - path: Networking
         - path: UI
         - path: Resources
           excludes: [README.md]
         - path: Shared
         - path: Data
   ```
   *Run `make project` in the project root directory (terminal) to regenerate the Xcode project.*

2. **Create `SQLiteDB.swift`**:
   Create the directory `iOSApp/Data/Persistence` and write the native SQLite wrapper exactly:
   ```swift
   import Foundation
   import SQLite3

   public final class SQLiteDB {
       private var db: OpaquePointer?
       
       public init(path: String) throws {
           if sqlite3_open(path, &db) != SQLITE_OK {
               let msg = db != nil ? String(cString: sqlite3_errmsg(db)) : "Unknown error"
               throw DatabaseError.openFailed(msg)
           }
           try execute("PRAGMA journal_mode=WAL;")
           try execute("PRAGMA foreign_keys=ON;")
       }
       
       deinit {
           if let db = db {
               sqlite3_close(db)
           }
       }
       
       public func execute(_ sql: String, arguments: [Any] = []) throws {
           var stmt: OpaquePointer?
           if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) != SQLITE_OK {
               throw DatabaseError.prepareFailed(errorMessage())
           }
           defer { sqlite3_finalize(stmt) }
           
           try bind(stmt!, arguments: arguments)
           
           if sqlite3_step(stmt) != SQLITE_DONE {
               throw DatabaseError.executionFailed(errorMessage())
           }
       }
       
       public func query(_ sql: String, arguments: [Any] = []) throws -> [[String: Any]] {
           var stmt: OpaquePointer?
           if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) != SQLITE_OK {
               throw DatabaseError.prepareFailed(errorMessage())
           }
           defer { sqlite3_finalize(stmt) }
           
           try bind(stmt!, arguments: arguments)
           
           var rows = [[String: Any]]()
           let colCount = sqlite3_column_count(stmt)
           
           while sqlite3_step(stmt) == SQLITE_ROW {
               var row = [String: Any]()
               for i in 0..<colCount {
                   let colName = String(cString: sqlite3_column_name(stmt, i))
                   let colType = sqlite3_column_type(stmt, i)
                   switch colType {
                   case SQLITE_INTEGER:
                       row[colName] = Int(sqlite3_column_int64(stmt, i))
                   case SQLITE_FLOAT:
                       row[colName] = sqlite3_column_double(stmt, i)
                   case SQLITE_TEXT:
                       if let ptr = sqlite3_column_text(stmt, i) {
                           row[colName] = String(cString: ptr)
                       } else {
                           row[colName] = ""
                       }
                   case SQLITE_NULL:
                       row[colName] = NSNull()
                   default:
                       row[colName] = NSNull()
                   }
               }
               rows.append(row)
           }
           return rows
       }
       
       public func transaction<T>(_ block: () throws -> T) throws -> T {
           try execute("BEGIN TRANSACTION;")
           do {
               let result = try block()
               try execute("COMMIT;")
               return result
           } catch {
               try? execute("ROLLBACK;")
               throw error
           }
       }
       
       private func bind(_ stmt: OpaquePointer, arguments: [Any]) throws {
           for (index, val) in arguments.enumerated() {
               let idx = Int32(index + 1)
               let status: Int32
               if let str = val as? String {
                   status = sqlite3_bind_text(stmt, idx, str, -1, nil)
               } else if let intVal = val as? Int {
                   status = sqlite3_bind_int64(stmt, idx, Int64(intVal))
               } else if let doubleVal = val as? Double {
                   status = sqlite3_bind_double(stmt, idx, doubleVal)
               } else if let boolVal = val as? Bool {
                   status = sqlite3_bind_int64(stmt, idx, boolVal ? 1 : 0)
               } else if val is NSNull {
                   status = sqlite3_bind_null(stmt, idx)
               } else {
                   status = sqlite3_bind_null(stmt, idx)
               }
               if status != SQLITE_OK {
                   throw DatabaseError.bindFailed(errorMessage())
               }
           }
       }
       
       private func errorMessage() -> String {
           return db != nil ? String(cString: sqlite3_errmsg(db)) : "Unknown database error"
       }
       
       public enum DatabaseError: Error, LocalizedError {
           case openFailed(String)
           case prepareFailed(String)
           case executionFailed(String)
           case bindFailed(String)
           
           public var errorDescription: String? {
               switch self {
               case .openFailed(let msg): return "Database open failed: \(msg)"
               case .prepareFailed(let msg): return "Database prepare query failed: \(msg)"
               case .executionFailed(let msg): return "Database execute failed: \(msg)"
               case .bindFailed(let msg): return "Database bind parameter failed: \(msg)"
               }
           }
       }
   }
   ```

3. **Create `LocalBudgetFileManager.swift`**:
   Write the storage coordinating manager exactly:
   ```swift
   import Foundation

   public final class LocalBudgetFileManager {
       public static let shared = LocalBudgetFileManager()
       
       private init() {}
       
       public var budgetsDirectory: URL {
           let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
           let appSupport = paths[0]
           let budgetsDir = appSupport.appendingPathComponent("Budgets", isDirectory: true)
           if !FileManager.default.fileExists(atPath: budgetsDir.path) {
               try? FileManager.default.createDirectory(at: budgetsDir, withIntermediateDirectories: true)
           }
           return budgetsDir
       }
       
       public func budgetDirectory(for budgetId: String) -> URL {
           return budgetsDirectory.appendingPathComponent(budgetId, isDirectory: true)
       }
       
       public func sqliteFileURL(for budgetId: String) -> URL {
           return budgetDirectory(for: budgetId).appendingPathComponent("budget.sqlite")
       }
       
       public func metadataFileURL(for budgetId: String) -> URL {
           return budgetDirectory(for: budgetId).appendingPathComponent("budget-metadata.json")
       }
       
       public func createBudgetDirectory(for budgetId: String) throws {
           let dir = budgetDirectory(for: budgetId)
           if !FileManager.default.fileExists(atPath: dir.path) {
               try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
           }
       }
       
       public func listBudgets() -> [(id: String, displayName: String)] {
           let dir = budgetsDirectory
           guard let urls = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles) else {
               return []
           }
           var list = [(id: String, displayName: String)]()
           for url in urls where url.hasDirectoryPath {
               let id = url.lastPathComponent
               let metaURL = metadataFileURL(for: id)
               var displayName = id
               if let data = try? Data(contentsOf: metaURL),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let name = json["displayName"] as? String {
                   displayName = name
               }
               list.append((id: id, displayName: displayName))
           }
           return list
       }
       
       public func deleteBudget(budgetId: String) throws {
           let dir = budgetDirectory(for: budgetId)
           if FileManager.default.fileExists(atPath: dir.path) {
               try FileManager.default.removeItem(at: dir)
           }
       }
   }
   ```

4. **Create `BudgetSeeder.swift`**:
   Write standard envelope seeds for fresh databases inside a transaction:
   ```swift
   import Foundation

   public struct BudgetSeeder {
       public static func seedStarterData(db: SQLiteDB) throws {
           let categoriesToSeed: [(groupName: String, isIncome: Bool, subCategories: [String])] = [
               ("Income", true, ["Salary", "Other Income"]),
               ("Fixed Expenses", false, ["Rent/Mortgage", "Utilities", "Internet/Phone", "Insurance"]),
               ("Flexible Spending", false, ["Groceries", "Dining Out", "Entertainment", "Shopping", "Travel"]),
               ("Savings & Investments", false, ["Emergency Fund", "Retirement"])
           ]
           
           try db.transaction {
               for group in categoriesToSeed {
                   let groupId = UUID().uuidString
                   try db.execute("INSERT INTO budget_category_groups (id, name, is_income, hidden) VALUES (?, ?, ?, 0);",
                                  arguments: [groupId, group.groupName, group.isIncome])
                   
                   for subCat in group.subCategories {
                       let subId = UUID().uuidString
                       try db.execute("INSERT INTO categories (id, name, is_income, hidden, group_id) VALUES (?, ?, ?, 0, ?);",
                                      arguments: [subId, subCat, group.isIncome, groupId])
                   }
               }
           }
       }
   }
   ```

### Verification Plan
- Build the app in Xcode (Cmd+B) or run `make build` / `xcodebuild` in terminal. Verify that compiling completes successfully.

---

## Prompt 2: Database Schema & Repository Layer (Phase 2)

### Objective
Define the protocol abstraction `BudgetRepository` and its concrete SQLite implementation `LocalBudgetRepository`, containing schema migrations, transaction double-entry book-keeping transfers, and calculations.

### Files to Create / Modify
- **[NEW]** [BudgetRepository.swift](file:///Users/roshanlodha/Documents/actual-budget-app/iOSApp/Data/Repository/BudgetRepository.swift)
- **[NEW]** [LocalBudgetRepository.swift](file:///Users/roshanlodha/Documents/actual-budget-app/iOSApp/Data/Repository/LocalBudgetRepository.swift)

### Step-by-Step Instructions

1. **Create `BudgetRepository.swift`**:
   Create the directory `iOSApp/Data/Repository` and write the protocol exactly:
   ```swift
   import Foundation

   public protocol BudgetRepository {
       func fetchAccounts() async throws -> [Account]
       func createAccount(name: String, offbudget: Bool) async throws -> String
       func updateAccount(_ account: Account) async throws
       func deleteAccount(id: String) async throws
       
       func fetchCategories() async throws -> [Category]
       func fetchCategoriesByGroupId(_ groupId: String) async throws -> [Category]
       func createCategory(name: String, isIncome: Bool, groupId: String) async throws -> String
       
       func fetchPayees() async throws -> [Payee]
       func createPayee(name: String, categoryId: String?, transferAccountId: String?) async throws -> String
       
       func fetchTransactions(accountId: String, since: String?) async throws -> [Transaction]
       func fetchAllTransactions(since: String?) async throws -> [Transaction]
       func createTransaction(_ transaction: Transaction) async throws
       func updateTransaction(_ transaction: Transaction) async throws
       func deleteTransaction(id: String) async throws
       
       func fetchAccountBalance(accountId: String) async throws -> Int
       
       func fetchBudgetMonthCategoryGroups(_ month: String) async throws -> [BudgetMonthCategoryGroup]
       func fetchBudgetMonth(_ month: String) async throws -> BudgetMonth
       func updateBudgetAmount(month: String, categoryId: String, budgeted: Int) async throws
       
       func fetchAccountLinks() async throws -> [String: String]
       func saveAccountLink(simplefinId: String, name: String, localId: String) async throws
       func deleteAccountLink(simplefinId: String) async throws
   }
   ```

2. **Create `LocalBudgetRepository.swift`**:
   Write the concrete database engine exactly:
   ```swift
   import Foundation

   public final class LocalBudgetRepository: BudgetRepository {
       private let db: SQLiteDB
       
       public init(db: SQLiteDB) {
           self.db = db
           try? setupSchema()
       }
       
       private func setupSchema() throws {
           try db.execute("""
           CREATE TABLE IF NOT EXISTS accounts (
               id TEXT PRIMARY KEY,
               name TEXT NOT NULL,
               offbudget INTEGER NOT NULL DEFAULT 0,
               closed INTEGER NOT NULL DEFAULT 0
           );
           """)
           
           try db.execute("""
           CREATE TABLE IF NOT EXISTS categories (
               id TEXT PRIMARY KEY,
               name TEXT NOT NULL,
               is_income INTEGER NOT NULL DEFAULT 0,
               hidden INTEGER NOT NULL DEFAULT 0,
               group_id TEXT
           );
           """)
           
           try db.execute("""
           CREATE TABLE IF NOT EXISTS payees (
               id TEXT PRIMARY KEY,
               name TEXT NOT NULL,
               category_id TEXT,
               transfer_account_id TEXT
           );
           """)
           
           try db.execute("""
           CREATE TABLE IF NOT EXISTS transactions (
               id TEXT PRIMARY KEY,
               account_id TEXT NOT NULL,
               date TEXT NOT NULL,
               amount INTEGER NOT NULL DEFAULT 0,
               payee_id TEXT,
               payee_name TEXT,
               category_id TEXT,
               notes TEXT,
               imported_id TEXT,
               transfer_id TEXT,
               cleared INTEGER NOT NULL DEFAULT 0,
               source TEXT NOT NULL DEFAULT 'manual'
           );
           """)
           
           try db.execute("""
           CREATE TABLE IF NOT EXISTS budget_category_groups (
               id TEXT PRIMARY KEY,
               name TEXT NOT NULL,
               is_income INTEGER NOT NULL DEFAULT 0,
               hidden INTEGER NOT NULL DEFAULT 0
           );
           """)
           
           try db.execute("""
           CREATE TABLE IF NOT EXISTS budget_category_values (
               month TEXT NOT NULL,
               category_id TEXT NOT NULL,
               budgeted INTEGER NOT NULL DEFAULT 0,
               carryover INTEGER NOT NULL DEFAULT 1,
               PRIMARY KEY (month, category_id)
           );
           """)
           
           try db.execute("""
           CREATE TABLE IF NOT EXISTS simplefin_account_links (
               simplefin_account_id TEXT PRIMARY KEY,
               simplefin_account_name TEXT NOT NULL,
               local_account_id TEXT NOT NULL,
               last_balance_amount INTEGER,
               last_balance_date TEXT
           );
           """)
           
           let rowCount = try db.query("SELECT COUNT(*) as count FROM categories;")
           let count = rowCount.first?["count"] as? Int ?? 0
           if count == 0 {
               try BudgetSeeder.seedStarterData(db: db)
           }
       }
       
       // MARK: - Accounts
       public func fetchAccounts() async throws -> [Account] {
           let rows = try db.query("SELECT id, name, offbudget, closed FROM accounts;")
           return rows.map { row in
               Account(
                   id: row["id"] as? String ?? "",
                   name: row["name"] as? String ?? "",
                   offbudget: (row["offbudget"] as? Int ?? 0) != 0,
                   closed: (row["closed"] as? Int ?? 0) != 0
               )
           }
       }
       
       public func createAccount(name: String, offbudget: Bool) async throws -> String {
           let id = UUID().uuidString
           try db.execute("INSERT INTO accounts (id, name, offbudget, closed) VALUES (?, ?, ?, 0);", arguments: [id, name, offbudget])
           
           let payeeId = UUID().uuidString
           try db.execute("INSERT INTO payees (id, name, category_id, transfer_account_id) VALUES (?, ?, NULL, ?);",
                          arguments: [payeeId, "Transfer: \(name)", id])
           return id
       }
       
       public func updateAccount(_ account: Account) async throws {
           try db.execute("UPDATE accounts SET name = ?, offbudget = ?, closed = ? WHERE id = ?;",
                          arguments: [account.name, account.offbudget, account.closed, account.id])
       }
       
       public func deleteAccount(id: String) async throws {
           try db.transaction {
               try db.execute("DELETE FROM transactions WHERE account_id = ?;", arguments: [id])
               try db.execute("DELETE FROM payees WHERE transfer_account_id = ?;", arguments: [id])
               try db.execute("DELETE FROM accounts WHERE id = ?;", arguments: [id])
           }
       }
       
       // MARK: - Categories
       public func fetchCategories() async throws -> [Category] {
           let rows = try db.query("SELECT id, name, is_income, hidden, group_id FROM categories;")
           return rows.map { row in
               Category(
                   id: row["id"] as? String ?? "",
                   name: row["name"] as? String ?? "",
                   is_income: (row["is_income"] as? Int ?? 0) != 0,
                   hidden: (row["hidden"] as? Int ?? 0) != 0,
                   group_id: row["group_id"] as? String
               )
           }
       }
       
       public func fetchCategoriesByGroupId(_ groupId: String) async throws -> [Category] {
           let rows = try db.query("SELECT id, name, is_income, hidden, group_id FROM categories WHERE group_id = ?;", arguments: [groupId])
           return rows.map { row in
               Category(
                   id: row["id"] as? String ?? "",
                   name: row["name"] as? String ?? "",
                   is_income: (row["is_income"] as? Int ?? 0) != 0,
                   hidden: (row["hidden"] as? Int ?? 0) != 0,
                   group_id: row["group_id"] as? String
               )
           }
       }
       
       public func createCategory(name: String, isIncome: Bool, groupId: String) async throws -> String {
           let id = UUID().uuidString
           try db.execute("INSERT INTO categories (id, name, is_income, hidden, group_id) VALUES (?, ?, ?, 0, ?);",
                          arguments: [id, name, isIncome, groupId])
           return id
       }
       
       // MARK: - Payees
       public func fetchPayees() async throws -> [Payee] {
           let rows = try db.query("SELECT id, name, category_id, transfer_account_id FROM payees;")
           return rows.map { row in
               Payee(
                   id: row["id"] as? String ?? "",
                   name: row["name"] as? String ?? "",
                   category: row["category_id"] as? String,
                   transfer_acct: row["transfer_account_id"] as? String
               )
           }
       }
       
       public func createPayee(name: String, categoryId: String?, transferAccountId: String?) async throws -> String {
           let id = UUID().uuidString
           try db.execute("INSERT INTO payees (id, name, category_id, transfer_account_id) VALUES (?, ?, ?, ?);",
                          arguments: [id, name, categoryId ?? NSNull(), transferAccountId ?? NSNull()])
           return id
       }
       
       // MARK: - Transactions
       public func fetchTransactions(accountId: String, since: String? = nil) async throws -> [Transaction] {
           var sql = "SELECT id, account_id, date, amount, payee_id, payee_name, category_id, notes, imported_id, transfer_id, cleared FROM transactions WHERE account_id = ?"
           var args: [Any] = [accountId]
           if let since = since {
               sql += " AND date >= ?"
               args.append(since)
           }
           sql += " ORDER BY date DESC;"
           
           let rows = try db.query(sql, arguments: args)
           return mapTransactionRows(rows)
       }
       
       public func fetchAllTransactions(since: String? = nil) async throws -> [Transaction] {
           var sql = "SELECT id, account_id, date, amount, payee_id, payee_name, category_id, notes, imported_id, transfer_id, cleared FROM transactions"
           var args: [Any] = []
           if let since = since {
               sql += " WHERE date >= ?"
               args.append(since)
           }
           sql += " ORDER BY date DESC;"
           
           let rows = try db.query(sql, arguments: args)
           return mapTransactionRows(rows)
       }
       
       private func mapTransactionRows(_ rows: [[String: Any]]) -> [Transaction] {
           return rows.map { row in
               Transaction(
                   id: row["id"] as? String,
                   account: row["account_id"] as? String ?? "",
                   date: row["date"] as? String ?? "",
                   amount: row["amount"] as? Int,
                   payee: row["payee_id"] as? String,
                   payee_name: row["payee_name"] as? String,
                   imported_payee: nil,
                   category: row["category_id"] as? String,
                   notes: row["notes"] as? String,
                   imported_id: row["imported_id"] as? String,
                   transfer_id: row["transfer_id"] as? String,
                   cleared: (row["cleared"] as? Int ?? 0) != 0,
                   subtransactions: nil
               )
           }
       }
       
       public func createTransaction(_ transaction: Transaction) async throws {
           try db.transaction {
               let txId = transaction.id ?? UUID().uuidString
               
               var transferId = transaction.transfer_id
               var targetAccountId: String? = nil
               
               if let payeeId = transaction.payee {
                   let payeeRows = try db.query("SELECT transfer_account_id FROM payees WHERE id = ?;", arguments: [payeeId])
                   if let pRow = payeeRows.first, let destAcct = pRow["transfer_account_id"] as? String {
                       targetAccountId = destAcct
                   }
               }
               
               if let destAccount = targetAccountId {
                   if transferId == nil {
                       transferId = UUID().uuidString
                   }
                   
                   let sourcePayeeRows = try db.query("SELECT id FROM payees WHERE transfer_account_id = ?;", arguments: [transaction.account])
                   let sourcePayeeId = sourcePayeeRows.first?["id"] as? String
                   
                   let pairedTxId = UUID().uuidString
                   try db.execute("""
                       INSERT INTO transactions (id, account_id, date, amount, payee_id, payee_name, category_id, notes, imported_id, transfer_id, cleared, source)
                       VALUES (?, ?, ?, ?, ?, NULL, NULL, ?, NULL, ?, ?, 'manual');
                   """, arguments: [
                       pairedTxId,
                       destAccount,
                       transaction.date,
                       -(transaction.amount ?? 0),
                       sourcePayeeId ?? NSNull(),
                       transaction.notes ?? NSNull(),
                       transferId!,
                       transaction.cleared ?? false
                   ])
               }
               
               try db.execute("""
                   INSERT INTO transactions (id, account_id, date, amount, payee_id, payee_name, category_id, notes, imported_id, transfer_id, cleared, source)
                   VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'manual');
               """, arguments: [
                   txId,
                   transaction.account,
                   transaction.date,
                   transaction.amount ?? 0,
                   transaction.payee ?? NSNull(),
                   transaction.payee_name ?? NSNull(),
                   transaction.category ?? NSNull(),
                   transaction.notes ?? NSNull(),
                   transaction.imported_id ?? NSNull(),
                   transferId ?? NSNull(),
                   transaction.cleared ?? false
               ])
           }
       }
       
       public func updateTransaction(_ transaction: Transaction) async throws {
           guard let txId = transaction.id else { return }
           try db.transaction {
               try db.execute("""
                   UPDATE transactions 
                   SET account_id = ?, date = ?, amount = ?, payee_id = ?, payee_name = ?, category_id = ?, notes = ?, cleared = ?
                   WHERE id = ?;
               """, arguments: [
                   transaction.account,
                   transaction.date,
                   transaction.amount ?? 0,
                   transaction.payee ?? NSNull(),
                   transaction.payee_name ?? NSNull(),
                   transaction.category ?? NSNull(),
                   transaction.notes ?? NSNull(),
                   transaction.cleared ?? false,
                   txId
               ])
               
               if let transferId = transaction.transfer_id {
                   try db.execute("""
                       UPDATE transactions 
                       SET date = ?, amount = ?, notes = ?
                       WHERE transfer_id = ? AND id != ?;
                   """, arguments: [
                       transaction.date,
                       -(transaction.amount ?? 0),
                       transaction.notes ?? NSNull(),
                       transferId,
                       txId
                   ])
               }
           }
       }
       
       public func deleteTransaction(id: String) async throws {
           try db.transaction {
               let rows = try db.query("SELECT transfer_id FROM transactions WHERE id = ?;", arguments: [id])
               if let row = rows.first, let transferId = row["transfer_id"] as? String {
                   try db.execute("DELETE FROM transactions WHERE transfer_id = ?;", arguments: [transferId])
               } else {
                   try db.execute("DELETE FROM transactions WHERE id = ?;", arguments: [id])
               }
           }
       }
       
       public func fetchAccountBalance(accountId: String) async throws -> Int {
           let rows = try db.query("SELECT SUM(amount) as balance FROM transactions WHERE account_id = ?;", arguments: [accountId])
           return rows.first?["balance"] as? Int ?? 0
       }
       
       // MARK: - Calculations Engine
       public func fetchBudgetMonthCategoryGroups(_ month: String) async throws -> [BudgetMonthCategoryGroup] {
           let groupRows = try db.query("SELECT id, name, is_income, hidden FROM budget_category_groups WHERE hidden = 0;")
           let catRows = try db.query("SELECT id, name, is_income, hidden, group_id FROM categories WHERE hidden = 0;")
           
           let budgetRows = try db.query("SELECT category_id, budgeted, carryover FROM budget_category_values WHERE month = ?;", arguments: [month])
           let budgetsByCat = Dictionary(uniqueKeysWithValues: budgetRows.map { 
               ($0["category_id"] as? String ?? "", ($0["budgeted"] as? Int ?? 0, $0["carryover"] as? Int ?? 1)) 
           })
           
           let spentRows = try db.query("""
               SELECT category_id, SUM(amount) as spent 
               FROM transactions t
               JOIN accounts a ON t.account_id = a.id
               WHERE strftime('%Y-%m', date) = ? AND t.transfer_id IS NULL AND a.offbudget = 0
               GROUP BY category_id;
           """, arguments: [month])
           let spentByCat = Dictionary(uniqueKeysWithValues: spentRows.map { ($0["category_id"] as? String ?? "", $0["spent"] as? Int ?? 0) })
           
           let cumulativeSpentRows = try db.query("""
               SELECT category_id, SUM(amount) as spent 
               FROM transactions t
               JOIN accounts a ON t.account_id = a.id
               WHERE strftime('%Y-%m', date) <= ? AND t.transfer_id IS NULL AND a.offbudget = 0
               GROUP BY category_id;
           """, arguments: [month])
           let cumulativeSpentByCat = Dictionary(uniqueKeysWithValues: cumulativeSpentRows.map { ($0["category_id"] as? String ?? "", $0["spent"] as? Int ?? 0) })
           
           let cumulativeBudgetedRows = try db.query("""
               SELECT category_id, SUM(budgeted) as budgeted 
               FROM budget_category_values 
               WHERE month <= ?
               GROUP BY category_id;
           """, arguments: [month])
           let cumulativeBudgetedByCat = Dictionary(uniqueKeysWithValues: cumulativeBudgetedRows.map { ($0["category_id"] as? String ?? "", $0["budgeted"] as? Int ?? 0) })
           
           var groups = [BudgetMonthCategoryGroup]()
           
           for gRow in groupRows {
               let gId = gRow["id"] as? String ?? ""
               let gName = gRow["name"] as? String ?? ""
               let gIsIncome = (gRow["is_income"] as? Int ?? 0) != 0
               let gHidden = (gRow["hidden"] as? Int ?? 0) != 0
               
               let catsInGroup = catRows.filter { ($0["group_id"] as? String) == gId }.map { cRow -> BudgetMonthCategory in
                   let cId = cRow["id"] as? String ?? ""
                   let cName = cRow["name"] as? String ?? ""
                   let cIsIncome = (cRow["is_income"] as? Int ?? 0) != 0
                   let cHidden = (cRow["hidden"] as? Int ?? 0) != 0
                   
                   let budgeted = budgetsByCat[cId]?.0 ?? 0
                   let spent = spentByCat[cId] ?? 0
                   
                   let cumBudgeted = cumulativeBudgetedByCat[cId] ?? 0
                   let cumSpent = cumulativeSpentByCat[cId] ?? 0
                   let balance = cumBudgeted + cumSpent
                   
                   return BudgetMonthCategory(
                       id: cId,
                       name: cName,
                       is_income: cIsIncome,
                       hidden: cHidden,
                       group_id: gId,
                       budgeted: budgeted,
                       spent: spent,
                       balance: balance,
                       carryover: (budgetsByCat[cId]?.1 ?? 1) != 0
                   )
               }
               
               let totalBudgeted = catsInGroup.map { $0.budgeted ?? 0 }.reduce(0, +)
               let totalSpent = catsInGroup.map { $0.spent ?? 0 }.reduce(0, +)
               let totalBalance = catsInGroup.map { $0.balance ?? 0 }.reduce(0, +)
               
               groups.append(BudgetMonthCategoryGroup(
                   id: gId,
                   name: gName,
                   is_income: gIsIncome,
                   hidden: gHidden,
                   categories: catsInGroup,
                   budgeted: totalBudgeted,
                   spent: totalSpent,
                   balance: totalBalance
               ))
           }
           return groups
       }
       
       public func fetchBudgetMonth(_ month: String) async throws -> BudgetMonth {
           let f = DateFormatter(); f.dateFormat = "yyyy-MM"
           guard let currentDate = f.date(from: month) else {
               throw NSError(domain: "LocalBudgetRepository", code: 10, userInfo: [NSLocalizedDescriptionKey: "Invalid month key format"])
           }
           let cal = Calendar.current
           let prevDate = cal.date(byAdding: .month, value: -1, to: currentDate) ?? currentDate
           let prevMonthKey = f.string(from: prevDate)
           
           let incomeCatsRows = try db.query("SELECT id FROM categories WHERE is_income = 1;")
           let incomeCatIds = Set(incomeCatsRows.map { $0["id"] as? String ?? "" })
           
           let monthSpentRows = try db.query("""
               SELECT category_id, SUM(amount) as total 
               FROM transactions t
               JOIN accounts a ON t.account_id = a.id
               WHERE strftime('%Y-%m', date) = ? AND t.transfer_id IS NULL AND a.offbudget = 0
               GROUP BY category_id;
           """, arguments: [month])
           
           var totalIncome = 0
           var totalSpent = 0
           for r in monthSpentRows {
               let catId = r["category_id"] as? String ?? ""
               let amt = r["total"] as? Int ?? 0
               if incomeCatIds.contains(catId) {
                   totalIncome += amt
               } else {
                   totalSpent += amt
               }
           }
           
           let monthBudgetedRows = try db.query("""
               SELECT category_id, budgeted 
               FROM budget_category_values 
               WHERE month = ?;
           """, arguments: [month])
           var totalBudgeted = 0
           for r in monthBudgetedRows {
               let catId = r["category_id"] as? String ?? ""
               let budgeted = r["budgeted"] as? Int ?? 0
               if !incomeCatIds.contains(catId) {
                   totalBudgeted += budgeted
               }
           }
           
           func getCumulativeIncome(untilMonth: String) throws -> Int {
               let sql = """
                   SELECT SUM(amount) as total 
                   FROM transactions t
                   JOIN accounts a ON t.account_id = a.id
                   WHERE strftime('%Y-%m', date) <= ? 
                     AND t.transfer_id IS NULL 
                     AND a.offbudget = 0
                     AND t.category_id IN (SELECT id FROM categories WHERE is_income = 1);
               """
               let rows = try db.query(sql, arguments: [untilMonth])
               return rows.first?["total"] as? Int ?? 0
           }
           
           func getCumulativeBudgeted(untilMonth: String) throws -> Int {
               let sql = """
                   SELECT SUM(budgeted) as total 
                   FROM budget_category_values 
                   WHERE month <= ? 
                     AND category_id IN (SELECT id FROM categories WHERE is_income = 0);
               """
               let rows = try db.query(sql, arguments: [untilMonth])
               return rows.first?["total"] as? Int ?? 0
           }
           
           let cumIncomePrev = try getCumulativeIncome(untilMonth: prevMonthKey)
           let cumBudgetPrev = try getCumulativeBudgeted(untilMonth: prevMonthKey)
           let fromLastMonth = cumIncomePrev - cumBudgetPrev
           
           let incomeAvailable = fromLastMonth + totalIncome
           let toBudget = incomeAvailable - totalBudgeted
           
           let balanceRows = try db.query("SELECT SUM(amount) as balance FROM transactions WHERE strftime('%Y-%m', date) <= ?;", arguments: [month])
           let totalBalance = balanceRows.first?["balance"] as? Int ?? 0
           
           return BudgetMonth(
               month: month,
               incomeAvailable: incomeAvailable,
               lastMonthOverspent: 0,
               forNextMonth: 0,
               totalBudgeted: totalBudgeted,
               toBudget: toBudget,
               fromLastMonth: fromLastMonth,
               totalIncome: totalIncome,
               totalSpent: totalSpent,
               totalBalance: totalBalance
           )
       }
       
       public func updateBudgetAmount(month: String, categoryId: String, budgeted: Int) async throws {
           try db.execute("""
               INSERT INTO budget_category_values (month, category_id, budgeted, carryover)
               VALUES (?, ?, ?, 1)
               ON CONFLICT(month, category_id) DO UPDATE SET budgeted = excluded.budgeted;
           """, arguments: [month, categoryId, budgeted])
       }
       
       // MARK: - SimpleFIN Account Links
       public func fetchAccountLinks() async throws -> [String: String] {
           let rows = try db.query("SELECT simplefin_account_id, local_account_id FROM simplefin_account_links;")
           var links = [String: String]()
           for row in rows {
               if let sfId = row["simplefin_account_id"] as? String, let locId = row["local_account_id"] as? String {
                   links[sfId] = locId
               }
           }
           return links
       }
       
       public func saveAccountLink(simplefinId: String, name: String, localId: String) async throws {
           try db.execute("""
               INSERT INTO simplefin_account_links (simplefin_account_id, simplefin_account_name, local_account_id)
               VALUES (?, ?, ?)
               ON CONFLICT(simplefin_account_id) DO UPDATE SET local_account_id = excluded.local_account_id;
           """, arguments: [simplefinId, name, localId])
       }
       
       public func deleteAccountLink(simplefinId: String) async throws {
           try db.execute("DELETE FROM simplefin_account_links WHERE simplefin_account_id = ?;", arguments: [simplefinId])
       }
   }
   ```

### Verification Plan
- Build the app (Cmd+B) and confirm no compiler errors exist.

---

## Prompt 3: AppState State Management & Navigation Refactor (Phase 3)

### Objective
Update state management to manage local budget selections instead of remote HTTP server credentials. Adjust root navigation to launch either onboarding or the dashboard based on budget selection. Keep temporary shims in `AppState` for existing HTTP clients to preserve compilability.

### Files to Create / Modify
- **[MODIFY]** [AppState.swift](file:///Users/roshanlodha/Documents/actual-budget-app/iOSApp/Shared/AppState.swift)
- **[MODIFY]** [RootView.swift](file:///Users/roshanlodha/Documents/actual-budget-app/iOSApp/Features/RootView.swift)
- **[MODIFY]** [OnboardingView.swift](file:///Users/roshanlodha/Documents/actual-budget-app/iOSApp/Features/Onboarding/OnboardingView.swift)
- **[MODIFY]** [SettingsView.swift](file:///Users/roshanlodha/Documents/actual-budget-app/iOSApp/Features/Settings/SettingsView.swift)

### Step-by-Step Instructions

1. **Rewrite `AppState.swift`**:
   Replace the old server session state. Maintain compilability shims returning mock values so legacy HTTP client files still compile. Copy this implementation exactly:
   ```swift
   import Foundation
   import Combine

   public final class AppState: ObservableObject {
       public enum OnboardingState {
           case noBudgetSelected
           case ready
       }
       
       @Published var selectedBudgetID: String? {
           didSet {
               if let selectedBudgetID = selectedBudgetID {
                   UserDefaults.standard.set(selectedBudgetID, forKey: Keys.selectedBudgetID)
                   do {
                       try LocalBudgetFileManager.shared.createBudgetDirectory(for: selectedBudgetID)
                       let path = LocalBudgetFileManager.shared.sqliteFileURL(for: selectedBudgetID).path
                       let db = try SQLiteDB(path: path)
                       self.repository = LocalBudgetRepository(db: db)
                       self.onboardingState = .ready
                   } catch {
                       self.repository = nil
                       self.onboardingState = .noBudgetSelected
                   }
               } else {
                   UserDefaults.standard.removeObject(forKey: Keys.selectedBudgetID)
                   self.repository = nil
                   self.onboardingState = .noBudgetSelected
               }
           }
       }
       
       @Published var selectedBudgetDisplayName: String = "" {
           didSet { UserDefaults.standard.set(selectedBudgetDisplayName, forKey: Keys.selectedBudgetDisplayName) }
       }
       
       @Published var currencyCode: String {
           didSet { UserDefaults.standard.set(currencyCode, forKey: Keys.currencyCode) }
       }
       
       @Published var currentTheme: Theme {
           didSet { UserDefaults.standard.set(currentTheme.rawValue, forKey: Keys.currentTheme) }
       }
       
       @Published var onboardingState: OnboardingState = .noBudgetSelected
       @Published var repository: BudgetRepository?
       
       public enum Theme: String, CaseIterable, Identifiable {
           case Dark = "Dark"
           case amoledDark = "Dark (AMOLED)"
           case systemLight = "System Light"
           public var id: String { self.rawValue }
       }
       
       // --- SHIMS FOR COMPILABILITY WITH LEGACY NETWORKING CODE ---
       // (To be deleted in Phase 4 once Views are updated and Networking is removed)
       @Published public var baseURLString: String = "local://database"
       @Published public var apiKey: String = "local_key"
       @Published public var syncId: String = "local_sync"
       @Published public var budgetEncryptionPassword: String = ""
       public var isConfigured: Bool { onboardingState == .ready }
       public func resetConfiguration() {
           selectedBudgetID = nil
       }
       // -----------------------------------------------------------
       
       public init() {
           self.currencyCode = UserDefaults.standard.string(forKey: Keys.currencyCode) ?? Locale.current.currency?.identifier ?? "USD"
           let savedTheme = UserDefaults.standard.string(forKey: Keys.currentTheme) ?? ""
           self.currentTheme = Theme(rawValue: savedTheme) ?? .amoledDark
           self.selectedBudgetDisplayName = UserDefaults.standard.string(forKey: Keys.selectedBudgetDisplayName) ?? ""
           
           if let budgetId = UserDefaults.standard.string(forKey: Keys.selectedBudgetID) {
               DispatchQueue.main.async {
                   self.selectedBudgetID = budgetId
               }
           } else {
               self.onboardingState = .noBudgetSelected
           }
       }
       
       private enum Keys {
           static let selectedBudgetID = "SelectedBudgetID"
           static let selectedBudgetDisplayName = "SelectedBudgetDisplayName"
           static let currencyCode = "ActualCurrencyCode"
           static let currentTheme = "ActualCurrentTheme"
       }
   }
   ```

2. **Update `RootView.swift`**:
   Adjust navigation routing checks to use `onboardingState`:
   ```swift
   import SwiftUI

   struct RootView: View {
       @EnvironmentObject private var appState: AppState

       var body: some View {
           if appState.onboardingState == .ready {
               MainTabView()
           } else {
               OnboardingView()
           }
       }
   }
   ```

3. **Rewrite `OnboardingView.swift`**:
   Replace the old server input fields with a simple layout asking for a display name:
   ```swift
   import SwiftUI

   struct OnboardingView: View {
       @EnvironmentObject private var appState: AppState
       @State private var budgetName: String = ""
       @State private var errorMessage: String?
       
       var body: some View {
           ZStack {
               AppBackground()
               VStack(spacing: 24) {
                   Spacer()
                   Text("Welcome to Actual")
                       .font(AppTheme.Fonts.largeTitle)
                       .foregroundColor(.primary)
                       .multilineTextAlignment(.center)
                   
                   Text("Create your local budget on-device. Safe, fast, offline-first.")
                       .font(AppTheme.Fonts.body)
                       .foregroundColor(.secondary)
                       .multilineTextAlignment(.center)
                       .padding(.horizontal)

                   GlassCard {
                       VStack(alignment: .leading, spacing: 12) {
                           Text("Budget Display Name")
                               .font(AppTheme.Fonts.subheadline)
                               .foregroundColor(.secondary)
                           TextField("", text: $budgetName, prompt: Text("e.g. My Personal Finances").foregroundColor(.secondary.opacity(0.5)))
                               .foregroundColor(.primary)
                               .textFieldStyle(.plain)
                               .padding(10)
                               .background(Color.primary.opacity(0.05))
                               .cornerRadius(8)
                       }
                   }
                   .padding(.horizontal)

                   Button(action: createBudget) {
                       Text("Create New Budget")
                           .font(AppTheme.Fonts.headline)
                           .frame(maxWidth: .infinity)
                   }
                   .buttonStyle(.borderedProminent)
                   .tint(AppTheme.accent)
                   .disabled(budgetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                   .padding(.horizontal)
                   
                   Spacer()
               }
               .padding()
           }
           .alert("Error", isPresented: .constant(errorMessage != nil)) {
               Button("OK") { errorMessage = nil }
           } message: { Text(errorMessage ?? "") }
       }

       private func createBudget() {
           let cleanName = budgetName.trimmingCharacters(in: .whitespacesAndNewlines)
           guard !cleanName.isEmpty else { return }
           let budgetId = UUID().uuidString
           
           let metaURL = LocalBudgetFileManager.shared.metadataFileURL(for: budgetId)
           try? LocalBudgetFileManager.shared.createBudgetDirectory(for: budgetId)
           
           let metadata: [String: Any] = [
               "displayName": cleanName,
               "createdAt": ISO8601DateFormatter().string(from: Date()),
               "lastModifiedAt": ISO8601DateFormatter().string(from: Date())
           ]
           if let data = try? JSONSerialization.data(withJSONObject: metadata) {
               try? data.write(to: metaURL)
           }
           
           appState.selectedBudgetDisplayName = cleanName
           appState.selectedBudgetID = budgetId
       }
   }
   ```

4. **Rewrite `SettingsView.swift`**:
   Remove server options. Display the active budget display name and currency:
   ```swift
   import SwiftUI

   struct SettingsView: View {
       @EnvironmentObject private var appState: AppState
       
       var body: some View {
           ZStack {
               AppBackground()
               List {
                   Section("Active Budget") {
                       HStack {
                           Text("Name")
                           Spacer()
                           Text(appState.selectedBudgetDisplayName)
                               .foregroundColor(.secondary)
                       }
                       HStack {
                           Text("ID")
                           Spacer()
                           Text(appState.selectedBudgetID ?? "Unknown")
                               .font(.caption.monospaced())
                               .foregroundColor(.secondary)
                               .lineLimit(1)
                       }
                       Button(role: .destructive) {
                           appState.selectedBudgetID = nil
                       } label: {
                           Label("Switch Budget / Disconnect", systemImage: "arrow.left.arrow.right")
                       }
                   }
                   .listRowBackground(Color.primary.opacity(0.05))
                   
                   Section("Preferences") {
                       Picker("Theme", selection: $appState.currentTheme) {
                           ForEach(AppState.Theme.allCases) { theme in
                               Text(theme.rawValue).tag(theme)
                           }
                       }
                       Picker("Currency", selection: $appState.currencyCode) {
                           ForEach(CurrencyFormatter.supportedCurrencies, id: \.0) { code, name in
                               Text("\(code) - \(name)").tag(code)
                           }
                       }
                   }
                   .listRowBackground(Color.primary.opacity(0.05))
                   
                   Section("Logs") {
                       NavigationLink {
                           LogsView()
                       } label: {
                           Label("View System Logs", systemImage: "doc.text.magnifyingglass")
                       }
                   }
                   .listRowBackground(Color.primary.opacity(0.05))
               }
               .scrollContentBackground(.hidden)
           }
           .navigationTitle("Settings")
       }
   }
   ```

### Verification Plan
- Build the app and confirm it compiles cleanly.
- Run the app. It should launch into `OnboardingView` asking for a "Budget Display Name".
- Enter "My Local Budget" and tap "Create New Budget". The app should transition to the dashboard.
- Go to Settings, verify the budget name is "My Local Budget". Tap "Switch Budget / Disconnect". The app should return to Onboarding immediately.

---

## Prompt 4: Local View Integration & Calculations Engine (Phase 4)

### Objective
Update all SwiftUI screens to call `BudgetRepository` from `AppState` instead of legacy networking code. Implement interactive budgeting edits in `BudgetView` using alert input overlays. Delete the legacy `Networking/` directory and remove the temporary shims from `AppState.swift`.

### Files to Create / Modify / Delete
- **[MODIFY]** [AppState.swift](file:///Users/roshanlodha/Documents/actual-budget-app/iOSApp/Shared/AppState.swift)
- **[MODIFY]** [DashboardView.swift](file:///Users/roshanlodha/Documents/actual-budget-app/iOSApp/Features/Dashboard/DashboardView.swift)
- **[MODIFY]** [AccountsView.swift](file:///Users/roshanlodha/Documents/actual-budget-app/iOSApp/Features/Accounts/AccountsView.swift)
- **[MODIFY]** [TransactionsView.swift](file:///Users/roshanlodha/Documents/actual-budget-app/iOSApp/Features/Transactions/TransactionsView.swift)
- **[MODIFY]** [AllTransactionsView.swift](file:///Users/roshanlodha/Documents/actual-budget-app/iOSApp/Features/Transactions/AllTransactionsView.swift)
- **[MODIFY]** [TransactionEditor.swift](file:///Users/roshanlodha/Documents/actual-budget-app/iOSApp/Features/Transactions/TransactionEditor.swift)
- **[MODIFY]** [BudgetView.swift](file:///Users/roshanlodha/Documents/actual-budget-app/iOSApp/Features/Budget/BudgetView.swift)
- **[DELETE]** `iOSApp/Networking/ActualAPIClient.swift`
- **[DELETE]** `iOSApp/Networking/APIEndpoints.swift`
- **[DELETE]** `iOSApp/Networking/DemoDataService.swift`

### Step-by-Step Instructions

1. **Delete Shims in `AppState.swift`**:
   Remove the temporary shims block (lines marked for deletion in Phase 3) from [AppState.swift](file:///Users/roshanlodha/Documents/actual-budget-app/iOSApp/Shared/AppState.swift).

2. **Delete Networking folder files**:
   Delete `ActualAPIClient.swift`, `APIEndpoints.swift`, and `DemoDataService.swift`.

3. **Rewrite `DashboardView.swift`**:
   Refactor dashboard queries to load data from the local SQLite repository:
   ```swift
   import SwiftUI
   import WidgetKit

   struct DashboardView: View {
       @EnvironmentObject private var appState: AppState
       @State private var accounts: [Account] = []
       @State private var categoriesById: [String: String] = [:]
       @State private var payeesById: [String: Payee] = [:]
       @State private var transactions: [Transaction] = []
       @State private var errorMessage: String?
       @State private var activeSheet: SheetType?

       var onBudgetAccounts: [Account] { accounts.filter { !$0.offbudget } }
       private var recentFive: [Transaction] { recentNonTransferOnBudget().prefix(5).map { $0 } }
       
       private var repository: BudgetRepository {
           guard let repo = appState.repository else { fatalError("Repository unavailable") }
           return repo
       }

       var body: some View {
           ZStack {
               AppBackground()
               List {
                   Section {
                       VStack(spacing: 24) {
                           Text("Overview")
                               .font(AppTheme.Fonts.largeTitle)
                               .foregroundColor(.primary)
                               .frame(maxWidth: .infinity, alignment: .leading)
                               .padding(.top)

                           GlassCard {
                               VStack(alignment: .leading, spacing: 8) {
                                   Text("Spent This Month")
                                       .font(AppTheme.Fonts.body)
                                       .foregroundStyle(.secondary)
                                   Text(formatMoney(spentThisMonth()))
                                       .font(AppTheme.Fonts.title)
                                       .foregroundColor(.primary)
                                       .monospacedDigit()
                               }
                               .frame(maxWidth: .infinity, alignment: .leading)
                           }

                           ScrollView(.horizontal, showsIndicators: false) {
                               HStack(spacing: 16) {
                                   metricCard(title: "Spent Today", value: spentToday())
                                   metricCard(title: "Spent Last Month", value: spentLastMonth())
                                   metricCard(title: "On-budget Accounts", value: onBudgetAccounts.count, isMoney: false)
                               }
                           }
                       }
                       .listRowBackground(Color.clear)
                       .listRowSeparator(.hidden)
                   }

                   Section(header:
                       HStack {
                           Text("Recent Activity")
                               .font(AppTheme.Fonts.title)
                               .foregroundColor(.primary)
                           Spacer()
                           NavigationLink("View All") { AllTransactionsView() }
                               .foregroundColor(AppTheme.accent)
                       }
                   ) {
                       if recentFive.isEmpty {
                           GlassCard {
                               Text("No recent transactions to show.")
                                   .font(AppTheme.Fonts.body)
                                   .foregroundStyle(.secondary)
                                   .frame(maxWidth: .infinity, minHeight: 100)
                           }
                           .listRowBackground(Color.clear)
                           .listRowSeparator(.hidden)
                       } else {
                           ForEach(recentFive, id: \.id) { tx in
                               TransactionRow(
                                   transaction: tx,
                                   accounts: accounts,
                                   payeesById: payeesById,
                                   categoriesById: categoriesById,
                                   currencyCode: appState.currencyCode,
                                   onEdit: { t in activeSheet = .edit(t) },
                                   onDelete: { t in Task { await delete(t) } }
                               )
                               .listRowBackground(Color.clear)
                               .listRowSeparator(.hidden)
                           }
                       }
                       Button {
                           activeSheet = .add
                       } label: {
                           HStack {
                               Image(systemName: "plus")
                               Text("Add Transaction")
                           }
                           .font(AppTheme.Fonts.headline)
                           .foregroundColor(AppTheme.accent)
                           .frame(maxWidth: .infinity)
                           .padding()
                           .background(.ultraThinMaterial)
                           .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                       }
                       .listRowBackground(Color.clear)
                       .listRowSeparator(.hidden)
                   }
               }
               .listStyle(.plain)
               .scrollContentBackground(.hidden)
           }
           .navigationBarHidden(true)
           .task { await load() }
           .sheet(item: $activeSheet) { sheetType in
               switch sheetType {
               case .add:
                   TransactionEditor(transaction: nil, initialAccountId: nil, onSave: { _ in Task { await load() } })
               case .edit(let transaction):
                   TransactionEditor(transaction: transaction, initialAccountId: nil, onSave: { _ in Task { await load() } })
               }
           }
           .alert("Error", isPresented: .constant(errorMessage != nil), actions: {
               Button("OK") { errorMessage = nil }
           }, message: {
               Text(errorMessage ?? "An unknown error occurred.")
           })
       }

       private func metricCard(title: String, value: Int, isMoney: Bool = true) -> some View {
           GlassCard(cornerRadius: 16) {
               VStack(alignment: .leading, spacing: 4) {
                   Text(title)
                       .font(AppTheme.Fonts.footnote)
                       .foregroundStyle(.secondary)
                   Text(isMoney ? formatMoney(value) : String(value))
                       .font(AppTheme.Fonts.subtitle)
                       .foregroundColor(.primary)
               }
               .frame(width: 140, alignment: .leading)
           }
       }

       private func load() async {
           do {
               let accList = try await repository.fetchAccounts()
               let catList = try await repository.fetchCategories()
               let payeeList = try await repository.fetchPayees()
               
               let since = firstOfThisMonthMinus(days: 31)
               var allTxs = [Transaction]()
               for acc in accList {
                   let list = try await repository.fetchTransactions(accountId: acc.id, since: since)
                   allTxs.append(contentsOf: list)
               }
               
               await MainActor.run {
                   self.accounts = accList
                   self.transactions = allTxs
                   self.categoriesById = Dictionary(uniqueKeysWithValues: catList.map { ($0.id, $0.name) })
                   self.payeesById = Dictionary(uniqueKeysWithValues: payeeList.map { ($0.id, $0) })
                   
                   SharedDataManager.shared.save(spentToday: self.spentToday(), currencyCode: self.appState.currencyCode)
               }
           } catch {
               await MainActor.run { errorMessage = error.localizedDescription }
           }
       }

       private func spentToday() -> Int {
           let today = format(date: Date())
           let onBudgetIds = Set(onBudgetAccounts.map { $0.id })
           let todays = transactions.filter { $0.date == today && onBudgetIds.contains($0.account) && !isTransfer($0) }
           return -todays.map { $0.amount ?? 0 }.filter { $0 < 0 }.reduce(0, +)
       }

       private func spentThisMonth() -> Int {
           let (start, end) = monthRange(date: Date())
           let onBudgetIds = Set(onBudgetAccounts.map { $0.id })
           let list = transactions.filter { $0.date >= start && $0.date <= end && onBudgetIds.contains($0.account) && !isTransfer($0) }
           return -list.map { $0.amount ?? 0 }.filter { $0 < 0 }.reduce(0, +)
       }

       private func spentLastMonth() -> Int {
           let cal = Calendar(identifier: .gregorian)
           let lastMonthDate = cal.date(byAdding: .month, value: -1, to: Date()) ?? Date()
           let (start, end) = monthRange(date: lastMonthDate)
           let onBudgetIds = Set(onBudgetAccounts.map { $0.id })
           let list = transactions.filter { $0.date >= start && $0.date <= end && onBudgetIds.contains($0.account) && !isTransfer($0) }
           return -list.map { $0.amount ?? 0 }.filter { $0 < 0 }.reduce(0, +)
       }

       private func isTransfer(_ tx: Transaction) -> Bool {
           if tx.transfer_id != nil { return true }
           if let payeeId = tx.payee, let p = payeesById[payeeId], p.transfer_acct != nil { return true }
           return false
       }

       private func recentNonTransferOnBudget() -> [Transaction] {
           let onBudgetIds = Set(onBudgetAccounts.map { $0.id })
           return transactions.filter { onBudgetIds.contains($0.account) && !isTransfer($0) }.sorted { $0.date > $1.date }
       }
       
       private func monthRange(date: Date) -> (String, String) {
           let cal = Calendar(identifier: .gregorian)
           let comps = cal.dateComponents([.year, .month], from: date)
           let startDate = cal.date(from: comps) ?? date
           let endDate = cal.date(byAdding: DateComponents(month: 1, day: -1), to: startDate) ?? date
           return (format(date: startDate), format(date: endDate))
       }

       private func firstOfThisMonthMinus(days: Int) -> String {
           let cal = Calendar(identifier: .gregorian)
           let comps = cal.dateComponents([.year, .month], from: Date())
           let start = cal.date(from: comps) ?? Date()
           let since = cal.date(byAdding: .day, value: -days, to: start) ?? start
           return format(date: since)
       }

       private func format(date: Date) -> String {
           let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.string(from: date)
       }

       private func formatMoney(_ amount: Int) -> String {
           return CurrencyFormatter.shared.format(amount, currencyCode: appState.currencyCode)
       }

       private func delete(_ tx: Transaction) async {
           guard let txId = tx.id else { return }
           do {
               try await repository.deleteTransaction(id: txId)
               await load()
           } catch {
               await MainActor.run { errorMessage = error.localizedDescription }
           }
       }
   }
   ```

4. **Rewrite `AccountsView.swift`**:
   Load balances directly from SQLite:
   ```swift
   import SwiftUI

   struct AccountsView: View {
       @EnvironmentObject private var appState: AppState
       @State private var accounts: [Account] = []
       @State private var search: String = ""
       @State private var isLoading = false
       @State private var errorMessage: String?
       @State private var showingCreate = false
       @State private var balancesById: [String: Int] = [:]

       private var repository: BudgetRepository {
           guard let repo = appState.repository else { fatalError("Repository unavailable") }
           return repo
       }

       private var onBudget: [Account] {
           let list = accounts.filter { !$0.offbudget }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
           guard !search.isEmpty else { return list }
           return list.filter { $0.name.localizedCaseInsensitiveContains(search) }
       }

       private var offBudget: [Account] {
           let list = accounts.filter { $0.offbudget }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
           guard !search.isEmpty else { return list }
           return list.filter { $0.name.localizedCaseInsensitiveContains(search) }
       }

       var body: some View {
           ZStack {
               AppBackground()
               ScrollView {
                   VStack(spacing: 24) {
                       GlassCard(cornerRadius: 15) {
                           HStack {
                               VStack(alignment: .leading) {
                                   Text("Total Balance")
                                       .font(AppTheme.Fonts.title)
                                       .foregroundColor(.primary)
                               }
                               Spacer()
                               Text(formattedAmount(totalAll()))
                                   .font(AppTheme.Fonts.body.monospacedDigit())
                                   .foregroundColor(.primary)
                           }
                       }
                       if accounts.isEmpty && !isLoading {
                           emptyState
                       }
                       if !onBudget.isEmpty {
                           accountSection(title: "On-Budget", accounts: onBudget)
                       }
                       if !offBudget.isEmpty {
                           accountSection(title: "Off-Budget", accounts: offBudget)
                       }
                   }
                   .padding()
               }
           }
           .navigationTitle("Accounts")
           .toolbar {
               ToolbarItem(placement: .navigationBarTrailing) {
                   Button { showingCreate = true } label: {
                       Image(systemName: "plus.circle.fill")
                           .font(.title2)
                           .foregroundColor(AppTheme.accent)
                   }
               }
           }
           .task { await reload() }
           .refreshable { await reload() }
           .alert("Error", isPresented: .constant(errorMessage != nil)) {
               Button("OK") { errorMessage = nil }
           } message: { Text(errorMessage ?? "") }
           .sheet(isPresented: $showingCreate) {
               CreateAccountSheet { name, offbudget in
                   Task { await createAccount(name: name, offbudget: offbudget) }
               }
               .presentationDetents([.height(250)])
           }
       }

       private func accountSection(title: String, accounts: [Account]) -> some View {
           VStack(alignment: .leading, spacing: 16) {
               HStack {
                   Text(title)
                       .font(AppTheme.Fonts.title)
                       .foregroundColor(.primary)
                   Spacer()
                   Text(formattedAmount(totalFor(accounts: accounts)))
                       .font(AppTheme.Fonts.body.monospacedDigit())
                       .foregroundColor(.primary)
               }
               .padding(.horizontal)

               ForEach(accounts) { account in
                   NavigationLink(destination: TransactionsView(account: account)) {
                       GlassCard(cornerRadius: 15) {
                           HStack {
                               VStack(alignment: .leading) {
                                   Text(account.name)
                                       .font(AppTheme.Fonts.headline)
                                       .foregroundColor(.primary)
                                   Text(account.closed ? "Closed" : "Active")
                                       .font(AppTheme.Fonts.footnote)
                                       .foregroundStyle(account.closed ? .yellow : .secondary)
                               }
                               Spacer()
                               Text(formattedAmount(balancesById[account.id]))
                                   .font(AppTheme.Fonts.body.monospacedDigit())
                                   .foregroundColor(.primary)
                           }
                       }
                   }
                   .buttonStyle(.plain)
               }
           }
       }

       private func reload() async {
           isLoading = true
           defer { isLoading = false }
           do {
               let list = try await repository.fetchAccounts()
               var balances = [String: Int]()
               for acc in list {
                   balances[acc.id] = try await repository.fetchAccountBalance(accountId: acc.id)
               }
               await MainActor.run {
                   self.accounts = list
                   self.balancesById = balances
               }
           } catch {
               await MainActor.run { errorMessage = error.localizedDescription }
           }
       }

       private func formattedAmount(_ amount: Int?) -> String {
           return CurrencyFormatter.shared.format(amount ?? 0, currencyCode: appState.currencyCode)
       }

       private func totalFor(accounts: [Account]) -> Int {
           accounts.map { balancesById[$0.id] ?? 0 }.reduce(0, +)
       }

       private func totalAll() -> Int {
           totalFor(accounts: self.accounts)
       }

       private func createAccount(name: String, offbudget: Bool) async {
           do {
               _ = try await repository.createAccount(name: name, offbudget: offbudget)
               await reload()
           } catch {
               await MainActor.run { errorMessage = error.localizedDescription }
           }
       }

       private var emptyState: some View {
           GlassCard(cornerRadius: 15) {
               VStack(alignment: .leading, spacing: 12) {
                   Text("No accounts yet")
                       .font(AppTheme.Fonts.headline)
                       .foregroundColor(.primary)
                   Text("Create your first account to start tracking balances and transactions.")
                       .font(AppTheme.Fonts.body)
                       .foregroundStyle(.secondary)
                   Button("Create your first account") {
                       showingCreate = true
                   }
                   .buttonStyle(.borderedProminent)
                   .tint(AppTheme.accent)
               }
               .frame(maxWidth: .infinity, alignment: .leading)
           }
       }
   }

   private struct CreateAccountSheet: View {
       var onCreate: (String, Bool) -> Void
       @Environment(\.dismiss) private var dismiss
       @State private var name: String = ""
       @State private var offbudget: Bool = false

       var body: some View {
           NavigationStack {
               ZStack {
                   AppBackground()
                   Form {
                       Section(header: Text("Account Details")) {
                           TextField("Name", text: $name)
                           Toggle("Off-budget account", isOn: $offbudget)
                       }
                       .listRowBackground(Color.primary.opacity(0.05))
                   }
                   .scrollContentBackground(.hidden)
               }
               .navigationTitle("New Account")
               .navigationBarTitleDisplayMode(.inline)
               .toolbar {
                   ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                   ToolbarItem(placement: .confirmationAction) {
                       Button("Create") {
                           onCreate(name, offbudget)
                           dismiss()
                       }
                       .disabled(name.isEmpty)
                   }
               }
               .tint(AppTheme.accent)
           }
       }
   }
   ```

5. **Rewrite `TransactionsView.swift`**:
   Adjust to connect directly to local repository models:
   ```swift
   import SwiftUI

   struct TransactionsView: View {
       let account: Account
       @EnvironmentObject private var appState: AppState
       @State private var transactions: [Transaction] = []
       @State private var accounts: [Account] = []
       @State private var categoriesById: [String: String] = [:]
       @State private var payeesById: [String: Payee] = [:]
       @State private var errorMessage: String?
       @State private var activeSheet: SheetType?

       private var repository: BudgetRepository {
           guard let repo = appState.repository else { fatalError("Repository unavailable") }
           return repo
       }

       var sortedTransactions: [Transaction] {
           transactions.sorted { ($0.date) > ($1.date) }
       }

       var body: some View {
           ZStack {
               AppBackground()
               if sortedTransactions.isEmpty && errorMessage == nil {
                   VStack(spacing: 16) {
                       GlassCard {
                           VStack(alignment: .leading, spacing: 10) {
                               Text("No transactions yet")
                                   .font(AppTheme.Fonts.headline)
                                   .foregroundColor(.primary)
                               Text("Add a transaction to start building this account's history.")
                                   .font(AppTheme.Fonts.body)
                                   .foregroundStyle(.secondary)
                               Button("Add Transaction") {
                                   activeSheet = .add
                               }
                               .buttonStyle(.borderedProminent)
                               .tint(AppTheme.accent)
                           }
                           .frame(maxWidth: .infinity, alignment: .leading)
                       }
                       Spacer()
                   }
                   .padding()
               } else {
                   List {
                       ForEach(sortedTransactions, id: \.id) { tx in
                           TransactionRow(
                               transaction: tx,
                               accounts: accounts,
                               payeesById: payeesById,
                               categoriesById: categoriesById,
                               currencyCode: appState.currencyCode,
                               onEdit: { t in activeSheet = .edit(t) },
                               onDelete: { t in Task { await delete(t) } }
                           )
                           .contextMenu { contextMenuItems(for: tx) }
                       }
                       .listRowBackground(Color.clear)
                       .listRowSeparator(.hidden)
                   }
                   .listStyle(.plain)
                   .scrollContentBackground(.hidden)
               }
           }
           .navigationTitle(account.name)
           .toolbar {
               ToolbarItem(placement: .navigationBarTrailing) {
                   Button {
                       activeSheet = .add
                   } label: { Image(systemName: "plus") }
               }
           }
           .task { await loadAll() }
           .refreshable { await loadAll() }
           .sheet(item: $activeSheet) { sheetType in
               switch sheetType {
               case .add:
                   TransactionEditor(transaction: nil, initialAccountId: account.id, onSave: { _ in Task { await loadAll() } })
               case .edit(let transaction):
                   TransactionEditor(transaction: transaction, initialAccountId: account.id, onSave: { _ in Task { await loadAll() } })
               }
           }
           .alert("Error", isPresented: .constant(errorMessage != nil)) {
               Button("OK") { errorMessage = nil }
           } message: { Text(errorMessage ?? "") }
       }
       
       @ViewBuilder
       private func contextMenuItems(for tx: Transaction) -> some View {
           if let destAccount = transferDestinationAccount(tx) {
               NavigationLink {
                   TransactionsView(account: destAccount)
               } label: {
                   Label("Go to Transfer Account", systemImage: "arrow.right.arrow.left.circle")
               }
           }
           
           Button(role: .destructive) {
               Task { await delete(tx) }
           } label: {
               Label("Delete Transaction", systemImage: "trash")
           }
       }

       private func delete(_ tx: Transaction) async {
           guard let txId = tx.id else { return }
           do {
               try await repository.deleteTransaction(id: txId)
               await loadAll()
           } catch {
               await MainActor.run { errorMessage = error.localizedDescription }
           }
       }
       
       private func transferDestinationAccount(_ tx: Transaction) -> Account? {
           if let payeeId = tx.payee,
              let p = payeesById[payeeId],
              let destAcctId = p.transfer_acct {
               return accounts.first { $0.id == destAcctId }
           }
           return nil
       }

       private func loadAll() async {
           do {
               let accountList = try await repository.fetchAccounts()
               let categories = try await repository.fetchCategories()
               let payeesList = try await repository.fetchPayees()
               let list = try await repository.fetchTransactions(accountId: account.id, since: defaultSinceDate())
               
               let catMap = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0.name) })
               let payeeMap = Dictionary(uniqueKeysWithValues: payeesList.map { ($0.id, $0) })
               
               await MainActor.run {
                   self.accounts = accountList
                   categoriesById = catMap
                   payeesById = payeeMap
                   transactions = list
               }
           } catch {
               await MainActor.run { errorMessage = error.localizedDescription }
           }
       }
       
       private func formattedSignedAmount(_ amount: Int?) -> String {
           return CurrencyFormatter.shared.formatSigned(amount ?? 0, currencyCode: appState.currencyCode)
       }

       private func categoryName(_ id: String?) -> String? {
           guard let id else { return nil }
           return categoriesById[id]
       }

       private func payeeText(_ tx: Transaction) -> String {
           if let account = transferDestinationAccount(tx) {
               return "Transfer \((tx.amount ?? 0) < 0 ? "to" : "from"): \(account.name)"
           }
           if let payeeId = tx.payee, let p = payeesById[payeeId] { return p.name }
           if let n = tx.payee_name, !n.isEmpty { return n }
           return "(No payee)"
       }
       
       private func defaultSinceDate() -> String {
           let cal = Calendar(identifier: .gregorian)
           let start = cal.date(byAdding: .year, value: -1, to: Date()) ?? Date()
           let f = DateFormatter(); f.calendar = cal; f.dateFormat = "yyyy-MM-dd"; return f.string(from: start)
       }
   }
   ```

6. **Rewrite `AllTransactionsView.swift`**:
   Load transactions from SQLite:
   ```swift
   import SwiftUI

   struct AllTransactionsView: View {
       @EnvironmentObject private var appState: AppState
       @State private var transactions: [Transaction] = []
       @State private var accounts: [Account] = []
       @State private var payeesById: [String: Payee] = [:]
       @State private var categoriesById: [String: String] = [:]
       @State private var errorMessage: String?
       @State private var isLoading = false
       @State private var onBudgetOnly: Bool = true
       @State private var filterGranularity: Granularity = .day
       @State private var filterValue: Int = 30
       @State private var activeSheet: SheetType?

       private var repository: BudgetRepository {
           guard let repo = appState.repository else { fatalError("Repository unavailable") }
           return repo
       }

       enum Granularity: String, CaseIterable, Identifiable {
           case day = "Days", week = "Weeks", month = "Months", year = "Years"
           var id: String { rawValue }
       }

       var filteredTransactions: [Transaction] {
           let onBudgetAccountIds = Set(accounts.filter { !$0.offbudget }.map { $0.id })
           let allAccountIds = Set(accounts.map { $0.id })
           let targetAccountIds = onBudgetOnly ? onBudgetAccountIds : allAccountIds
           
           return transactions
               .filter { targetAccountIds.contains($0.account) }
               .sorted { $0.date > $1.date }
       }

       private var listTransactions: [Transaction] {
           let since = sinceDateString()
           return filteredTransactions
               .filter { $0.date >= since }
               .filter { !isTransferToOnBudget($0) }
       }

       var body: some View {
           ZStack {
               AppBackground()
               List {
                   filtersBar
                       .listRowBackground(Color.clear)
                       .listRowSeparator(.hidden)
                       .listRowInsets(EdgeInsets())

                   if listTransactions.isEmpty && !isLoading {
                       GlassCard(cornerRadius: 15) {
                           VStack(alignment: .leading, spacing: 10) {
                               Text("No transactions yet")
                                   .font(AppTheme.Fonts.headline)
                                   .foregroundColor(.primary)
                               Text("Add a transaction to start building your history.")
                                   .font(AppTheme.Fonts.body)
                                   .foregroundStyle(.secondary)
                           }
                           .frame(maxWidth: .infinity, alignment: .leading)
                       }
                       .listRowBackground(Color.clear)
                       .listRowSeparator(.hidden)
                   } else {
                       ForEach(listTransactions, id: \.id) { tx in
                           TransactionRow(
                               transaction: tx,
                               accounts: accounts,
                               payeesById: payeesById,
                               categoriesById: categoriesById,
                               currencyCode: appState.currencyCode,
                               onEdit: { t in activeSheet = .edit(t) },
                               onDelete: { t in Task { await delete(t) } }
                           )
                       }
                       .listRowBackground(Color.clear)
                       .listRowSeparator(.hidden)
                   }
               }
               .listStyle(.plain)
               .scrollContentBackground(.hidden)
           }
           .navigationTitle("All Transactions")
           .toolbar {
               ToolbarItem(placement: .navigationBarTrailing) {
                   Button {
                       activeSheet = .add
                   } label: { Image(systemName: "plus") }
               }
           }
           .task { await load() }
           .refreshable { await load() }
           .sheet(item: $activeSheet) { sheetType in
               switch sheetType {
               case .add:
                   TransactionEditor(transaction: nil, initialAccountId: nil, onSave: { _ in Task { await load() } })
               case .edit(let transaction):
                   TransactionEditor(transaction: transaction, initialAccountId: nil, onSave: { _ in Task { await load() } })
               }
           }
           .alert("Error", isPresented: .constant(errorMessage != nil)) {
               Button("OK") { errorMessage = nil }
           } message: { Text(errorMessage ?? "") }
       }

       private func delete(_ tx: Transaction) async {
           guard let id = tx.id else { return }
           do {
               try await repository.deleteTransaction(id: id)
               await load()
           } catch {
               await MainActor.run { errorMessage = error.localizedDescription }
           }
       }

       private var filtersBar: some View {
           GlassCard(cornerRadius: 0) {
               VStack(spacing: 16) {
                   Toggle("On-budget only", isOn: $onBudgetOnly)
                       .tint(AppTheme.accent)
                   
                   Picker("Range", selection: $filterGranularity) {
                       ForEach(Granularity.allCases) { g in
                           Text(g.rawValue).tag(g)
                       }
                   }
                   .pickerStyle(.segmented)
                   
                   Stepper("Last \(filterValue) \(filterGranularity.rawValue)", value: $filterValue, in: 1...365)
               }
               .foregroundColor(.primary)
           }
           .padding(.bottom)
       }

       private func isTransferToOnBudget(_ tx: Transaction) -> Bool {
           if let payeeId = tx.payee, let p = payeesById[payeeId], let destId = p.transfer_acct {
               if let dest = accounts.first(where: { $0.id == destId }) {
                   return !dest.offbudget
               }
           }
           return false
       }

       private func load() async {
           isLoading = true
           defer { isLoading = false }
           do {
               let since = sinceDateString()
               let accountsList = try await repository.fetchAccounts()
               let payeesList = try await repository.fetchPayees()
               let categories = try await repository.fetchCategories()
               
               let mappingCats = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0.name) })
               let mappingPayees = Dictionary(uniqueKeysWithValues: payeesList.map { ($0.id, $0) })
               
               var allTxs = [Transaction]()
               for acc in accountsList {
                   let list = try await repository.fetchTransactions(accountId: acc.id, since: since)
                   allTxs.append(contentsOf: list)
               }
               
               await MainActor.run {
                   self.accounts = accountsList
                   self.categoriesById = mappingCats
                   self.payeesById = mappingPayees
                   self.transactions = allTxs
               }
           } catch {
               await MainActor.run { errorMessage = error.localizedDescription }
           }
       }
       
       private func sinceDateString() -> String {
           let cal = Calendar.current
           let now = Date()
           let fromDate: Date
           switch filterGranularity {
           case .day: fromDate = cal.date(byAdding: .day, value: -filterValue, to: now) ?? now
           case .week: fromDate = cal.date(byAdding: .weekOfYear, value: -filterValue, to: now) ?? now
           case .month: fromDate = cal.date(byAdding: .month, value: -filterValue, to: now) ?? now
           case .year: fromDate = cal.date(byAdding: .year, value: -filterValue, to: now) ?? now
           }
           let formatter = DateFormatter()
           formatter.dateFormat = "yyyy-MM-dd"
           return formatter.string(from: fromDate)
       }

       private func formattedSignedAmount(_ amount: Int?) -> String {
           CurrencyFormatter.shared.formatSigned(amount ?? 0, currencyCode: appState.currencyCode)
       }

       private func payeeText(_ tx: Transaction) -> String {
           if let payeeId = tx.payee, let p = payeesById[payeeId] { return p.name }
           if let n = tx.payee_name, !n.isEmpty { return n }
           return "(No payee)"
       }
   }
   ```

7. **Rewrite `TransactionEditor.swift`**:
   Write transactions locally:
   ```swift
   import SwiftUI

   struct TransactionEditor: View {
       enum PayeeInputMode { case picker, custom }

       var transaction: Transaction?
       var initialAccountId: String?
       var onSave: (Transaction) -> Void
       
       @EnvironmentObject private var appState: AppState
       @Environment(\.dismiss) private var dismiss

       @State private var accounts: [Account] = []
       @State private var categoriesById: [String: String] = [:]
       @State private var payees: [Payee] = []
       @State private var errorMessage: String?
       
       @State private var date: Date
       @State private var amountString: String
       @State private var isNegative: Bool
       @State private var selectedPayeeId: String
       @State private var selectedTransferId: String?
       @State private var customPayee: String
       @State private var payeeMode: PayeeInputMode
       @State private var notes: String
       @State private var categoryId: String?
       @State private var selectedAccountId: String

       private var repository: BudgetRepository {
           guard let repo = appState.repository else { fatalError("Repository unavailable") }
           return repo
       }

       init(transaction: Transaction?, initialAccountId: String?, onSave: @escaping (Transaction) -> Void) {
           self.transaction = transaction
           self.initialAccountId = initialAccountId
           self.onSave = onSave

           if let t = transaction {
               _date = State(initialValue: Self.parseDate(t.date) ?? Date())
               _amountString = State(initialValue: Self.formatAmountForDisplay(abs(t.amount ?? 0)))
               _isNegative = State(initialValue: (t.amount ?? 0) < 0)
               
               if let payeeId = t.payee, !payeeId.isEmpty {
                   _selectedPayeeId = State(initialValue: payeeId)
                   _payeeMode = State(initialValue: .picker)
                   _customPayee = State(initialValue: "")
               } else if let payeeName = t.payee_name, !payeeName.isEmpty {
                   _customPayee = State(initialValue: payeeName)
                   _payeeMode = State(initialValue: .custom)
                   _selectedPayeeId = State(initialValue: "")
               } else {
                   _payeeMode = State(initialValue: .picker)
                   _selectedPayeeId = State(initialValue: "")
                   _customPayee = State(initialValue: "")
               }
               
               _notes = State(initialValue: t.notes ?? "")
               _categoryId = State(initialValue: t.category)
               _selectedAccountId = State(initialValue: t.account)
               _selectedTransferId = State(initialValue: t.transfer_id)
           } else {
               _date = State(initialValue: Date())
               _amountString = State(initialValue: "0.00")
               _isNegative = State(initialValue: true)
               _selectedPayeeId = State(initialValue: "")
               _customPayee = State(initialValue: "")
               _payeeMode = State(initialValue: .picker)
               _notes = State(initialValue: "")
               _categoryId = State(initialValue: nil)
               _selectedAccountId = State(initialValue: initialAccountId ?? "")
               _selectedTransferId = State(initialValue: nil)
           }
       }

       var body: some View {
           NavigationView {
               ZStack {
                   AppBackground()
                   if accounts.isEmpty && errorMessage == nil {
                       ProgressView().tint(AppTheme.accent)
                   } else {
                       formContent
                   }
               }
               .navigationTitle(transaction == nil ? "New Transaction" : "Edit Transaction")
               .navigationBarTitleDisplayMode(.inline)
               .toolbar {
                   ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                   ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).bold() }
               }
               .task { await load() }
               .alert("Error", isPresented: .constant(errorMessage != nil)) {
                   Button("OK") { errorMessage = nil }
               } message: { Text(errorMessage ?? "") }
           }
           .tint(AppTheme.accent)
       }
       
       private var formContent: some View {
           Form {
               Section("Account") {
                   Picker("Account", selection: $selectedAccountId) {
                       ForEach(accounts, id: \.id) { acc in
                           Text(acc.name + (acc.offbudget ? " (Off-Budget)" : "")).tag(acc.id)
                       }
                   }
               }
               .listRowBackground(Color.primary.opacity(0.05))
               
               Section("Details") {
                   DatePicker("Date", selection: $date, displayedComponents: .date)
                   
                   HStack {
                       TextField("Amount", text: $amountString)
                           .keyboardType(.decimalPad)
                       
                       Picker("Type", selection: $isNegative) {
                           Text("Expense").tag(true)
                           Text("Income").tag(false)
                       }
                       .pickerStyle(.segmented)
                       .frame(width: 150)
                   }
                   
                   Picker("Payee", selection: $payeeMode) {
                       Text("Choose").tag(PayeeInputMode.picker)
                       Text("Custom").tag(PayeeInputMode.custom)
                   }
                   .pickerStyle(.segmented)

                   if payeeMode == .picker {
                       Picker("Payee", selection: $selectedPayeeId) {
                           Text("None").tag("")
                           ForEach(payees, id: \.id) { payee in
                               Text(payee.name).tag(payee.id)
                           }
                       }
                       .onChange(of: selectedPayeeId) { oldValue, newValue in
                           selectedTransferId = payees.first(where: { $0.id == newValue })?.transfer_acct
                       }
                   } else {
                       TextField("Payee Name", text: $customPayee)
                   }
                   
                   Picker("Category", selection: $categoryId) {
                       Text("None").tag(String?.none)
                       ForEach(categoriesById.sorted { $0.value < $1.value }, id: \.key) { key, value in
                           Text(value).tag(String?.some(key))
                       }
                   }
                   
                   TextField("Notes", text: $notes)
               }
               .listRowBackground(Color.primary.opacity(0.05))
           }
           .scrollContentBackground(.hidden)
       }
       
       private func buildTransaction() -> Transaction {
           let units = parseAmountFromDisplay(amountString)
           let signed = isNegative ? -abs(units) : abs(units)
           
           let payeeId: String? = payeeMode == .picker ? (selectedPayeeId.isEmpty ? nil : selectedPayeeId) : nil
           let payeeName: String? = payeeMode == .custom ? (customPayee.isEmpty ? nil : customPayee) : nil
           
           return Transaction(
               id: transaction?.id,
               account: selectedAccountId,
               date: Self.formatDate(date),
               amount: signed,
               payee: payeeId,
               payee_name: payeeName,
               imported_payee: nil,
               category: categoryId,
               notes: notes.isEmpty ? nil : notes,
               imported_id: nil,
               transfer_id: selectedTransferId,
               cleared: false, subtransactions: nil
           )
       }

       private func save() {
           Task {
               do {
                   let built = buildTransaction()
                   if let _ = transaction {
                       try await repository.updateTransaction(built)
                   } else {
                       try await repository.createTransaction(built)
                   }
                   onSave(built)
                   dismiss()
               } catch {
                   await MainActor.run { errorMessage = error.localizedDescription }
               }
           }
       }

       private func load() async {
           do {
               let a = try await repository.fetchAccounts()
               let c = try await repository.fetchCategories()
               let p = try await repository.fetchPayees()
               await MainActor.run {
                   accounts = a.filter { !$0.closed }
                   categoriesById = Dictionary(uniqueKeysWithValues: c.map { ($0.id, $0.name) })
                   payees = p.sorted { $0.name < $1.name }
                   
                   if transaction == nil && selectedAccountId.isEmpty {
                       selectedAccountId = initialAccountId ?? accounts.first?.id ?? ""
                   }
               }
           } catch {
               await MainActor.run { errorMessage = error.localizedDescription }
           }
       }

       private static func parseDate(_ str: String) -> Date? {
           let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.date(from: str)
       }
       private static func formatDate(_ date: Date) -> String {
           let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.string(from: date)
       }
       private static func formatAmountForDisplay(_ amount: Int) -> String {
           String(format: "%.2f", Double(amount) / 100.0)
       }
       private func parseAmountFromDisplay(_ display: String) -> Int {
           Int((Double(display.replacingOccurrences(of: ",", with: ".")) ?? 0.0) * 100)
       }
   }
   ```

8. **Rewrite `BudgetView.swift`**:
   Load category group balances and implement tap-to-budget editing dialogs:
   ```swift
   import SwiftUI

   struct BudgetView: View {
       @EnvironmentObject private var appState: AppState
       @State private var monthDate: Date = Date()
       @State private var budget: BudgetMonth?
       @State private var monthGroups: [BudgetMonthCategoryGroup] = []
       @State private var expandedGroups: Set<String> = []
       @State private var errorMessage: String?
       
       @State private var editingCategory: BudgetMonthCategory?
       @State private var editBudgetString: String = ""

       private var repository: BudgetRepository {
           guard let repo = appState.repository else { fatalError("Repository unavailable") }
           return repo
       }

       var body: some View {
           ZStack {
               AppBackground()
               ScrollView {
                   VStack(spacing: 24) {
                       header()
                       
                       if monthGroups.isEmpty {
                           GlassCard {
                                Text("No budget categories found for this month.")
                                    .font(AppTheme.Fonts.body)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, minHeight: 100)
                            }
                       } else {
                           categoryGroups
                       }
                   }
                   .padding()
               }
           }
           .navigationTitle(monthTitle())
           .toolbar {
               ToolbarItem(placement: .navigationBarLeading) {
                   Button { moveMonth(-1) } label: { Image(systemName: "chevron.left") }
               }
               ToolbarItem(placement: .navigationBarTrailing) {
                   Button { moveMonth(+1) } label: { Image(systemName: "chevron.right") }
               }
           }
           .task { await loadAll() }
           .alert("Edit Budget Amount", isPresented: Binding(get: { editingCategory != nil }, set: { if !$0 { editingCategory = nil } })) {
               TextField("Amount", text: $editBudgetString)
                   .keyboardType(.decimalPad)
               Button("Cancel", role: .cancel) { editingCategory = nil }
               Button("Save") { saveBudgetEdit() }
           } message: {
               Text("Enter the monthly budgeted amount for \(editingCategory?.name ?? "")")
           }
           .alert("Error", isPresented: .constant(errorMessage != nil)) {
               Button("OK") { errorMessage = nil }
           } message: { Text(errorMessage ?? "") }
       }

       private func header() -> some View {
           GlassCard {
               VStack(alignment: .leading) {
                   Text("To Be Budgeted")
                       .font(AppTheme.Fonts.body)
                       .foregroundStyle(.secondary) 
                   Text(formatMoney(budget?.toBudget ?? 0))
                       .font(AppTheme.Fonts.title)
                       .foregroundColor( (budget?.toBudget ?? 0) < 0 ? AppTheme.destructive : .primary) 
                       .monospacedDigit()
                   
                   Divider().padding(.vertical, 8)
                   
                   HStack {
                       metric(label: "Available", value: budget?.incomeAvailable ?? 0)
                       Spacer()
                       metric(label: "Budgeted", value: budget?.totalBudgeted ?? 0)
                       Spacer()
                       metric(label: "Spent", value: budget?.totalSpent ?? 0)
                   }
               }
           }
       }
       
       private var categoryGroups: some View {
           ForEach(sortedGroups(), id: \.id) { group in
               VStack(alignment: .leading, spacing: 12) {
                   DisclosureGroup(isExpanded: Binding(
                       get: { expandedGroups.contains(group.id) },
                       set: { isExpanded in
                           if isExpanded { expandedGroups.insert(group.id) } else { expandedGroups.remove(group.id) }
                       }
                   )) {
                       ForEach(group.categories ?? [], id: \.id) { cat in
                           categoryRow(cat)
                               .padding(.top, 8)
                               .contentShape(Rectangle())
                               .onTapGesture {
                                   editingCategory = cat
                                   editBudgetString = String(format: "%.2f", Double(cat.budgeted ?? 0) / 100.0)
                               }
                       }
                   } label: {
                       HStack {
                           Text(group.name)
                               .font(AppTheme.Fonts.subtitle)
                               .foregroundColor(.primary) 
                           Spacer()
                           Text(formatMoney(group.balance ?? 0))
                               .font(AppTheme.Fonts.body.monospacedDigit())
                               .foregroundStyle(.secondary) 
                       }
                   }
                   .accentColor(.secondary) 
               }
               .padding()
               .background(Color.primary.opacity(0.05))
               .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
           }
       }

       private func categoryRow(_ category: BudgetMonthCategory) -> some View {
           VStack(alignment: .leading, spacing: 6) {
               HStack {
                   Text(category.name)
                       .font(AppTheme.Fonts.headline)
                       .foregroundColor(.primary) 
                   Spacer()
                   Text(formatMoney(category.balance ?? 0))
                       .font(AppTheme.Fonts.subheadline.monospacedDigit())
                       .foregroundColor( (category.balance ?? 0) < 0 ? AppTheme.destructive : .primary) 
               }
               
               let spent = abs(category.spent ?? 0)
               let budgeted = category.budgeted ?? 0
               let progress = budgeted > 0 ? min(Double(spent) / Double(budgeted), 1.0) : 0.0
               
               ProgressView(value: progress)
                   .tint(progress > 0.85 ? AppTheme.destructive : AppTheme.accent)
                   .padding(.top, 2)
               
               HStack {
                   Text("Spent: \(formatMoney(spent))")
                   Spacer()
                   Text("Budgeted: \(formatMoney(budgeted))")
               }
               .font(AppTheme.Fonts.footnote)
               .foregroundStyle(.secondary) 
           }
       }

       private func saveBudgetEdit() {
           guard let category = editingCategory else { return }
           let cents = Int((Double(editBudgetString.replacingOccurrences(of: ",", with: ".")) ?? 0.0) * 100)
           let monthKey = String(format: "%04d-%02d", Calendar.current.component(.year, from: monthDate), Calendar.current.component(.month, from: monthDate))
           
           Task {
               do {
                   try await repository.updateBudgetAmount(month: monthKey, categoryId: category.id, budgeted: cents)
                   await loadAll()
                   editingCategory = nil
               } catch {
                   await MainActor.run { errorMessage = error.localizedDescription }
               }
           }
       }

       private func metric(label: String, value: Int) -> some View {
           VStack(alignment: .leading) {
               Text(label)
                   .font(AppTheme.Fonts.footnote)
                   .foregroundStyle(.secondary) 
               Text(formatMoney(value))
                   .font(AppTheme.Fonts.subheadline.monospacedDigit())
                   .foregroundStyle(.primary) 
           }
       }
       
       private func sortedGroups() -> [BudgetMonthCategoryGroup] {
           let income = monthGroups.filter { $0.is_income == true }
           let spend = monthGroups.filter { $0.is_income != true }
           return spend + income
       }

       private func moveMonth(_ delta: Int) {
           monthDate = Calendar(identifier: .gregorian).date(
               byAdding: .month,
               value: delta,
               to: monthDate
           ) ?? monthDate
           Task { await loadAll() }
       }

       private func monthTitle() -> String {
           let f = DateFormatter(); f.dateFormat = "LLLL yyyy"; return f.string(from: monthDate)
       }

       private func formatMoney(_ amount: Int) -> String {
           return CurrencyFormatter.shared.format(amount, currencyCode: appState.currencyCode)
       }

       private func loadAll() async {
           do {
               let monthKey = String(format: "%04d-%02d", Calendar.current.component(.year, from: monthDate), Calendar.current.component(.month, from: monthDate))
               let bm = try await repository.fetchBudgetMonth(monthKey)
               let g = try await repository.fetchBudgetMonthCategoryGroups(monthKey)
               await MainActor.run {
                   budget = bm
                   monthGroups = g
               }
           } catch {
               await MainActor.run { errorMessage = error.localizedDescription }
           }
       }
   }
   ```

### Verification Plan
- Build and run the app.
- Create a new budget in Onboarding. Go to the Accounts tab and create a checking account.
- Add an expense transaction of $50.00 for Groceries. Verify the Dashboard metric displays Spent Today as $50.00.
- Go to the Budget tab. Expand Flexible Spending. Tap Groceries. Enter 100.00 and tap Save.
- Verify:
  - Budgeted amount for Groceries changes to $100.00.
  - Groceries Balance becomes positive $50.00 ($100 budgeted - $50 spent).
  - Header displays To Be Budgeted as -$100.00, Available as $0.00, Budgeted as $100.00, Spent as $50.00.
  - Enter a salary transaction of $1000.00 under Salary. Verify To Be Budgeted updates to positive $900.00.

---

## Prompt 5: Native SimpleFIN Bank Sync Integration (Phase 5)

### Objective
Integrate SimpleFIN bank sync capability. Implement a device Keychain store, claimed token authorization endpoint client, linking interfaces, and idempotent duplicate-filtering transaction sync coordinator.

### Files to Create / Modify
- **[NEW]** [SimpleFINCredentialStore.swift](file:///Users/roshanlodha/Documents/actual-budget-app/iOSApp/Data/Importing/SimpleFINCredentialStore.swift)
- **[NEW]** [SimpleFINClient.swift](file:///Users/roshanlodha/Documents/actual-budget-app/iOSApp/Data/Importing/SimpleFINClient.swift)
- **[NEW]** [SimpleFINImportCoordinator.swift](file:///Users/roshanlodha/Documents/actual-budget-app/iOSApp/Data/Importing/SimpleFINImportCoordinator.swift)
- **[NEW]** [BankConnectionsView.swift](file:///Users/roshanlodha/Documents/actual-budget-app/iOSApp/Features/BankConnections/BankConnectionsView.swift)
- **[MODIFY]** [SettingsView.swift](file:///Users/roshanlodha/Documents/actual-budget-app/iOSApp/Features/Settings/SettingsView.swift)

### Step-by-Step Instructions

1. **Create `SimpleFINCredentialStore.swift`**:
   Write the secure Keychain wrapper exactly:
   ```swift
   import Foundation
   import Security

   public final class SimpleFINCredentialStore {
       public static let shared = SimpleFINCredentialStore()
       private let service = "com.actual.accounts.simplefin"
       private let account = "access_url"
       
       public func saveAccessURL(_ url: URL) throws {
           let data = url.absoluteString.data(using: .utf8)!
           let query: [String: Any] = [
               kSecClass as String: kSecClassGenericPassword,
               kSecAttrService as String: service,
               kSecAttrAccount as String: account,
               kSecValueData as String: data,
               kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
           ]
           
           SecItemDelete(query as CFDictionary)
           let status = SecItemAdd(query as CFDictionary, nil)
           if status != errSecSuccess {
               throw NSError(domain: "KeychainError", code: Int(status), userInfo: nil)
           }
       }
       
       public func loadAccessURL() -> URL? {
           let query: [String: Any] = [
               kSecClass as String: kSecClassGenericPassword,
               kSecAttrService as String: service,
               kSecAttrAccount as String: account,
               kSecReturnData as String: true,
               kSecMatchLimit as String: kSecMatchLimitOne
           ]
           
           var dataTypeRef: AnyObject?
           let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)
           if status == errSecSuccess, let data = dataTypeRef as? Data, let str = String(data: data, encoding: .utf8) {
               return URL(string: str)
           }
           return nil
       }
       
       public func deleteAccessURL() {
           let query: [String: Any] = [
               kSecClass as String: kSecClassGenericPassword,
               kSecAttrService as String: service,
               kSecAttrAccount as String: account
           ]
           SecItemDelete(query as CFDictionary)
       }
   }
   ```

2. **Create `SimpleFINClient.swift`**:
   Implement standard token claim exchanges and institutional query endpoints:
   ```swift
   import Foundation

   public struct SimpleFINAccountSet: Decodable {
       public let errors: [String]?
       public let accounts: [SimpleFINAccount]
   }

   public struct SimpleFINAccount: Decodable {
       public let id: String
       public let name: String
       public let balance: String?
       public let transactions: [SimpleFINTx]?
   }

   public struct SimpleFINTx: Decodable {
       public let id: String
       public let posted: Double
       public let amount: String
       public let description: String
   }

   public final class SimpleFINClient {
       public init() {}
       
       public func claimAccessURL(from setupToken: String) async throws -> URL {
           guard let tokenData = Data(base64Encoded: setupToken.trimmingCharacters(in: .whitespacesAndNewlines)),
                 let claimString = String(data: tokenData, encoding: .utf8),
                 let claimURL = URL(string: claimString) else {
               throw NSError(domain: "SimpleFINClient", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid setup token"])
           }
           
           var request = URLRequest(url: claimURL)
           request.httpMethod = "POST"
           let (data, response) = try await URLSession.shared.data(for: request)
           guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
               throw NSError(domain: "SimpleFINClient", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to claim access token"])
           }
           
           guard let urlString = String(data: data, encoding: .utf8), let accessURL = URL(string: urlString) else {
               throw NSError(domain: "SimpleFINClient", code: 3, userInfo: [NSLocalizedDescriptionKey: "Invalid access URL returned"])
           }
           return accessURL
       }
       
       public func fetchAccountSet(accessURL: URL, balancesOnly: Bool = false, startDate: Date? = nil) async throws -> SimpleFINAccountSet {
           guard let user = accessURL.user, let password = accessURL.password else {
               throw NSError(domain: "SimpleFINClient", code: 4, userInfo: [NSLocalizedDescriptionKey: "Access URL missing credentials"])
           }
           
           var comps = URLComponents(url: accessURL.appendingPathComponent("accounts"), resolvingAgainstBaseURL: false)!
           var qItems = [URLQueryItem(name: "version", value: "2")]
           if balancesOnly {
               qItems.append(URLQueryItem(name: "balances-only", value: "1"))
           }
           if let startDate = startDate {
               let unixStr = String(Int(startDate.timeIntervalSince1970))
               qItems.append(URLQueryItem(name: "start-date", value: unixStr))
           }
           comps.queryItems = qItems
           
           var request = URLRequest(url: comps.url!)
           request.httpMethod = "GET"
           let authString = "\(user):\(password)"
           let authData = authString.data(using: .utf8)!.base64EncodedString()
           request.setValue("Basic \(authData)", forHTTPHeaderField: "Authorization")
           
           let (data, response) = try await URLSession.shared.data(for: request)
           guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
               throw NSError(domain: "SimpleFINClient", code: 5, userInfo: [NSLocalizedDescriptionKey: "Failed to fetch accounts data"])
           }
           
           return try JSONDecoder().decode(SimpleFINAccountSet.self, from: data)
       }
   }
   ```

3. **Create `SimpleFINImportCoordinator.swift`**:
   Write the transaction sync logic exactly:
   ```swift
   import Foundation

   public final class SimpleFINImportCoordinator {
       private let client = SimpleFINClient()
       private let repository: BudgetRepository
       
       public init(repository: BudgetRepository) {
           self.repository = repository
       }
       
       public func runSync() async throws {
           guard let accessURL = SimpleFINCredentialStore.shared.loadAccessURL() else {
               throw NSError(domain: "Sync", code: 401, userInfo: [NSLocalizedDescriptionKey: "SimpleFIN connection not configured"])
           }
           
           let links = try await repository.fetchAccountLinks()
           guard !links.isEmpty else { return }
           
           let startDate = Calendar.current.date(byAdding: .day, value: -90, to: Date())
           let accountSet = try await client.fetchAccountSet(accessURL: accessURL, balancesOnly: false, startDate: startDate)
           
           let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
           
           for remoteAccount in accountSet.accounts {
               guard let localAccountId = links[remoteAccount.id] else { continue }
               guard let transactions = remoteAccount.transactions else { continue }
               
               let existing = try await repository.fetchTransactions(accountId: localAccountId, since: nil)
               
               for tx in transactions {
                   let amountCents = Int(round((Double(tx.amount) ?? 0.0) * 100))
                   let dateStr = f.string(from: Date(timeIntervalSince1970: tx.posted))
                   let importedId = "simplefin:\(remoteAccount.id):\(tx.id)"
                   
                   if existing.contains(where: { $0.imported_id == importedId }) {
                       continue
                   }
                   
                   let transaction = Transaction(
                       id: UUID().uuidString,
                       account: localAccountId,
                       date: dateStr,
                       amount: amountCents,
                       payee: nil,
                       payee_name: tx.description,
                       imported_payee: tx.description,
                       category: nil,
                       notes: nil,
                       imported_id: importedId,
                       transfer_id: nil,
                       cleared: true,
                       subtransactions: nil
                   )
                   try await repository.createTransaction(transaction)
               }
           }
       }
   }
   ```

4. **Create `BankConnectionsView.swift`**:
   Write the account matching view:
   ```swift
   import SwiftUI

   struct BankConnectionsView: View {
       @EnvironmentObject private var appState: AppState
       @Environment(\.dismiss) private var dismiss
       @State private var tokenString: String = ""
       @State private var isLoading = false
       @State private var errorMessage: String?
       @State private var accountsToMap = [SimpleFINAccount]()
       @State private var localAccounts = [Account]()
       @State private var mappings = [String: String]()
       
       var body: some View {
           NavigationStack {
               ZStack {
                   AppBackground()
                   VStack {
                       if isLoading {
                           ProgressView().tint(AppTheme.accent)
                       } else if !accountsToMap.isEmpty {
                           Form {
                               Section("Map Discovered Accounts") {
                                   ForEach(accountsToMap, id: \.id) { remote in
                                       Picker(remote.name, selection: binding(for: remote.id)) {
                                           Text("Ignore").tag("")
                                           ForEach(localAccounts) { local in
                                               Text(local.name).tag(local.id)
                                           }
                                       }
                                   }
                               }
                               .listRowBackground(Color.primary.opacity(0.05))
                           }
                           .scrollContentBackground(.hidden)
                           
                           Button("Save Mappings") {
                               Task { await saveMappings() }
                           }
                           .buttonStyle(.borderedProminent)
                           .tint(AppTheme.accent)
                           .padding()
                       } else {
                           VStack(spacing: 20) {
                               Text("Link via SimpleFIN Bridge")
                                   .font(AppTheme.Fonts.headline)
                               TextField("Paste Setup Token", text: $tokenString)
                                   .textFieldStyle(.roundedBorder)
                                   .padding(.horizontal)
                               
                               Button("Fetch Remote Accounts") {
                                   Task { await claimToken() }
                               }
                               .buttonStyle(.borderedProminent)
                               .tint(AppTheme.accent)
                               .disabled(tokenString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                           }
                           .padding()
                       }
                   }
               }
               .navigationTitle("Bank Connections")
               .navigationBarTitleDisplayMode(.inline)
               .toolbar {
                   ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
               }
               .alert("Sync Info", isPresented: .constant(errorMessage != nil)) {
                   Button("OK") { errorMessage = nil }
               } message: { Text(errorMessage ?? "") }
               .task {
                   localAccounts = (try? await appState.repository?.fetchAccounts()) ?? []
               }
           }
       }
       
       private func binding(for id: String) -> Binding<String> {
           Binding(
               get: { mappings[id] ?? "" },
               set: { mappings[id] = $0 }
           )
       }
       
       private func claimToken() async {
           isLoading = true
           defer { isLoading = false }
           do {
               let client = SimpleFINClient()
               let accessURL = try await client.claimAccessURL(from: tokenString)
               try SimpleFINCredentialStore.shared.saveAccessURL(accessURL)
               let accountSet = try await client.fetchAccountSet(accessURL: accessURL, balancesOnly: true)
               accountsToMap = accountSet.accounts
           } catch {
               errorMessage = error.localizedDescription
           }
       }
       
       private func saveMappings() async {
           guard let repo = appState.repository else { return }
           do {
               for (remoteId, localId) in mappings {
                   if !localId.isEmpty, let remote = accountsToMap.first(where: { $0.id == remoteId }) {
                       try await repo.saveAccountLink(simplefinId: remoteId, name: remote.name, localId: localId)
                   }
               }
               dismiss()
           } catch {
               errorMessage = error.localizedDescription
           }
       }
   }
   ```

5. **Modify `SettingsView.swift`**:
   Add Bank Connections section:
   ```swift
   // Add this property to SettingsView
   @State private var showingBankLinks = false

   // Insert this section above the preferences section inside the body List
   Section("Bank Connections") {
       Button {
           showingBankLinks = true
       } label: {
           Label("Configure SimpleFIN Connections", systemImage: "link.badge.plus")
       }
   }
   .listRowBackground(Color.primary.opacity(0.05))

   // Append this sheet attachment below the scrollContentBackground view modifier
   .sheet(isPresented: $showingBankLinks) {
       BankConnectionsView()
   }
   ```

### Verification Plan
- Build and run the app. Go to Settings, verify the "Bank Connections" option is present.
- Tap it, paste a SimpleFIN token, link accounts, and confirm transaction importing executes cleanly.

---

## Prompt 6: Actual Budget Backup SQLite Importer (Phase 6 - Second to Last Step)

### Objective
Implement the ability to import data directly from an Actual Budget backup SQLite file (.sqlite). Provide a file picker, a schema mapping layer to read tables and views, a preview modal displaying statistics before import, and database transaction protection to execute the migration safely.

### Files to Create / Modify
- **[NEW]** [ActualBackupSQLiteImporter.swift](file:///Users/roshanlodha/Documents/actual-budget-app/iOSApp/Data/Migration/ActualBackupSQLiteImporter.swift)
- **[MODIFY]** [OnboardingView.swift](file:///Users/roshanlodha/Documents/actual-budget-app/iOSApp/Features/Onboarding/OnboardingView.swift)

### Step-by-Step Instructions

1. **Create `ActualBackupSQLiteImporter.swift`**:
   Create the folder `iOSApp/Data/Migration` and write the importer exactly:
   ```swift
   import Foundation

   public final class ActualBackupSQLiteImporter {
       public struct BackupPreview: Identifiable {
           public var id: String { "\(accountsCount)-\(transactionsCount)" }
           public let accountsCount: Int
           public let transactionsCount: Int
           public let categoriesCount: Int
       }
       
       private let backupPath: String
       
       public init(backupPath: String) {
           self.backupPath = backupPath
       }
       
       public func generatePreview() throws -> BackupPreview {
           let srcDB = try SQLiteDB(path: backupPath)
           
           let accs = try srcDB.query("SELECT COUNT(*) as c FROM accounts WHERE tombstone = 0;").first?["c"] as? Int ?? 0
           let txs = try srcDB.query("SELECT COUNT(*) as c FROM transactions WHERE tombstone = 0;").first?["c"] as? Int ?? 0
           let cats = try srcDB.query("SELECT COUNT(*) as c FROM categories WHERE tombstone = 0;").first?["c"] as? Int ?? 0
           
           return BackupPreview(accountsCount: accs, transactionsCount: txs, categoriesCount: cats)
       }
       
       public func executeImport(targetDB: SQLiteDB) throws {
           let srcDB = try SQLiteDB(path: backupPath)
           
           let groupRows = try srcDB.query("SELECT id, name, is_income FROM category_groups WHERE tombstone = 0;")
           let catRows = try srcDB.query("SELECT id, name, is_income, cat_group FROM categories WHERE tombstone = 0;")
           let accRows = try srcDB.query("SELECT id, name, offbudget, closed FROM accounts WHERE tombstone = 0;")
           let payeeRows = try srcDB.query("SELECT id, name, transfer_acct FROM payees WHERE tombstone = 0;")
           
           let txQuery = "SELECT id, account, date, amount, payee, category, notes, imported_id, transfer_id, cleared FROM transactions WHERE tombstone = 0;"
           let txRows = try srcDB.query(txQuery)
           let budgetRows = try srcDB.query("SELECT month, category, amount, carryover FROM zero_budgets;")
           
           try targetDB.transaction {
               try targetDB.execute("DELETE FROM transactions;")
               try targetDB.execute("DELETE FROM payees;")
               try targetDB.execute("DELETE FROM categories;")
               try targetDB.execute("DELETE FROM budget_category_groups;")
               try targetDB.execute("DELETE FROM accounts;")
               try targetDB.execute("DELETE FROM budget_category_values;")
               
               for g in groupRows {
                   try targetDB.execute("INSERT INTO budget_category_groups (id, name, is_income, hidden) VALUES (?, ?, ?, 0);",
                                        arguments: [g["id"]!, g["name"]!, g["is_income"]!])
               }
               
               for c in catRows {
                   try targetDB.execute("INSERT INTO categories (id, name, is_income, hidden, group_id) VALUES (?, ?, ?, 0, ?);",
                                        arguments: [c["id"]!, c["name"]!, c["is_income"]!, c["cat_group"] ?? NSNull()])
               }
               
               for a in accRows {
                   try targetDB.execute("INSERT INTO accounts (id, name, offbudget, closed) VALUES (?, ?, ?, ?);",
                                        arguments: [a["id"]!, a["name"]!, a["offbudget"]!, a["closed"]!])
               }
               
               for p in payeeRows {
                   try targetDB.execute("INSERT INTO payees (id, name, category_id, transfer_account_id) VALUES (?, ?, NULL, ?);",
                                        arguments: [p["id"]!, p["name"]!, p["transfer_acct"] ?? NSNull()])
               }
               
               for t in txRows {
                   var dateStr = t["date"] as? String ?? ""
                   if let dateInt = t["date"] as? Int {
                       let s = String(dateInt)
                       if s.count == 8 {
                           dateStr = "\(s.prefix(4))-\(s.dropFirst(4).prefix(2))-\(s.suffix(2))"
                       }
                   }
                   
                   try targetDB.execute("""
                       INSERT INTO transactions (id, account_id, date, amount, payee_id, payee_name, category_id, notes, imported_id, transfer_id, cleared, source)
                       VALUES (?, ?, ?, ?, ?, NULL, ?, ?, ?, ?, ?, 'backup-import');
                   """, arguments: [
                       t["id"]!,
                       t["account"]!,
                       dateStr,
                       t["amount"]!,
                       t["payee"] ?? NSNull(),
                       t["category"] ?? NSNull(),
                       t["notes"] ?? NSNull(),
                       t["imported_id"] ?? NSNull(),
                       t["transfer_id"] ?? NSNull(),
                       t["cleared"]!
                   ])
               }
               
               for b in budgetRows {
                   var monthStr = b["month"] as? String ?? ""
                   if let monthInt = b["month"] as? Int {
                       let s = String(monthInt)
                       if s.count == 6 {
                           monthStr = "\(s.prefix(4))-\(s.suffix(2))"
                       }
                   }
                   
                   try targetDB.execute("""
                       INSERT INTO budget_category_values (month, category_id, budgeted, carryover)
                       VALUES (?, ?, ?, ?);
                   """, arguments: [
                       monthStr,
                       b["category"]!,
                       b["amount"]!,
                       b["carryover"] ?? 1
                   ])
               }
           }
       }
   }
   ```

2. **Modify `OnboardingView.swift`**:
   Add import buttons and file selection triggers:
   ```swift
   // Add import SwiftUI, and also UniformTypeIdentifiers to get UTType:
   import UniformTypeIdentifiers

   // Add these state properties inside OnboardingView:
   @State private var showingFilePicker = false
   @State private var previewInfo: ActualBackupSQLiteImporter.BackupPreview?
   @State private var tempBackupURL: URL?

   // Add this button below the "Create New Budget" Button in body VStack:
   Button(action: { showingFilePicker = true }) {
       HStack {
           Image(systemName: "doc.badge.plus")
           Text("Import Actual Budget Backup")
       }
       .font(AppTheme.Fonts.headline)
       .frame(maxWidth: .infinity)
   }
   .buttonStyle(.bordered)
   .tint(AppTheme.accent)
   .padding(.horizontal)
   .fileImporter(
       isPresented: $showingFilePicker,
       allowedContentTypes: [UTType.data],
       allowsMultipleSelection: false
   ) { result in
       switch result {
       case .success(let urls):
           guard let selectedURL = urls.first else { return }
           importBackupFileSelected(selectedURL)
       case .failure(let error):
           errorMessage = error.localizedDescription
       }
   }

   // Append these sheet and handler methods to OnboardingView:
   // 1. Add sheet trigger at the very end of ZStack in body:
   .sheet(item: Binding(
       get: { previewInfo },
       set: { if $0 == nil { previewInfo = nil; tempBackupURL = nil } }
   )) { info in
       VStack(spacing: 20) {
           Text("Confirm Backup Import")
               .font(AppTheme.Fonts.title)
           
           VStack(alignment: .leading, spacing: 12) {
               Text("Discovered Data:")
               Text("• Accounts: \(info.accountsCount)")
               Text("• Categories: \(info.categoriesCount)")
               Text("• Transactions: \(info.transactionsCount)")
           }
           .font(AppTheme.Fonts.body)
           .padding()
           .background(Color.primary.opacity(0.05))
           .cornerRadius(10)
           
           Button("Confirm & Overwrite") {
               executeBackupImport()
           }
           .buttonStyle(.borderedProminent)
           .tint(AppTheme.accent)
           
           Button("Cancel") {
               previewInfo = nil
           }
           .foregroundColor(.secondary)
       }
       .padding()
       .presentationDetents([.height(300)])
   }

   // 2. Add helper functions at the end of the Struct:
   private func importBackupFileSelected(_ url: URL) {
       guard url.startAccessingSecurityScopedResource() else { return }
       defer { url.stopAccessingSecurityScopedResource() }
       
       let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sqlite")
       do {
           try FileManager.default.copyItem(at: url, to: tempURL)
           let importer = ActualBackupSQLiteImporter(backupPath: tempURL.path)
           let preview = try importer.generatePreview()
           self.tempBackupURL = tempURL
           self.previewInfo = preview
       } catch {
           errorMessage = error.localizedDescription
       }
   }
   
   private func executeBackupImport() {
       guard let tempURL = tempBackupURL else { return }
       let budgetId = UUID().uuidString
       
       do {
           try LocalBudgetFileManager.shared.createBudgetDirectory(for: budgetId)
           let localDBURL = LocalBudgetFileManager.shared.sqliteFileURL(for: budgetId)
           
           // Copy the database in place, then execute migrations on it
           try FileManager.default.copyItem(at: tempURL, to: localDBURL)
           
           let db = try SQLiteDB(path: localDBURL.path)
           let importer = ActualBackupSQLiteImporter(backupPath: localDBURL.path)
           try importer.executeImport(targetDB: db)
           
           let metaURL = LocalBudgetFileManager.shared.metadataFileURL(for: budgetId)
           let metadata: [String: Any] = [
               "displayName": "Imported Budget",
               "createdAt": ISO8601DateFormatter().string(from: Date()),
               "lastModifiedAt": ISO8601DateFormatter().string(from: Date())
           ]
           if let data = try? JSONSerialization.data(withJSONObject: metadata) {
               try? data.write(to: metaURL)
           }
           
           appState.selectedBudgetDisplayName = "Imported Budget"
           appState.selectedBudgetID = budgetId
           
           try? FileManager.default.removeItem(at: tempURL)
           previewInfo = nil
       } catch {
           errorMessage = error.localizedDescription
       }
   }
   ```

### Verification Plan
- Build and run the app.
- Enter Onboarding, click "Import Actual Budget Backup".
- Pick an Actual Budget backup SQLite file. Verify the preview modal lists statistics of the accounts, categories, and transactions correctly.
- Tap "Confirm & Overwrite". Verify it imports data successfully and transitions into the Dashboard showing the transactions correctly.

## Prompt 7: iCloud Sync Adapter (Phase 7 - Last Step)

### Objective
Enable iCloud capabilities. Implement ubiquitous database copy synchronizations using coordinated reads and writes (`NSFileCoordinator`).

### Files to Create / Modify
- **[MODIFY]** [project.yml](file:///Users/roshanlodha/Documents/actual-budget-app/iOSApp/project.yml)
- **[MODIFY]** [ActualAccounts.entitlements](file:///Users/roshanlodha/Documents/actual-budget-app/iOSApp/Resources/ActualAccounts.entitlements)
- **[NEW]** [ICloudBudgetSyncAdapter.swift](file:///Users/roshanlodha/Documents/actual-budget-app/iOSApp/Data/Sync/ICloudBudgetSyncAdapter.swift)
- **[MODIFY]** [LocalBudgetRepository.swift](file:///Users/roshanlodha/Documents/actual-budget-app/iOSApp/Data/Repository/LocalBudgetRepository.swift)
- **[MODIFY]** [SettingsView.swift](file:///Users/roshanlodha/Documents/actual-budget-app/iOSApp/Features/Settings/SettingsView.swift)
- **[MODIFY]** [ActualAccountsApp.swift](file:///Users/roshanlodha/Documents/actual-budget-app/iOSApp/App/ActualAccountsApp.swift)

### Step-by-Step Instructions

1. **Configure iCloud Entitlements**:
   Ensure `CODE_SIGN_ENTITLEMENTS` in `project.yml` points to the entitlements file path:
   ```yaml
   CODE_SIGN_ENTITLEMENTS: Resources/ActualAccounts.entitlements
   ```
   Overwrite `iOSApp/Resources/ActualAccounts.entitlements` with the complete XML including App Group and iCloud configuration:
   ```xml
   <?xml version="1.0" encoding="UTF-8"?>
   <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
   <plist version="1.0">
   <dict>
       <key>com.apple.security.application-groups</key>
       <array>
           <string>group.com.actual.accounts</string>
       </array>
       <key>com.apple.developer.icloud-container-identifiers</key>
       <array>
           <string>iCloud.com.actual.accounts</string>
       </array>
       <key>com.apple.developer.icloud-services</key>
       <array>
           <string>CloudDocuments</string>
       </array>
       <key>com.apple.developer.ubiquity-container-identifiers</key>
       <array>
           <string>iCloud.com.actual.accounts</string>
       </array>
       <key>com.apple.developer.ubiquity-kvstore-identifier</key>
       <string>$(TeamIdentifierPrefix)com.actual.accounts</string>
   </dict>
   </plist>
   ```

2. **Create `ICloudBudgetSyncAdapter.swift`**:
   Create the directory `iOSApp/Data/Sync` and write the coordinated file adapter exactly:
   ```swift
   import Foundation

   public final class ICloudBudgetSyncAdapter {
       public static let shared = ICloudBudgetSyncAdapter()
       
       private let fileManager = FileManager.default
       private let coordinator = NSFileCoordinator()
       
       public var iCloudContainerURL: URL? {
           return fileManager.url(forUbiquityContainerIdentifier: nil)?.appendingPathComponent("Documents")
       }
       
       public func isICloudEnabled() -> Bool {
           return iCloudContainerURL != nil
       }
       
       public func syncBudget(budgetId: String) {
           guard let iCloudURL = iCloudContainerURL else { return }
           
           let localDB = LocalBudgetFileManager.shared.sqliteFileURL(for: budgetId)
           let localMeta = LocalBudgetFileManager.shared.metadataFileURL(for: budgetId)
           
           let icloudDir = iCloudURL.appendingPathComponent("Budgets").appendingPathComponent(budgetId)
           let icloudDB = icloudDir.appendingPathComponent("budget.sqlite")
           let icloudMeta = icloudDir.appendingPathComponent("budget-metadata.json")
           
           try? fileManager.createDirectory(at: icloudDir, withIntermediateDirectories: true, attributes: nil)
           
           let localMetaObj = loadMetadata(url: localMeta) ?? [:]
           let icloudMetaObj = loadMetadata(url: icloudMeta) ?? [:]
           
           let localTime = localMetaObj["lastModifiedAt"] as? String ?? ""
           let icloudTime = icloudMetaObj["lastModifiedAt"] as? String ?? ""
           
           if icloudTime > localTime {
               coordinator.coordinate(readingItemAt: icloudDB, options: [], writingItemAt: localDB, options: .forReplacing) { readURL, writeURL in
                   do {
                       if fileManager.fileExists(atPath: writeURL.path) {
                           try fileManager.removeItem(at: writeURL)
                       }
                       try fileManager.copyItem(at: readURL, to: writeURL)
                       
                       if fileManager.fileExists(atPath: localMeta.path) {
                           try fileManager.removeItem(at: localMeta)
                       }
                       try fileManager.copyItem(at: icloudMeta, to: localMeta)
                       
                       DispatchQueue.main.async {
                           NotificationCenter.default.post(name: NSNotification.Name("BudgetUpdatedFromICloud"), object: nil)
                       }
                   } catch {
                       print("iCloud download failed: \(error)")
                   }
               }
           } else if localTime > icloudTime {
               coordinator.coordinate(readingItemAt: localDB, options: [], writingItemAt: icloudDB, options: .forReplacing) { readURL, writeURL in
                   do {
                       if fileManager.fileExists(atPath: writeURL.path) {
                           try fileManager.removeItem(at: writeURL)
                       }
                       try fileManager.copyItem(at: readURL, to: writeURL)
                       
                       if fileManager.fileExists(atPath: icloudMeta.path) {
                           try fileManager.removeItem(at: icloudMeta)
                       }
                       try fileManager.copyItem(at: localMeta, to: icloudMeta)
                   } catch {
                       print("iCloud upload failed: \(error)")
                   }
               }
           }
       }
       
       private func loadMetadata(url: URL) -> [String: Any]? {
           guard let data = try? Data(contentsOf: url) else { return nil }
           return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
       }
   }
   ```

3. **Update Write Queries in `LocalBudgetRepository.swift`**:
   Add mutation notification calls to update database metadata, perform WAL checkpointing, and run iCloud sync automatically on changes:
   ```swift
   // Add this helper method inside LocalBudgetRepository:
   private func notifyMutation() {
       guard let budgetId = UserDefaults.standard.string(forKey: "SelectedBudgetID") else { return }
       
       // Force a WAL checkpoint to truncate changes into the main .sqlite file prior to iCloud copy
       try? db.execute("PRAGMA wal_checkpoint(TRUNCATE);")
       
       let metaURL = LocalBudgetFileManager.shared.metadataFileURL(for: budgetId)
       
       var meta = (try? JSONSerialization.jsonObject(with: Data(contentsOf: metaURL)) as? [String: Any]) ?? [:]
       meta["lastModifiedAt"] = ISO8601DateFormatter().string(from: Date())
       
       if let data = try? JSONSerialization.data(withJSONObject: meta) {
           try? data.write(to: metaURL)
       }
       
       ICloudBudgetSyncAdapter.shared.syncBudget(budgetId: budgetId)
   }

   // Call notifyMutation() at the end of these functions inside LocalBudgetRepository:
   // createAccount, updateAccount, deleteAccount, createCategory, createPayee, createTransaction, updateTransaction, deleteTransaction, and updateBudgetAmount.
   ```

4. **Modify `SettingsView.swift`**:
   Append iCloud sync option block to the Settings List:
   ```swift
   Section("iCloud Synchronization") {
       HStack {
           Text("iCloud Status")
           Spacer()
           Text(ICloudBudgetSyncAdapter.shared.isICloudEnabled() ? "Enabled" : "Disabled")
               .foregroundColor(.secondary)
       }
       Button("Force iCloud Sync Trigger") {
           if let activeId = appState.selectedBudgetID {
               ICloudBudgetSyncAdapter.shared.syncBudget(budgetId: activeId)
           }
       }
       .disabled(!ICloudBudgetSyncAdapter.shared.isICloudEnabled())
   }
   .listRowBackground(Color.primary.opacity(0.05))
   ```

5. **Modify `ActualAccountsApp.swift`**:
   Trigger sync on active scene transitions and observe iCloud notifications to refresh local connections:
   ```swift
   import SwiftUI

   @main
   struct ActualAccountsApp: App {
       @StateObject private var appState = AppState()
       @Environment(\.scenePhase) private var scenePhase

       var body: some Scene {
           WindowGroup {
               RootView()
                   .environmentObject(appState)
                   .onChange(of: scenePhase) { oldValue, newValue in
                       if newValue == .active, let activeId = appState.selectedBudgetID {
                           ICloudBudgetSyncAdapter.shared.syncBudget(budgetId: activeId)
                       }
                   }
                   .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("BudgetUpdatedFromICloud"))) { _ in
                       let temp = appState.selectedBudgetID
                       appState.selectedBudgetID = nil
                       appState.selectedBudgetID = temp
                   }
           }
       }
   }
   ```

### Verification Plan
- Build and run the app. Go to Settings, verify "iCloud Status" displays "Enabled" (if signed in on simulator/device).
- Mutate transactions or values, verify that modifications copy to the iCloud ubiquity containers correctly.