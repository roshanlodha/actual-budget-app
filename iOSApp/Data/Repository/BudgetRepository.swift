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
