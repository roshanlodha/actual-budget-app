import SwiftUI

struct AllTransactionsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var transactions: [Transaction] = []
    @State private var accounts: [Account] = []
    @State private var payeesById: [String: Payee] = [:]
    @State private var categoriesById: [String: Category] = [:]
    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var onBudgetOnly: Bool = true
    @State private var filterGranularity: Granularity = .day
    @State private var filterValue: Int = 30
    @State private var activeSheet: SheetType?
    @State private var searchText: String = ""

    private var repository: BudgetRepository {
        guard let repo = appState.repository else { fatalError("Repository unavailable") }
        return repo
    }

    enum Granularity: String, CaseIterable, Identifiable {
        case day = "Days", week = "Weeks", month = "Months", year = "Years"
        var id: String { rawValue }
    }

    var filteredTransactions: [Transaction] {
        let onBudgetAccountIds = Set(accounts.filter { !$0.offbudget }.map { $0.id })
        let allAccountIds = Set(accounts.map { $0.id })
        let targetAccountIds = onBudgetOnly ? onBudgetAccountIds : allAccountIds
        
        var list = transactions
            .filter { targetAccountIds.contains($0.account) }
            
        if !searchText.isEmpty {
            list = list.filter { tx in
                let notesMatch = tx.notes?.localizedCaseInsensitiveContains(searchText) ?? false
                let payeeMatch = payeeText(tx).localizedCaseInsensitiveContains(searchText)
                let categoryMatch = (categoriesById[tx.category ?? ""]?.name).map { $0.localizedCaseInsensitiveContains(searchText) } ?? false
                return notesMatch || payeeMatch || categoryMatch
            }
        }
        
        return list.sorted { $0.date > $1.date }
    }

    private var listTransactions: [Transaction] {
        let since = sinceDateString()
        return filteredTransactions
            .filter { $0.date >= since }
            .filter { !isTransferToOnBudget($0) }
    }

    var body: some View {
        ZStack {
            AppBackground()
            ScrollView {
                AdaptiveGlassContainer(spacing: 12) {
                    VStack(spacing: 12) {
                        filtersBar
                        
                        if listTransactions.isEmpty && !isLoading {
                            GlassCard(cornerRadius: 15) {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("No transactions yet")
                                        .font(AppTheme.Fonts.headline)
                                        .foregroundColor(.primary)
                                    Text("Add a transaction to start building your history.")
                                        .font(AppTheme.Fonts.body)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        } else {
                            LazyVStack(spacing: 12) {
                                ForEach(listTransactions, id: \.id) { tx in
                                    TransactionRow(
                                        transaction: tx,
                                        accounts: accounts,
                                        payeesById: payeesById,
                                        categoriesById: categoriesById,
                                        currencyCode: appState.currencyCode,
                                        onEdit: { t in activeSheet = .edit(t) },
                                        onDelete: { t in Task { await delete(t) } }
                                    )
                                }
                            }
                        }
                    }
                    .padding()
                }
                .macContentWidth()
            }
            .applyScrollEdgeEffect()
        }
        .navigationTitle("All Transactions")
        .searchable(text: $searchText, prompt: "Search transactions")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    activeSheet = .add
                } label: { Image(systemName: "plus") }
            }
        }
        .task { await load() }
        .refreshable { await load() }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("BudgetDataChanged"))) { _ in
            Task { await load() }
        }
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
        .alert("Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    private func delete(_ tx: Transaction) async {
        guard let id = tx.id else { return }
        do {
            try await repository.deleteTransaction(id: id)
            await load()
        } catch {
            await MainActor.run { errorMessage = error.localizedDescription }
        }
    }

    private var filtersBar: some View {
        GlassCard(cornerRadius: 15) {
            VStack(spacing: 16) {
                Toggle("On-budget only", isOn: $onBudgetOnly)
                    .tint(AppTheme.accent)
                    .font(AppTheme.Fonts.body)
                
                Picker("Range", selection: $filterGranularity) {
                    ForEach(Granularity.allCases) { g in
                        Text(g.rawValue).tag(g)
                    }
                }
                .pickerStyle(.segmented)
                
                Stepper("Last \(filterValue) \(filterGranularity.rawValue)", value: $filterValue, in: 1...365)
                    .font(AppTheme.Fonts.body)
            }
            .foregroundColor(.primary)
        }
    }

    private func isTransferToOnBudget(_ tx: Transaction) -> Bool {
        if let payeeId = tx.payee, let p = payeesById[payeeId], let destId = p.transfer_acct {
            if let dest = accounts.first(where: { $0.id == destId }) {
                return !dest.offbudget
            }
        }
        return false
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let since = sinceDateString()
            let accountsList = try await repository.fetchAccounts()
            let payeesList = try await repository.fetchPayees()
            let categories = try await repository.fetchCategories()
            
            let mappingCats = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
            let mappingPayees = Dictionary(uniqueKeysWithValues: payeesList.map { ($0.id, $0) })
            
            var allTxs = [Transaction]()
            for acc in accountsList {
                let list = try await repository.fetchTransactions(accountId: acc.id, since: since)
                allTxs.append(contentsOf: list)
            }
            
            await MainActor.run {
                self.accounts = accountsList
                self.categoriesById = mappingCats
                self.payeesById = mappingPayees
                self.transactions = allTxs
            }
        } catch {
            await MainActor.run { errorMessage = error.localizedDescription }
        }
    }
    
    private func sinceDateString() -> String {
        let cal = Calendar.current
        let now = Date()
        let fromDate: Date
        switch filterGranularity {
        case .day: fromDate = cal.date(byAdding: .day, value: -filterValue, to: now) ?? now
        case .week: fromDate = cal.date(byAdding: .weekOfYear, value: -filterValue, to: now) ?? now
        case .month: fromDate = cal.date(byAdding: .month, value: -filterValue, to: now) ?? now
        case .year: fromDate = cal.date(byAdding: .year, value: -filterValue, to: now) ?? now
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: fromDate)
    }

    private func formattedSignedAmount(_ amount: Int?) -> String {
        CurrencyFormatter.shared.formatSigned(amount ?? 0, currencyCode: appState.currencyCode)
    }

    private func payeeText(_ tx: Transaction) -> String {
        if let payeeId = tx.payee, let p = payeesById[payeeId] { return p.name }
        if let n = tx.payee_name, !n.isEmpty { return n }
        return "(No payee)"
    }
}
