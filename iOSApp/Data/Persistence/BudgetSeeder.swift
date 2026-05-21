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