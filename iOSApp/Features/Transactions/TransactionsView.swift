import SwiftUI

struct TransactionsView: View {
    let account: Account
    @EnvironmentObject private var appState: AppState
    @State private var transactions: [Transaction] = []
    @State private var accounts: [Account] = []
    @State private var categoriesById: [String: Category] = [:]
    @State private var payeesById: [String: Payee] = [:]
    @State private var errorMessage: String?
    @State private var activeSheet: SheetType?

    private var repository: BudgetRepository {
        guard let repo = appState.repository else { fatalError("Repository unavailable") }
        return repo
    }

    var sortedTransactions: [Transaction] {
        transactions.sorted { ($0.date) > ($1.date) }
    }

    var body: some View {
        ZStack {
            AppBackground()
            ScrollView {
                AdaptiveGlassContainer(spacing: 12) {
                    VStack(spacing: 12) {
                        if sortedTransactions.isEmpty && errorMessage == nil {
                            GlassCard {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("No transactions yet")
                                        .font(AppTheme.Fonts.headline)
                                        .foregroundColor(.primary)
                                    Text("Add a transaction to start building this account's history.")
                                        .font(AppTheme.Fonts.body)
                                        .foregroundStyle(.secondary)
                                     Button("Import Transactions") {
                                         activeSheet = .importCSV
                                     }
                                     .buttonStyle(.borderedProminent)
                                     .tint(AppTheme.accent)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        } else {
                            LazyVStack(spacing: 12) {
                                ForEach(sortedTransactions, id: \.id) { tx in
                                    TransactionRow(
                                        transaction: tx,
                                        accounts: accounts,
                                        payeesById: payeesById,
                                        categoriesById: categoriesById,
                                        currencyCode: appState.currencyCode,
                                        onEdit: { t in activeSheet = .edit(t) },
                                        onDelete: { t in Task { await delete(t) } }
                                    )
                                    .contextMenu { contextMenuItems(for: tx) }
                                }
                            }
                        }
                    }
                    .padding()
                }
            }
            .applyScrollEdgeEffect()
        }
        .navigationTitle(account.name)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    activeSheet = .add
                } label: { Image(systemName: "plus") }
            }
        }
        .task { await loadAll() }
        .refreshable { await loadAll() }
        .sheet(item: $activeSheet) { sheetType in
            switch sheetType {
            case .add:
                TransactionEditor(transaction: nil, initialAccountId: account.id, onSave: { _ in Task { await loadAll() } })
            case .edit(let transaction):
                TransactionEditor(transaction: transaction, initialAccountId: account.id, onSave: { _ in Task { await loadAll() } })
            case .importCSV:
                CSVImportView(account: account, onImport: { Task { await loadAll() } })
            }
        }
        .alert("Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }
    
    @ViewBuilder
    private func contextMenuItems(for tx: Transaction) -> some View {
        if let destAccount = transferDestinationAccount(tx) {
            NavigationLink {
                TransactionsView(account: destAccount)
            } label: {
                Label("Go to Transfer Account", systemImage: "arrow.right.arrow.left.circle")
            }
        }
        
        Button(role: .destructive) {
            Task { await delete(tx) }
        } label: {
            Label("Delete Transaction", systemImage: "trash")
        }
    }

    private func delete(_ tx: Transaction) async {
        guard let txId = tx.id else { return }
        do {
            try await repository.deleteTransaction(id: txId)
            await loadAll()
        } catch {
            await MainActor.run { errorMessage = error.localizedDescription }
        }
    }
    
    private func transferDestinationAccount(_ tx: Transaction) -> Account? {
        if let payeeId = tx.payee,
           let p = payeesById[payeeId],
           let destAcctId = p.transfer_acct {
            return accounts.first { $0.id == destAcctId }
        }
        return nil
    }

    private func loadAll() async {
        do {
            let accountList = try await repository.fetchAccounts()
            let categories = try await repository.fetchCategories()
            let payeesList = try await repository.fetchPayees()
            let list = try await repository.fetchTransactions(accountId: account.id, since: defaultSinceDate())
            
            let catMap = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
            let payeeMap = Dictionary(uniqueKeysWithValues: payeesList.map { ($0.id, $0) })
            
            await MainActor.run {
                self.accounts = accountList
                categoriesById = catMap
                payeesById = payeeMap
                transactions = list
            }
        } catch {
            await MainActor.run { errorMessage = error.localizedDescription }
        }
    }
    
    private func formattedSignedAmount(_ amount: Int?) -> String {
        return CurrencyFormatter.shared.formatSigned(amount ?? 0, currencyCode: appState.currencyCode)
    }

    private func categoryName(_ id: String?) -> String? {
        guard let id else { return nil }
        return categoriesById[id]?.name
    }

    private func payeeText(_ tx: Transaction) -> String {
        if let account = transferDestinationAccount(tx) {
            return "Transfer \((tx.amount ?? 0) < 0 ? "to" : "from"): \(account.name)"
        }
        if let payeeId = tx.payee, let p = payeesById[payeeId] { return p.name }
        if let n = tx.payee_name, !n.isEmpty { return n }
        return "(No payee)"
    }
    
    private func defaultSinceDate() -> String {
        let cal = Calendar(identifier: .gregorian)
        let start = cal.date(byAdding: .year, value: -1, to: Date()) ?? Date()
        let f = DateFormatter(); f.calendar = cal; f.dateFormat = "yyyy-MM-dd"; return f.string(from: start)
    }
}
