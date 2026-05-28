import Foundation

public struct BudgetSeeder {
    public static func seedStarterData(db: SQLiteDB) throws {
        let categoriesToSeed: [(groupName: String, isIncome: Bool, subCategories: [(name: String, color: String, icon: String)])] = [
            ("Income", true, [
                ("Business", "#4ECCA3", "briefcase.fill")
            ]),
            ("Fixed Expenses", false, [
                ("Rent", "#FF6B6B", "house.fill"),
                ("Utilities, Internet, Insurance", "#FFC93C", "bolt.fill"),
                ("Taxes", "#8D93AB", "percent")
            ]),
            ("Flexible Spending", false, [
                ("Groceries", "#FF8AAE", "cart.fill"),
                ("Eating Out", "#FF9233", "fork.knife"),
                ("Shopping", "#E056A0", "bag.fill"),
                ("Travel", "#39A2DB", "airplane"),
                ("Clothes & Hair", "#A66CFF", "tshirt.fill"),
                ("Transportation and Gas", "#39A2DB", "car.fill"),
                ("Other", "#8D93AB", "tag.fill")
            ]),
            ("Savings & Investments", false, [
                ("Savings", "#5A20CB", "banknote.fill")
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