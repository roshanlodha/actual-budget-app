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
                    AppLogger.shared.log("Error initializing budget database: \(error.localizedDescription)", level: .error)
                    print("Error initializing budget database: \(error)")
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
    
    @Published var currencyCode: String = "USD"
    
    
    @Published var onboardingState: OnboardingState = .noBudgetSelected
    @Published var repository: BudgetRepository?
    
    

    
    public init() {
        self.currencyCode = "USD"

        self.selectedBudgetDisplayName = UserDefaults.standard.string(forKey: Keys.selectedBudgetDisplayName) ?? ""
        
        if let budgetId = UserDefaults.standard.string(forKey: Keys.selectedBudgetID) {
            DispatchQueue.main.async {
                self.selectedBudgetID = budgetId
            }
        } else {
            self.onboardingState = .noBudgetSelected
        }
    }
    
    public func setupBudget(id: String, displayName: String, categoryGroups: [CategoryGroupSetup]) throws {
        try LocalBudgetFileManager.shared.createBudgetDirectory(for: id)
        
        let metaURL = LocalBudgetFileManager.shared.metadataFileURL(for: id)
        let metadata: [String: Any] = [
            "displayName": displayName,
            "createdAt": ISO8601DateFormatter().string(from: Date()),
            "lastModifiedAt": ISO8601DateFormatter().string(from: Date())
        ]
        let data = try JSONSerialization.data(withJSONObject: metadata)
        try data.write(to: metaURL)
        
        let path = LocalBudgetFileManager.shared.sqliteFileURL(for: id).path
        let db = try SQLiteDB(path: path)
        
        // This will create the schema.
        let repository = LocalBudgetRepository(db: db)
        
        // Clear seeded defaults
        try db.execute("DELETE FROM categories;")
        try db.execute("DELETE FROM budget_category_groups;")
        
        // Insert custom category groups and categories
        try db.transaction {
            for group in categoryGroups {
                let gId = group.id
                try db.execute("INSERT INTO budget_category_groups (id, name, is_income, hidden) VALUES (?, ?, ?, 0);",
                               arguments: [gId, group.name, group.isIncome])
                
                for cat in group.categories {
                    try db.execute("INSERT INTO categories (id, name, is_income, hidden, group_id, color, icon) VALUES (?, ?, ?, 0, ?, ?, ?);",
                                   arguments: [cat.id, cat.name, cat.isIncome, gId, cat.color ?? NSNull(), cat.icon ?? NSNull()])
                }
            }
        }
        
        // Update AppState
        DispatchQueue.main.async {
            self.selectedBudgetDisplayName = displayName
            self.selectedBudgetID = id
            self.repository = repository
            self.onboardingState = .ready
        }
    }
    
    public func resetBudget() {
        if let currentID = selectedBudgetID {
            try? LocalBudgetFileManager.shared.deleteBudget(budgetId: currentID)
        }
        
        DispatchQueue.main.async {
            self.selectedBudgetID = nil
            self.selectedBudgetDisplayName = ""
            self.repository = nil
            self.onboardingState = .noBudgetSelected
        }
    }
    
    private enum Keys {
        static let selectedBudgetID = "SelectedBudgetID"
        static let selectedBudgetDisplayName = "SelectedBudgetDisplayName"
        static let currencyCode = "ActualCurrencyCode"

    }
}

public struct CategorySetup: Identifiable, Hashable {
    public let id: String
    public var name: String
    public var isIncome: Bool
    public var color: String?
    public var icon: String?
    
    public init(id: String = UUID().uuidString, name: String, isIncome: Bool, color: String? = nil, icon: String? = nil) {
        self.id = id
        self.name = name
        self.isIncome = isIncome
        self.color = color
        self.icon = icon
    }
}

public struct CategoryGroupSetup: Identifiable, Hashable {
    public let id: String
    public var name: String
    public var isIncome: Bool
    public var categories: [CategorySetup]
    
    public init(id: String = UUID().uuidString, name: String, isIncome: Bool, categories: [CategorySetup] = []) {
        self.id = id
        self.name = name
        self.isIncome = isIncome
        self.categories = categories
    }
}
