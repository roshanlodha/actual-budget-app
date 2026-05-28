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
            group_id TEXT,
            color TEXT,
            icon TEXT
        );
        """)
        
        try? db.execute("ALTER TABLE categories ADD COLUMN color TEXT;")
        try? db.execute("ALTER TABLE categories ADD COLUMN icon TEXT;")
        
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
    
    public func fetchCategoryGroups() async throws -> [CategoryGroup] {
        let rows = try db.query("SELECT id, name, is_income, hidden FROM budget_category_groups WHERE hidden = 0;")
        return rows.map { row in
            CategoryGroup(
                id: row["id"] as? String ?? "",
                name: row["name"] as? String ?? "",
                is_income: (row["is_income"] as? Int ?? 0) != 0,
                hidden: (row["hidden"] as? Int ?? 0) != 0
            )
        }
    }
    
    // MARK: - Categories
    public func fetchCategories() async throws -> [Category] {
        let rows = try db.query("SELECT id, name, is_income, hidden, group_id, color, icon FROM categories;")
        return rows.map { row in
            Category(
                id: row["id"] as? String ?? "",
                name: row["name"] as? String ?? "",
                is_income: (row["is_income"] as? Int ?? 0) != 0,
                hidden: (row["hidden"] as? Int ?? 0) != 0,
                group_id: row["group_id"] as? String,
                color: row["color"] as? String,
                icon: row["icon"] as? String
            )
        }
    }
    
    public func fetchCategoriesByGroupId(_ groupId: String) async throws -> [Category] {
        let rows = try db.query("SELECT id, name, is_income, hidden, group_id, color, icon FROM categories WHERE group_id = ?;", arguments: [groupId])
        return rows.map { row in
            Category(
                id: row["id"] as? String ?? "",
                name: row["name"] as? String ?? "",
                is_income: (row["is_income"] as? Int ?? 0) != 0,
                hidden: (row["hidden"] as? Int ?? 0) != 0,
                group_id: row["group_id"] as? String,
                color: row["color"] as? String,
                icon: row["icon"] as? String
            )
        }
    }
    
    public func createCategory(name: String, isIncome: Bool, groupId: String, color: String?, icon: String?) async throws -> String {
        let id = UUID().uuidString
        try db.execute("INSERT INTO categories (id, name, is_income, hidden, group_id, color, icon) VALUES (?, ?, ?, 0, ?, ?, ?);",
                       arguments: [id, name, isIncome ? 1 : 0, groupId, color ?? NSNull(), icon ?? NSNull()])
        return id
    }
    
    public func updateCategory(_ category: Category) async throws {
        try db.execute("""
            UPDATE categories 
            SET name = ?, is_income = ?, hidden = ?, group_id = ?, color = ?, icon = ?
            WHERE id = ?;
        """, arguments: [
            category.name,
            (category.is_income ?? false) ? 1 : 0,
            (category.hidden ?? false) ? 1 : 0,
            category.group_id ?? NSNull(),
            category.color ?? NSNull(),
            category.icon ?? NSNull(),
            category.id
        ])
    }
    
    public func deleteCategory(id: String) async throws {
        try db.transaction {
            try db.execute("DELETE FROM budget_category_values WHERE category_id = ?;", arguments: [id])
            try db.execute("UPDATE transactions SET category_id = NULL WHERE category_id = ?;", arguments: [id])
            try db.execute("DELETE FROM categories WHERE id = ?;", arguments: [id])
        }
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
        let catRows = try db.query("SELECT id, name, is_income, hidden, group_id, color, icon FROM categories WHERE hidden = 0;")
        
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
                let cColor = cRow["color"] as? String
                let cIcon = cRow["icon"] as? String
                
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
                    carryover: (budgetsByCat[cId]?.1 ?? 1) != 0,
                    color: cColor,
                    icon: cIcon
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
