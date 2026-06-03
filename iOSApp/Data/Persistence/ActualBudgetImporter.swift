import Foundation
import SwiftUI

public struct ParsedCategory: Identifiable, Hashable {
    public var id: String { name + "||" + groupName }
    public let name: String
    public let groupName: String
    
    public init(name: String, groupName: String) {
        self.name = name
        self.groupName = groupName
    }
}

public final class ActualBudgetImporter {
    
    public static func parseCategoriesFromCSV(text: String) -> [ParsedCategory] {
        let rows = CSVParser.parse(text: text, delimiter: ",")
        guard !rows.isEmpty else { return [] }
        
        let headers = rows[0]
        var groupIdx = -1
        var categoryIdx = -1
        
        for (i, h) in headers.enumerated() {
            let clean = h.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if clean.contains("group") {
                groupIdx = i
            } else if clean.contains("category") {
                categoryIdx = i
            }
        }
        
        // Fallbacks
        if groupIdx == -1 {
            // Check if there is a Category_Group or Category Group column
            for (i, h) in headers.enumerated() {
                let clean = h.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if clean == "category_group" || clean == "category group" {
                    groupIdx = i
                }
            }
        }
        
        guard categoryIdx != -1 else { return [] }
        
        var categorySet = Set<ParsedCategory>()
        for row in rows.dropFirst() {
            guard categoryIdx < row.count else { continue }
            let catName = row[categoryIdx].trimmingCharacters(in: .whitespacesAndNewlines)
            let grpName = groupIdx != -1 && groupIdx < row.count ? row[groupIdx].trimmingCharacters(in: .whitespacesAndNewlines) : "Flexible Spending"
            
            if !catName.isEmpty {
                categorySet.insert(ParsedCategory(name: catName, groupName: grpName.isEmpty ? "Flexible Spending" : grpName))
            }
        }
        
        return Array(categorySet).sorted {
            if $0.groupName == $1.groupName {
                return $0.name < $1.name
            }
            return $0.groupName < $1.groupName
        }
    }
    
    public static func importBudgetFromCSV(
        text: String,
        displayName: String,
        selectedCategories: Set<String>,
        to appState: AppState
    ) throws {
        let rows = CSVParser.parse(text: text, delimiter: ",")
        guard !rows.isEmpty else {
            throw NSError(domain: "ActualBudgetImporter", code: 1, userInfo: [NSLocalizedDescriptionKey: "CSV file is empty."])
        }
        
        let headers = rows[0]
        var accountIdx = -1
        var dateIdx = -1
        var payeeIdx = -1
        var notesIdx = -1
        var groupIdx = -1
        var categoryIdx = -1
        var amountIdx = -1
        
        for (i, h) in headers.enumerated() {
            let clean = h.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if clean == "account" {
                accountIdx = i
            } else if clean == "date" {
                dateIdx = i
            } else if clean == "payee" {
                payeeIdx = i
            } else if clean == "notes" || clean == "memo" {
                notesIdx = i
            } else if clean.contains("group") {
                groupIdx = i
            } else if clean.contains("category") {
                categoryIdx = i
            } else if clean == "amount" {
                amountIdx = i
            }
        }
        
        // Fallbacks
        if groupIdx == -1 {
            for (i, h) in headers.enumerated() {
                let clean = h.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if clean == "category_group" || clean == "category group" {
                    groupIdx = i
                }
            }
        }
        
        guard accountIdx != -1, dateIdx != -1, payeeIdx != -1, categoryIdx != -1, amountIdx != -1 else {
            throw NSError(domain: "ActualBudgetImporter", code: 2, userInfo: [NSLocalizedDescriptionKey: "Missing required CSV columns (Account, Date, Payee, Category, Amount)."])
        }
        
        // Create local budget entry
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
        try destDB.execute("DELETE FROM accounts;")
        try destDB.execute("DELETE FROM payees;")
        try destDB.execute("DELETE FROM transactions;")
        
        // Read from Source & Write to Destination
        try destDB.transaction {
            var groupMap = [String: String]() // groupName -> ID
            var categoryMap = [String: String]() // name||groupName -> ID
            var accountMap = [String: String]() // accountName -> ID
            var payeeMap = [String: String]() // payeeName -> ID
            
            for row in rows.dropFirst() {
                guard accountIdx < row.count, dateIdx < row.count, payeeIdx < row.count,
                      categoryIdx < row.count, amountIdx < row.count else { continue }
                
                let accountName = row[accountIdx].trimmingCharacters(in: .whitespacesAndNewlines)
                let rawDateStr = row[dateIdx].trimmingCharacters(in: .whitespacesAndNewlines)
                let payeeName = row[payeeIdx].trimmingCharacters(in: .whitespacesAndNewlines)
                let noteStr = notesIdx != -1 && notesIdx < row.count ? row[notesIdx].trimmingCharacters(in: .whitespacesAndNewlines) : ""
                let groupName = groupIdx != -1 && groupIdx < row.count ? row[groupIdx].trimmingCharacters(in: .whitespacesAndNewlines) : "Flexible Spending"
                let categoryName = row[categoryIdx].trimmingCharacters(in: .whitespacesAndNewlines)
                let amountStr = row[amountIdx].trimmingCharacters(in: .whitespacesAndNewlines)
                
                guard !accountName.isEmpty, !rawDateStr.isEmpty else { continue }
                
                // A. Accounts
                let accountId: String
                if let id = accountMap[accountName] {
                    accountId = id
                } else {
                    let id = UUID().uuidString
                    accountId = id
                    accountMap[accountName] = id
                    try destDB.execute("INSERT INTO accounts (id, name, offbudget, closed) VALUES (?, ?, 0, 0);",
                                       arguments: [id, accountName])
                    
                    // Create transfer payee for this account
                    let transferPayeeId = UUID().uuidString
                    try destDB.execute("INSERT INTO payees (id, name, category_id, transfer_account_id) VALUES (?, ?, NULL, ?);",
                                       arguments: [transferPayeeId, "Transfer: \(accountName)", id])
                }
                
                // B. Category Groups & Categories
                let finalGroupName = groupName.isEmpty ? "Flexible Spending" : groupName
                let categoryKey = categoryName + "||" + finalGroupName
                let isSelectedCategory = selectedCategories.contains(categoryKey)
                
                var categoryId: Any = NSNull()
                if isSelectedCategory && !categoryName.isEmpty {
                    // Group
                    let groupId: String
                    if let id = groupMap[finalGroupName] {
                        groupId = id
                    } else {
                        let id = UUID().uuidString
                        groupId = id
                        groupMap[finalGroupName] = id
                        let isIncome = finalGroupName.localizedCaseInsensitiveCompare("income") == .orderedSame
                        try destDB.execute("INSERT INTO budget_category_groups (id, name, is_income, hidden) VALUES (?, ?, ?, 0);",
                                           arguments: [id, finalGroupName, isIncome ? 1 : 0])
                    }
                    
                    // Category
                    if let id = categoryMap[categoryKey] {
                        categoryId = id
                    } else {
                        let id = UUID().uuidString
                        categoryId = id
                        categoryMap[categoryKey] = id
                        let isIncome = finalGroupName.localizedCaseInsensitiveCompare("income") == .orderedSame
                        let style = colorAndIcon(for: categoryName, isIncome: isIncome)
                        try destDB.execute("INSERT INTO categories (id, name, is_income, hidden, group_id, color, icon) VALUES (?, ?, ?, 0, ?, ?, ?);",
                                           arguments: [id, categoryName, isIncome ? 1 : 0, groupId, style.color, style.icon])
                    }
                }
                
                // C. Payees
                var payeeId: Any = NSNull()
                var payeeInsertName: Any = NSNull()
                if !payeeName.isEmpty {
                    if let id = payeeMap[payeeName] {
                        payeeId = id
                    } else {
                        let id = UUID().uuidString
                        payeeId = id
                        payeeMap[payeeName] = id
                        try destDB.execute("INSERT INTO payees (id, name, category_id, transfer_account_id) VALUES (?, ?, NULL, NULL);",
                                           arguments: [id, payeeName])
                    }
                    payeeInsertName = payeeName
                }
                
                // D. Amount Parsing
                let doubleAmount = parseDouble(amountStr)
                let amountCents = Int(round(doubleAmount * 100))
                
                // E. Date Parsing
                let dateStr = parseDateString(rawDateStr)
                
                // F. Notes
                let finalNotes: Any = noteStr.isEmpty ? NSNull() : noteStr
                
                // G. Insert Transaction
                let txId = UUID().uuidString
                try destDB.execute("""
                    INSERT INTO transactions (id, account_id, date, amount, payee_id, payee_name, category_id, notes, imported_id, transfer_id, cleared, source)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, NULL, 1, 'imported');
                """, arguments: [
                    txId, accountId, dateStr, amountCents, payeeId, payeeInsertName, categoryId, finalNotes, "csv_import_\(UUID().uuidString.prefix(8))"
                ])
            }
        }
        
        // Set Active Budget in AppState
        let repo = LocalBudgetRepository(db: destDB)
        DispatchQueue.main.async {
            appState.selectedBudgetDisplayName = displayName
            appState.selectedBudgetID = budgetId
            appState.repository = repo
            appState.onboardingState = .ready
        }
    }
    
    private static func parseDateString(_ str: String) -> String {
        let cleaned = str.trimmingCharacters(in: .whitespacesAndNewlines)
        let formats = [
            "M/d/yy",
            "MM/dd/yy",
            "M/d/yyyy",
            "MM/dd/yyyy",
            "yyyy-MM-dd",
            "yyyy/MM/dd"
        ]
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        for format in formats {
            f.dateFormat = format
            if let d = f.date(from: cleaned) {
                let outF = DateFormatter()
                outF.dateFormat = "yyyy-MM-dd"
                return outF.string(from: d)
            }
        }
        return "2000-01-01"
    }
    
    private static func parseDouble(_ val: String) -> Double {
        let cleaned = val.replacingOccurrences(of: "$", with: "")
                         .replacingOccurrences(of: ",", with: "")
                         .trimmingCharacters(in: .whitespacesAndNewlines)
        return Double(cleaned) ?? 0.0
    }
    
    private static func colorAndIcon(for name: String, isIncome: Bool) -> (color: String, icon: String) {
        if isIncome {
            return ("#4ECCA3", "briefcase.fill")
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
