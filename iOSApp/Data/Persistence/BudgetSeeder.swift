import Foundation

public struct BudgetSeeder {
    public static func seedStarterData(db: SQLiteDB) throws {
        let categoriesToSeed: [(groupName: String, isIncome: Bool, subCategories: [(name: String, color: String, icon: String)])] = [
            ("Income", true, [
                ("Salary", "#4ECCA3", "briefcase.fill"),
                ("Other Income", "#00ADB5", "dollarsign.circle.fill")
            ]),
            ("Fixed Expenses", false, [
                ("Rent/Mortgage", "#FF6B6B", "house.fill"),
                ("Utilities", "#FF9233", "bolt.fill"),
                ("Internet/Phone", "#FFC93C", "wifi"),
                ("Insurance", "#8D93AB", "shield.fill")
            ]),
            ("Flexible Spending", false, [
                ("Groceries", "#FF8AAE", "cart.fill"),
                ("Dining Out", "#FF9233", "fork.knife"),
                ("Entertainment", "#A66CFF", "popcorn.fill"),
                ("Shopping", "#FF8AAE", "bag.fill"),
                ("Travel", "#39A2DB", "airplane")
            ]),
            ("Savings & Investments", false, [
                ("Emergency Fund", "#5A20CB", "banknote.fill"),
                ("Retirement", "#5A20CB", "banknote.fill")
            ])
        ]
        
        try db.transaction {
            for group in categoriesToSeed {
                let groupId = UUID().uuidString
                try db.execute("INSERT INTO budget_category_groups (id, name, is_income, hidden) VALUES (?, ?, ?, 0);",
                               arguments: [groupId, group.groupName, group.isIncome])
                
                for subCat in group.subCategories {
                    let subId = UUID().uuidString
                    try db.execute("INSERT INTO categories (id, name, is_income, hidden, group_id, color, icon) VALUES (?, ?, ?, 0, ?, ?, ?);",
                                   arguments: [subId, subCat.name, group.isIncome, groupId, subCat.color, subCat.icon])
                }
            }
        }
    }
}