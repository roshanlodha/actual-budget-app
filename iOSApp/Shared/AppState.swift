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
