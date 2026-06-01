import Foundation

public final class ActualBudgetImporter {
    public static func importBudget(from actualSqliteURL: URL, to appState: AppState) throws {
        // 1. Resolve security scoped resource
        let access = actualSqliteURL.startAccessingSecurityScopedResource()
        defer {
            if access {
                actualSqliteURL.stopAccessingSecurityScopedResource()
            }
        }
        
        // 2. Determine Budget Display Name
        var displayName = "Actual Budget"
        let parentURL = actualSqliteURL.deletingLastPathComponent()
        let metadataURL = parentURL.appendingPathComponent("metadata.json")
        
        if FileManager.default.fileExists(atPath: metadataURL.path),
           let data = try? Data(contentsOf: metadataURL),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let budgetName = json["budgetName"] as? String {
            displayName = budgetName
        } else {
            let folderName = parentURL.lastPathComponent
            if folderName != "/" && !folderName.isEmpty && folderName != "Documents" && folderName != "Downloads" {
                let cleaned = folderName
                    .replacingOccurrences(of: "-", with: " ")
                    .replacingOccurrences(of: "_", with: " ")
                displayName = cleaned.capitalized
            }
        }
        
        // 3. Initialize Source SQLite Database
        let srcDB = try SQLiteDB(path: actualSqliteURL.path)
        
        // Quick verification: check if transactions table exists
        let tablesCheck = try srcDB.query("SELECT name FROM sqlite_master WHERE type='table' AND name='transactions';")
        guard !tablesCheck.isEmpty else {
            throw NSError(domain: "ActualBudgetImporter", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid Actual database: 'transactions' table not found."])
        }
        
        // 4. Create local budget entry
        let budgetId = UUID().uuidString
        try LocalBudgetFileManager.shared.createBudgetDirectory(for: budgetId)
        
        // Write metadata
        let metaURL = LocalBudgetFileManager.shared.metadataFileURL(for: budgetId)
        let metadata: [String: Any] = [
            "displayName": displayName,
            "createdAt": ISO8601DateFormatter().string(from: Date()),
            "lastModifiedAt": ISO8601DateFormatter().string(from: Date())
        ]
        let metaDataBytes = try JSONSerialization.data(withJSONObject: metadata)
        try metaDataBytes.write(to: metaURL)
        
        // Initialize destination database and build schema
        let destPath = LocalBudgetFileManager.shared.sqliteFileURL(for: budgetId).path
        let destDB = try SQLiteDB(path: destPath)
        let _ = LocalBudgetRepository(db: destDB) // trigger schema creation
        
        // Clear seeded defaults
        try destDB.execute("DELETE FROM categories;")
        try destDB.execute("DELETE FROM budget_category_groups;")
        
        // 5. Read from Source & Write to Destination
        try destDB.transaction {
            // A. Category Groups
            let groups = try srcDB.query("SELECT id, name, is_income, hidden FROM category_groups WHERE tombstone = 0;")
            for g in groups {
                let id = g["id"] as? String ?? UUID().uuidString
                let name = g["name"] as? String ?? "Group"
                let isIncome = g["is_income"] as? Int ?? 0
                let hidden = g["hidden"] as? Int ?? 0
                try destDB.execute("INSERT INTO budget_category_groups (id, name, is_income, hidden) VALUES (?, ?, ?, ?);",
                                   arguments: [id, name, isIncome, hidden])
            }
            
            // B. Categories
            let categories = try srcDB.query("SELECT id, name, is_income, cat_group, hidden FROM categories WHERE tombstone = 0;")
            for c in categories {
                let id = c["id"] as? String ?? UUID().uuidString
                let name = c["name"] as? String ?? "Category"
                let isIncome = c["is_income"] as? Int ?? 0
                let groupId: Any = c["cat_group"] as? String ?? NSNull()
                let hidden = c["hidden"] as? Int ?? 0
                
                let style = colorAndIcon(for: name, isIncome: isIncome != 0)
                try destDB.execute("INSERT INTO categories (id, name, is_income, hidden, group_id, color, icon) VALUES (?, ?, ?, ?, ?, ?, ?);",
                                   arguments: [id, name, isIncome, hidden, groupId, style.color, style.icon])
            }
            
            // C. Accounts
            let accounts = try srcDB.query("SELECT id, name, offbudget, closed FROM accounts WHERE tombstone = 0;")
            for a in accounts {
                let id = a["id"] as? String ?? UUID().uuidString
                let name = a["name"] as? String ?? "Account"
                let offbudget = a["offbudget"] as? Int ?? 0
                let closed = a["closed"] as? Int ?? 0
                try destDB.execute("INSERT INTO accounts (id, name, offbudget, closed) VALUES (?, ?, ?, ?);",
                                   arguments: [id, name, offbudget, closed])
            }
            
            // D. Payees
            let payees = try srcDB.query("SELECT id, name, category, transfer_acct FROM payees WHERE tombstone = 0;")
            var payeeMap = [String: String]() // to look up payee names for transactions
            for p in payees {
                let id = p["id"] as? String ?? UUID().uuidString
                let name = p["name"] as? String ?? "Payee"
                let categoryId: Any = p["category"] as? String ?? NSNull()
                let transferAcctId: Any = p["transfer_acct"] as? String ?? NSNull()
                payeeMap[id] = name
                try destDB.execute("INSERT INTO payees (id, name, category_id, transfer_account_id) VALUES (?, ?, ?, ?);",
                                   arguments: [id, name, categoryId, transferAcctId])
            }
            
            // E. Transactions
            let txs = try srcDB.query("SELECT id, acct, category, amount, description, notes, date, financial_id, transferred_id, cleared FROM transactions WHERE tombstone = 0;")
            for t in txs {
                let id = t["id"] as? String ?? UUID().uuidString
                let accountId = t["acct"] as? String ?? ""
                let dateInt = t["date"] as? Int ?? 0
                
                // Convert YYYYMMDD to YYYY-MM-DD
                let dateStr: String
                if dateInt > 0 {
                    let year = dateInt / 10000
                    let month = (dateInt % 10000) / 100
                    let day = dateInt % 100
                    dateStr = String(format: "%04d-%02d-%02d", year, month, day)
                } else {
                    dateStr = "2000-01-01"
                }
                
                let amount = t["amount"] as? Int ?? 0
                let desc = t["description"] as? String ?? ""
                
                var payeeId: Any = NSNull()
                var payeeName: Any = NSNull()
                if !desc.isEmpty {
                    if let name = payeeMap[desc] {
                        payeeId = desc
                        payeeName = name
                    } else {
                        payeeName = desc
                    }
                }
                
                let categoryId: Any = t["category"] as? String ?? NSNull()
                let notes: Any = t["notes"] as? String ?? NSNull()
                let importedId: Any = t["financial_id"] as? String ?? NSNull()
                let transferId: Any = t["transferred_id"] as? String ?? NSNull()
                let cleared = t["cleared"] as? Int ?? 0
                
                try destDB.execute("""
                    INSERT INTO transactions (id, account_id, date, amount, payee_id, payee_name, category_id, notes, imported_id, transfer_id, cleared, source)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'imported');
                """, arguments: [
                    id, accountId, dateStr, amount, payeeId, payeeName, categoryId, notes, importedId, transferId, cleared
                ])
            }
            
            // F. Budget Values (zero_budgets)
            let zeroBudgets = try srcDB.query("SELECT month, category, amount, carryover FROM zero_budgets;")
            for zb in zeroBudgets {
                let monthInt = zb["month"] as? Int ?? 0
                let categoryId = zb["category"] as? String ?? ""
                let amount = zb["amount"] as? Int ?? 0
                let carryover = zb["carryover"] as? Int ?? 1
                
                guard !categoryId.isEmpty else { continue }
                
                // Convert YYYYMM to YYYY-MM
                let monthStr: String
                if monthInt > 0 {
                    let year = monthInt / 100
                    let month = monthInt % 100
                    monthStr = String(format: "%04d-%02d", year, month)
                } else {
                    monthStr = "2000-01"
                }
                
                try destDB.execute("""
                    INSERT INTO budget_category_values (month, category_id, budgeted, carryover)
                    VALUES (?, ?, ?, ?)
                    ON CONFLICT(month, category_id) DO UPDATE SET budgeted = excluded.budgeted, carryover = excluded.carryover;
                """, arguments: [monthStr, categoryId, amount, carryover])
            }
        }
        
        // 6. Set Active Budget in AppState
        let repo = LocalBudgetRepository(db: destDB)
        DispatchQueue.main.async {
            appState.selectedBudgetDisplayName = displayName
            appState.selectedBudgetID = budgetId
            appState.repository = repo
            appState.onboardingState = .ready
        }
    }
    
    private static func colorAndIcon(for name: String, isIncome: Bool) -> (color: String, icon: String) {
        if isIncome {
            return ("#4ECCA3", "briefcase.fill") // green, briefcase
        }
        
        let lower = name.lowercased()
        
        if lower.contains("rent") || lower.contains("mortgage") || lower.contains("housing") {
            return ("#FF6B6B", "house.fill")
        } else if lower.contains("groceries") || lower.contains("supermarket") {
            return ("#FF8AAE", "cart.fill")
        } else if lower.contains("eat") || lower.contains("restaurant") || lower.contains("food") || lower.contains("dining") || lower.contains("cafe") || lower.contains("coffee") {
            return ("#FF9233", "fork.knife")
        } else if lower.contains("utilities") || lower.contains("internet") || lower.contains("electricity") || lower.contains("gas") || lower.contains("water") || lower.contains("power") {
            return ("#FFC93C", "bolt.fill")
        } else if lower.contains("insurance") || lower.contains("medical") || lower.contains("health") || lower.contains("doctor") {
            return ("#00ADB5", "heart.fill")
        } else if lower.contains("travel") || lower.contains("flight") || lower.contains("hotel") || lower.contains("vacation") {
            return ("#39A2DB", "airplane")
        } else if lower.contains("car") || lower.contains("gasoline") || lower.contains("transport") || lower.contains("uber") || lower.contains("lyft") || lower.contains("taxi") {
            return ("#39A2DB", "car.fill")
        } else if lower.contains("shop") || lower.contains("amazon") || lower.contains("clothing") || lower.contains("clothes") {
            return ("#E056A0", "bag.fill")
        } else if lower.contains("saving") || lower.contains("invest") || lower.contains("retirement") {
            return ("#5A20CB", "banknote.fill")
        } else if lower.contains("tax") {
            return ("#8D93AB", "percent")
        } else {
            let colors = ["#FF6B6B", "#FF9233", "#FFC93C", "#4ECCA3", "#00ADB5", "#39A2DB", "#5A20CB", "#A66CFF", "#FF8AAE", "#8D93AB"]
            let index = abs(name.hashValue) % colors.count
            return (colors[index], "tag.fill")
        }
    }
}
