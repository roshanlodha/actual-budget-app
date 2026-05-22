import Foundation

public struct APIResponse<T: Decodable>: Decodable {
    public let data: T
}

public struct GeneralResponseMessage: Decodable {
    public let message: String
}

public struct Account: Identifiable, Codable, Equatable {
    public let id: String
    public var name: String
    public var offbudget: Bool
    public var closed: Bool

    public init(id: String, name: String, offbudget: Bool, closed: Bool) {
        self.id = id
        self.name = name
        self.offbudget = offbudget
        self.closed = closed
    }
}

public struct AccountsListResponse: Decodable {
    public let data: [Account]
}

public struct Category: Identifiable, Codable, Equatable {
    public let id: String
    public let name: String
    public let is_income: Bool?
    public let hidden: Bool?
    public let group_id: String?

    public init(id: String, name: String, is_income: Bool?, hidden: Bool?, group_id: String?) {
        self.id = id
        self.name = name
        self.is_income = is_income
        self.hidden = hidden
        self.group_id = group_id
    }
}

public struct CategoriesListResponse: Decodable {
    public let data: [Category]
}

public struct Payee: Identifiable, Codable, Equatable {
    public let id: String
    public let name: String
    public let category: String?
    public let transfer_acct: String?

    public init(id: String, name: String, category: String?, transfer_acct: String?) {
        self.id = id
        self.name = name
        self.category = category
        self.transfer_acct = transfer_acct
    }
}

public struct PayeesListResponse: Decodable {
    public let data: [Payee]
}

public struct Transaction: Identifiable, Codable, Equatable {
    public let id: String?
    public let account: String
    public let date: String
    public let amount: Int?
    public let payee: String?
    public let payee_name: String?
    public let imported_payee: String?
    public let category: String?
    public let notes: String?
    public let imported_id: String?
    public let transfer_id: String?
    public let cleared: Bool?
    public let subtransactions: [Transaction]?

    public init(
        id: String? = nil,
        account: String,
        date: String,
        amount: Int?,
        payee: String?,
        payee_name: String?,
        imported_payee: String? = nil,
        category: String?,
        notes: String?,
        imported_id: String?,
        transfer_id: String?,
        cleared: Bool?,
        subtransactions: [Transaction]? = nil
    ) {
        self.id = id
        self.account = account
        self.date = date
        self.amount = amount
        self.payee = payee
        self.payee_name = payee_name
        self.imported_payee = imported_payee
        self.category = category
        self.notes = notes
        self.imported_id = imported_id
        self.transfer_id = transfer_id
        self.cleared = cleared
        self.subtransactions = subtransactions
    }
}

public struct TransactionsListResponse: Decodable {
    public let data: [Transaction]
}

public struct BudgetMonth: Decodable {
    public let month: String
    public let incomeAvailable: Int
    public let lastMonthOverspent: Int
    public let forNextMonth: Int
    public let totalBudgeted: Int
    public let toBudget: Int
    public let fromLastMonth: Int
    public let totalIncome: Int
    public let totalSpent: Int
    public let totalBalance: Int

    public init(
        month: String,
        incomeAvailable: Int,
        lastMonthOverspent: Int,
        forNextMonth: Int,
        totalBudgeted: Int,
        toBudget: Int,
        fromLastMonth: Int,
        totalIncome: Int,
        totalSpent: Int,
        totalBalance: Int
    ) {
        self.month = month
        self.incomeAvailable = incomeAvailable
        self.lastMonthOverspent = lastMonthOverspent
        self.forNextMonth = forNextMonth
        self.totalBudgeted = totalBudgeted
        self.toBudget = toBudget
        self.fromLastMonth = fromLastMonth
        self.totalIncome = totalIncome
        self.totalSpent = totalSpent
        self.totalBalance = totalBalance
    }
}

public struct BudgetMonthCategory: Identifiable, Decodable, Equatable {
    public let id: String
    public let name: String
    public let is_income: Bool?
    public let hidden: Bool?
    public let group_id: String?
    public let budgeted: Int?
    public let spent: Int?
    public let balance: Int?
    public let carryover: Bool?

    public init(
        id: String,
        name: String,
        is_income: Bool?,
        hidden: Bool?,
        group_id: String?,
        budgeted: Int?,
        spent: Int?,
        balance: Int?,
        carryover: Bool?
    ) {
        self.id = id
        self.name = name
        self.is_income = is_income
        self.hidden = hidden
        self.group_id = group_id
        self.budgeted = budgeted
        self.spent = spent
        self.balance = balance
        self.carryover = carryover
    }
}

public struct BudgetMonthCategoryGroup: Identifiable, Decodable, Equatable {
    public let id: String
    public let name: String
    public let is_income: Bool?
    public let hidden: Bool?
    public let categories: [BudgetMonthCategory]?
    public let budgeted: Int?
    public let spent: Int?
    public let balance: Int?

    public init(
        id: String,
        name: String,
        is_income: Bool?,
        hidden: Bool?,
        categories: [BudgetMonthCategory]?,
        budgeted: Int?,
        spent: Int?,
        balance: Int?
    ) {
        self.id = id
        self.name = name
        self.is_income = is_income
        self.hidden = hidden
        self.categories = categories
        self.budgeted = budgeted
        self.spent = spent
        self.balance = balance
    }
}

public struct BudgetMonthCategoriesResponse: Decodable { public let data: [BudgetMonthCategory] }
public struct BudgetMonthCategoryGroupsResponse: Decodable { public let data: [BudgetMonthCategoryGroup] }