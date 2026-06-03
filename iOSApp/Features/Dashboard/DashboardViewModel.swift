import SwiftUI
import Combine

public struct MonthlyExpenseBarData: Identifiable, Equatable {
    public let id = UUID()
    public let monthLabel: String
    public let monthIndex: Int
    public let category: String
    public let amount: Double
}

public struct CategoryExpense: Identifiable, Equatable {
    public let id = UUID()
    public let category: String
    public let amount: Double
}

public struct CalendarMonthData: Identifiable {
    public let id = UUID()
    public let monthName: String
    public let monthStart: Date
    public let days: [CalendarDayData]
    public let totalIncome: Int
    public let totalExpense: Int
}

public struct CalendarDayData: Identifiable {
    public let id = UUID()
    public let date: Date
    public let dateString: String
    public let dayNumber: Int
    public let isPadding: Bool
    public let income: Int
    public let expense: Int
    public let transactions: [Transaction]
}

@MainActor
public final class DashboardViewModel: ObservableObject {
    @Published public var isLoading = false
    @Published public var errorMessage: String? = nil
    
    // YTD Stats
    @Published public var ytdExpenseTotal: Int = 0
    @Published public var ytdIncomeTotal: Int = 0
    @Published public var monthlyExpenseAverage: Int = 0
    @Published public var monthlyIncomeAverage: Int = 0
    @Published public var dateRangeLabel: String = ""
    @Published public var cashFlowNet: Int = 0
    
    // Per-month breakdown for YTD chart
    @Published public var perMonthExpenseBreakdown: [MonthlyExpenseBarData] = []
    @Published public var categoryColorMap: [String: Color] = [:]
    
    // Current month breakdown
    @Published public var currentMonthCategoryBreakdown: [CategoryExpense] = []
    
    // Calendar Data
    @Published public var calendarMonths: [CalendarMonthData] = []
    
    // Repository objects mapped for the View
    @Published public var accounts: [Account] = []
    @Published public var categoriesById: [String: Category] = [:]
    @Published public var payeesById: [String: Payee] = [:]
    
    // Selected day details for sheet
    @Published public var selectedDateTransactions: [Transaction] = []
    @Published public var selectedDateLabel: String = ""
    @Published public var showDetailSheet = false
    
    private var repository: BudgetRepository?
    private var cancellables = Set<AnyCancellable>()
    
    public init() {
        NotificationCenter.default.publisher(for: NSNotification.Name("IgnoredCategoriesChanged"))
            .sink { [weak self] _ in
                Task {
                    await self?.loadData()
                }
            }
            .store(in: &cancellables)
    }
    
    public func configure(repository: BudgetRepository) {
        self.repository = repository
    }
    
    public func loadData() async {
        guard let repository = repository else { return }
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        
        do {
            let fetchedAccounts = try await repository.fetchAccounts()
            let fetchedCategories = try await repository.fetchCategories()
            let fetchedPayees = try await repository.fetchPayees()
            
            let onBudgetAccountIds = Set(fetchedAccounts.filter { !$0.offbudget }.map { $0.id })
            let mappedCategoriesById = Dictionary(uniqueKeysWithValues: fetchedCategories.map { ($0.id, $0) })
            let mappedPayeesById = Dictionary(uniqueKeysWithValues: fetchedPayees.map { ($0.id, $0) })
            let incomeCategoryIds = Set(fetchedCategories.filter { $0.is_income == true }.map { $0.id })
            
            // Generate category colors map
            let palette: [Color] = [.teal, .orange, .red, .blue, .purple, .gray, .pink, .yellow, .indigo, .mint]
            var tempColorMap: [String: Color] = [:]
            for (index, cat) in fetchedCategories.enumerated() {
                tempColorMap[cat.name] = palette[index % palette.count]
            }
            tempColorMap["Uncategorized"] = .gray
            
            // Calculate query range
            let calendar = Calendar.current
            let now = Date()
            let currentYear = calendar.component(.year, from: now)
            
            guard let jan1 = calendar.date(from: DateComponents(year: currentYear, month: 1, day: 1)) else {
                throw NSError(domain: "DashboardViewModel", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to construct Jan 1 date"])
            }
            
            guard let threeMonthsAgo = calendar.date(byAdding: .month, value: -2, to: now),
                  let startOfThreeMonthsAgo = calendar.date(from: calendar.dateComponents([.year, .month], from: threeMonthsAgo)) else {
                throw NSError(domain: "DashboardViewModel", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to construct calendar start date"])
            }
            
            let queryStartDate = min(jan1, startOfThreeMonthsAgo)
            let queryStartDateString = formatDatePOSIX(queryStartDate)
            
            let allTransactions = try await repository.fetchAllTransactions(since: queryStartDateString)
            
            // Helpers
            func isTransfer(_ tx: Transaction) -> Bool {
                if tx.transfer_id != nil { return true }
                if let payeeId = tx.payee, let p = mappedPayeesById[payeeId], p.transfer_acct != nil { return true }
                return false
            }
            
            func isIncomeTransaction(_ tx: Transaction) -> Bool {
                if let catId = tx.category, let cat = mappedCategoriesById[catId] {
                    return cat.is_income == true
                }
                return (tx.amount ?? 0) > 0
            }
            
            // Filter transactions for calculations:
            // 1. Must be on-budget account
            // 2. Must not be a transfer
            // 3. Category must not be ignored
            let ignoredCategoryIDs = Set(UserDefaults.standard.stringArray(forKey: "IgnoredCategoryIDs") ?? [])
            let filteredTransactions = allTransactions.filter { tx in
                onBudgetAccountIds.contains(tx.account) &&
                !isTransfer(tx) &&
                !(tx.category.map { ignoredCategoryIDs.contains($0) } ?? false)
            }
            
            // Date formatting strings
            let todayPOSIX = formatDatePOSIX(now)
            let jan1POSIX = formatDatePOSIX(jan1)
            
            // YTD calculations (Jan 1 of current year through today)
            let ytdTransactions = filteredTransactions.filter { tx in
                tx.date >= jan1POSIX && tx.date <= todayPOSIX
            }
            
            var expenseSum = 0
            var incomeSum = 0
            
            for tx in ytdTransactions {
                let amt = tx.amount ?? 0
                if isIncomeTransaction(tx) {
                    incomeSum += amt
                } else {
                    expenseSum += amt
                }
            }
            expenseSum = abs(expenseSum)
            
            // Format YTD Range label
            let rangeFormatter = DateFormatter()
            rangeFormatter.dateFormat = "MMM yyyy"
            rangeFormatter.locale = Locale(identifier: "en_US")
            let startLabel = rangeFormatter.string(from: jan1)
            let endLabel = rangeFormatter.string(from: now)
            let dynamicRangeLabel = "\(startLabel) – \(endLabel)"
            
            // Per-month expense breakdown grouped by month (current year to date) and category name
            let shortMonthNames = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
            let currentMonthInt = calendar.component(.month, from: now)
            var monthlyBreakdown: [MonthlyExpenseBarData] = []
            
            for monthIdx in 1...currentMonthInt {
                let monthPrefix = String(format: "%04d-%02d", currentYear, monthIdx)
                let monthTxs = filteredTransactions.filter { $0.date.hasPrefix(monthPrefix) }
                
                var categoryTotals: [String: Int] = [:]
                for tx in monthTxs {
                    if !isIncomeTransaction(tx) {
                        let catName = mappedCategoriesById[tx.category ?? ""]?.name ?? "Uncategorized"
                        categoryTotals[catName, default: 0] += tx.amount ?? 0
                    }
                }
                
                if categoryTotals.isEmpty {
                    monthlyBreakdown.append(MonthlyExpenseBarData(
                        monthLabel: shortMonthNames[monthIdx - 1],
                        monthIndex: monthIdx,
                        category: "",
                        amount: 0.0
                    ))
                } else {
                    for (catName, total) in categoryTotals {
                        monthlyBreakdown.append(MonthlyExpenseBarData(
                            monthLabel: shortMonthNames[monthIdx - 1],
                            monthIndex: monthIdx,
                            category: catName,
                            amount: total < 0 ? Double(abs(total)) / 100.0 : 0.0
                        ))
                    }
                }
            }
            
            // Current month category breakdown for mini chart (sorted descending)
            let currentMonthKey = String(format: "%04d-%02d", currentYear, currentMonthInt)
            let currentMonthTxs = filteredTransactions.filter { $0.date.hasPrefix(currentMonthKey) }
            var currentMonthCategoryTotals: [String: Int] = [:]
            
            for tx in currentMonthTxs {
                if !isIncomeTransaction(tx) {
                    let catName = mappedCategoriesById[tx.category ?? ""]?.name ?? "Uncategorized"
                    currentMonthCategoryTotals[catName, default: 0] += tx.amount ?? 0
                }
            }
            
            let sortedBreakdown = currentMonthCategoryTotals
                .map { CategoryExpense(category: $0.key, amount: $0.value < 0 ? Double(abs($0.value)) / 100.0 : 0.0) }
                .filter { $0.amount > 0 }
                .sorted { $0.amount > $1.amount }
            
            // Calendar calculations (current month only)
            var generatedMonths: [CalendarMonthData] = []
            for offset in 0...0 {
                guard let monthDate = calendar.date(byAdding: .month, value: offset, to: now) else { continue }
                
                let comps = calendar.dateComponents([.year, .month], from: monthDate)
                guard let monthStart = calendar.date(from: comps) else { continue }
                guard let range = calendar.range(of: .day, in: .month, for: monthStart) else { continue }
                let numberOfDays = range.count
                
                let firstWeekday = calendar.component(.weekday, from: monthStart)
                let leadingPadding = firstWeekday - 1
                
                var days: [CalendarDayData] = []
                
                // Leading padding
                for _ in 0..<leadingPadding {
                    days.append(CalendarDayData(
                        date: monthStart,
                        dateString: "",
                        dayNumber: 0,
                        isPadding: true,
                        income: 0,
                        expense: 0,
                        transactions: []
                    ))
                }
                
                var totalMonthIncome = 0
                var totalMonthExpense = 0
                
                // Days of month
                for dayNum in 1...numberOfDays {
                    var dayComps = comps
                    dayComps.day = dayNum
                    guard let dayDate = calendar.date(from: dayComps) else { continue }
                    
                    let dateStr = String(format: "%04d-%02d-%02d", dayComps.year ?? currentYear, dayComps.month ?? 1, dayNum)
                    let dayTxs = filteredTransactions.filter { $0.date == dateStr }
                    
                    var dayIncome = 0
                    var dayExpense = 0
                    
                    for tx in dayTxs {
                        let amt = tx.amount ?? 0
                        if isIncomeTransaction(tx) {
                            dayIncome += amt
                        } else {
                            dayExpense += amt
                        }
                    }
                    
                    let finalDayExpense = dayExpense < 0 ? abs(dayExpense) : 0
                    let finalDayIncome = dayIncome + (dayExpense > 0 ? dayExpense : 0)
                    
                    totalMonthIncome += finalDayIncome
                    totalMonthExpense += finalDayExpense
                    
                    days.append(CalendarDayData(
                        date: dayDate,
                        dateString: dateStr,
                        dayNumber: dayNum,
                        isPadding: false,
                        income: finalDayIncome,
                        expense: finalDayExpense,
                        transactions: dayTxs
                    ))
                }
                
                // Trailing padding to complete the last week row
                let totalCells = days.count
                let trailingPadding = (7 - (totalCells % 7)) % 7
                for _ in 0..<trailingPadding {
                    days.append(CalendarDayData(
                        date: monthStart,
                        dateString: "",
                        dayNumber: 0,
                        isPadding: true,
                        income: 0,
                        expense: 0,
                        transactions: []
                    ))
                }
                
                let monthTitleFormatter = DateFormatter()
                monthTitleFormatter.dateFormat = "MMMM yyyy"
                let monthName = monthTitleFormatter.string(from: monthStart)
                
                generatedMonths.append(CalendarMonthData(
                    monthName: monthName,
                    monthStart: monthStart,
                    days: days,
                    totalIncome: totalMonthIncome,
                    totalExpense: totalMonthExpense
                ))
            }
            
            // Update UI state
            let elapsedMonths = max(1, currentMonthInt)
            self.accounts = fetchedAccounts
            self.categoriesById = mappedCategoriesById
            self.payeesById = mappedPayeesById
            
            self.ytdExpenseTotal = expenseSum
            self.ytdIncomeTotal = incomeSum
            self.monthlyExpenseAverage = expenseSum / elapsedMonths
            self.monthlyIncomeAverage = incomeSum / elapsedMonths
            self.dateRangeLabel = dynamicRangeLabel
            self.cashFlowNet = incomeSum - expenseSum
            
            self.categoryColorMap = tempColorMap
            self.perMonthExpenseBreakdown = monthlyBreakdown
            self.currentMonthCategoryBreakdown = sortedBreakdown
            self.calendarMonths = generatedMonths
            
        } catch {
            self.errorMessage = error.localizedDescription
        }
        
        self.isLoading = false
    }
    
    public func selectDate(_ day: CalendarDayData) {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        
        self.selectedDateLabel = formatter.string(from: day.date)
        self.selectedDateTransactions = day.transactions
        self.showDetailSheet = true
    }
    
    private func formatDatePOSIX(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: date)
    }
}
