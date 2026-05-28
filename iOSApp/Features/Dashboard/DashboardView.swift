import SwiftUI
import WidgetKit

struct DashboardView: View {
    @EnvironmentObject private var appState: AppState
    @State private var accounts: [Account] = []
    @State private var categoriesById: [String: String] = [:]
    @State private var payeesById: [String: Payee] = [:]
    @State private var transactions: [Transaction] = []
    @State private var errorMessage: String?
    @State private var activeSheet: SheetType?

    var onBudgetAccounts: [Account] { accounts.filter { !$0.offbudget } }
    private var recentFive: [Transaction] { recentNonTransferOnBudget().prefix(5).map { $0 } }
    
    private var repository: BudgetRepository {
        guard let repo = appState.repository else { fatalError("Repository unavailable") }
        return repo
    }

    var body: some View {
        ZStack {
            AppBackground()
            List {
                Section {
                    VStack(spacing: 24) {
                        Text("Overview")
                            .font(AppTheme.Fonts.largeTitle)
                            .foregroundColor(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top)

                        GlassCard {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Spent This Month")
                                    .font(AppTheme.Fonts.body)
                                    .foregroundStyle(.secondary)
                                Text(formatMoney(spentThisMonth()))
                                    .font(AppTheme.Fonts.title)
                                    .foregroundColor(.primary)
                                    .monospacedDigit()
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 16) {
                                metricCard(title: "Spent Today", value: spentToday())
                                metricCard(title: "Spent Last Month", value: spentLastMonth())
                                metricCard(title: "On-budget Accounts", value: onBudgetAccounts.count, isMoney: false)
                            }
                        }
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }

                Section(header:
                    HStack {
                        Text("Recent Activity")
                            .font(AppTheme.Fonts.title)
                            .foregroundColor(.primary)
                        Spacer()
                        NavigationLink("View All") { AllTransactionsView() }
                            .foregroundColor(AppTheme.accent)
                    }
                ) {
                    if recentFive.isEmpty {
                        GlassCard {
                            Text("No recent transactions to show.")
                                .font(AppTheme.Fonts.body)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, minHeight: 100)
                        }
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    } else {
                        ForEach(recentFive, id: \.id) { tx in
                            TransactionRow(
                                transaction: tx,
                                accounts: accounts,
                                payeesById: payeesById,
                                categoriesById: categoriesById,
                                currencyCode: appState.currencyCode,
                                onEdit: { t in activeSheet = .edit(t) },
                                onDelete: { t in Task { await delete(t) } }
                            )
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        }
                    }
                    Button {
                        activeSheet = .add
                    } label: {
                        HStack {
                            Image(systemName: "plus")
                            Text("Add Transaction")
                        }
                        .font(AppTheme.Fonts.headline)
                        .foregroundColor(AppTheme.accent)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .navigationBarHidden(true)
        .task { await load() }
        .sheet(item: $activeSheet) { sheetType in
            switch sheetType {
            case .add:
                TransactionEditor(transaction: nil, initialAccountId: nil, onSave: { _ in Task { await load() } })
            case .edit(let transaction):
                TransactionEditor(transaction: transaction, initialAccountId: nil, onSave: { _ in Task { await load() } })
            case .importCSV:
                EmptyView()
            }
        }
        .alert("Error", isPresented: .constant(errorMessage != nil), actions: {
            Button("OK") { errorMessage = nil }
        }, message: {
            Text(errorMessage ?? "An unknown error occurred.")
        })
    }

    private func metricCard(title: String, value: Int, isMoney: Bool = true) -> some View {
        GlassCard(cornerRadius: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(AppTheme.Fonts.footnote)
                    .foregroundStyle(.secondary)
                Text(isMoney ? formatMoney(value) : String(value))
                    .font(AppTheme.Fonts.subtitle)
                    .foregroundColor(.primary)
            }
            .frame(width: 140, alignment: .leading)
        }
    }

    private func load() async {
        do {
            let accList = try await repository.fetchAccounts()
            let catList = try await repository.fetchCategories()
            let payeeList = try await repository.fetchPayees()
            
            let since = firstOfThisMonthMinus(days: 31)
            var allTxs = [Transaction]()
            for acc in accList {
                let list = try await repository.fetchTransactions(accountId: acc.id, since: since)
                allTxs.append(contentsOf: list)
            }
            
            await MainActor.run {
                self.accounts = accList
                self.transactions = allTxs
                self.categoriesById = Dictionary(uniqueKeysWithValues: catList.map { ($0.id, $0.name) })
                self.payeesById = Dictionary(uniqueKeysWithValues: payeeList.map { ($0.id, $0) })
                
                SharedDataManager.shared.save(spentToday: self.spentToday(), currencyCode: self.appState.currencyCode)
            }
        } catch {
            await MainActor.run { errorMessage = error.localizedDescription }
        }
    }

    private func spentToday() -> Int {
        let today = format(date: Date())
        let onBudgetIds = Set(onBudgetAccounts.map { $0.id })
        let todays = transactions.filter { $0.date == today && onBudgetIds.contains($0.account) && !isTransfer($0) }
        return -todays.map { $0.amount ?? 0 }.filter { $0 < 0 }.reduce(0, +)
    }

    private func spentThisMonth() -> Int {
        let (start, end) = monthRange(date: Date())
        let onBudgetIds = Set(onBudgetAccounts.map { $0.id })
        let list = transactions.filter { $0.date >= start && $0.date <= end && onBudgetIds.contains($0.account) && !isTransfer($0) }
        return -list.map { $0.amount ?? 0 }.filter { $0 < 0 }.reduce(0, +)
    }

    private func spentLastMonth() -> Int {
        let cal = Calendar(identifier: .gregorian)
        let lastMonthDate = cal.date(byAdding: .month, value: -1, to: Date()) ?? Date()
        let (start, end) = monthRange(date: lastMonthDate)
        let onBudgetIds = Set(onBudgetAccounts.map { $0.id })
        let list = transactions.filter { $0.date >= start && $0.date <= end && onBudgetIds.contains($0.account) && !isTransfer($0) }
        return -list.map { $0.amount ?? 0 }.filter { $0 < 0 }.reduce(0, +)
    }

    private func isTransfer(_ tx: Transaction) -> Bool {
        if tx.transfer_id != nil { return true }
        if let payeeId = tx.payee, let p = payeesById[payeeId], p.transfer_acct != nil { return true }
        return false
    }

    private func recentNonTransferOnBudget() -> [Transaction] {
        let onBudgetIds = Set(onBudgetAccounts.map { $0.id })
        return transactions.filter { onBudgetIds.contains($0.account) && !isTransfer($0) }.sorted { $0.date > $1.date }
    }
    
    private func monthRange(date: Date) -> (String, String) {
        let cal = Calendar(identifier: .gregorian)
        let comps = cal.dateComponents([.year, .month], from: date)
        let startDate = cal.date(from: comps) ?? date
        let endDate = cal.date(byAdding: DateComponents(month: 1, day: -1), to: startDate) ?? date
        return (format(date: startDate), format(date: endDate))
    }

    private func firstOfThisMonthMinus(days: Int) -> String {
        let cal = Calendar(identifier: .gregorian)
        let comps = cal.dateComponents([.year, .month], from: Date())
        let start = cal.date(from: comps) ?? Date()
        let since = cal.date(byAdding: .day, value: -days, to: start) ?? start
        return format(date: since)
    }

    private func format(date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.string(from: date)
    }

    private func formatMoney(_ amount: Int) -> String {
        return CurrencyFormatter.shared.format(amount, currencyCode: appState.currencyCode)
    }

    private func delete(_ tx: Transaction) async {
        guard let txId = tx.id else { return }
        do {
            try await repository.deleteTransaction(id: txId)
            await load()
        } catch {
            await MainActor.run { errorMessage = error.localizedDescription }
        }
    }
}
