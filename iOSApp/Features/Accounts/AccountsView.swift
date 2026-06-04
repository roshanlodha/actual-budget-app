import SwiftUI

struct AccountsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var accounts: [Account] = []
    @State private var search: String = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingCreate = false
    @State private var balancesById: [String: Int] = [:]

    private var repository: BudgetRepository {
        guard let repo = appState.repository else { fatalError("Repository unavailable") }
        return repo
    }

    private var onBudget: [Account] {
        let list = accounts.filter { !$0.offbudget }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        guard !search.isEmpty else { return list }
        return list.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    private var offBudget: [Account] {
        let list = accounts.filter { $0.offbudget }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        guard !search.isEmpty else { return list }
        return list.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        ZStack {
            AppBackground()
            ScrollView {
                AdaptiveGlassContainer(spacing: 24) {
                    VStack(spacing: 24) {
                        GlassCard(cornerRadius: 15) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Total Balance")
                                        .font(AppTheme.Fonts.subheadline)
                                        .foregroundColor(.secondary)
                                    Text(formattedAmount(totalAll()))
                                        .font(AppTheme.Fonts.largeTitle.monospacedDigit())
                                        .foregroundColor(.primary)
                                }
                                Spacer()
                            }
                        }
                        if accounts.isEmpty && !isLoading {
                            emptyState
                        }
                        if !onBudget.isEmpty {
                            accountSection(title: "On-Budget", accounts: onBudget)
                        }
                        if !offBudget.isEmpty {
                            accountSection(title: "Off-Budget", accounts: offBudget)
                        }
                    }
                    .padding()
                }
                .macContentWidth()
            }
            .applyScrollEdgeEffect()
        }
        .navigationTitle("Accounts")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showingCreate = true } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundColor(AppTheme.accent)
                }
            }
        }
        .task { await reload() }
        .refreshable { await reload() }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("BudgetDataChanged"))) { _ in
            Task { await reload() }
        }
        .alert("Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
        .sheet(isPresented: $showingCreate) {
            CreateAccountSheet { name, offbudget in
                Task { await createAccount(name: name, offbudget: offbudget) }
            }
            .presentationDetents([.height(260)])
        }
    }

    private func accountSection(title: String, accounts: [Account]) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(title)
                    .font(AppTheme.Fonts.subtitle)
                    .foregroundColor(.primary)
                Spacer()
                Text(formattedAmount(totalFor(accounts: accounts)))
                    .font(AppTheme.Fonts.body.monospacedDigit())
                    .foregroundColor(.primary)
            }
            .padding(.horizontal)

            ForEach(accounts) { account in
                NavigationLink(destination: TransactionsView(account: account)) {
                    GlassCard(cornerRadius: 15, isInteractive: true) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(account.name)
                                    .font(AppTheme.Fonts.headline)
                                    .foregroundColor(.primary)
                                Text(account.closed ? "Closed" : "Active")
                                    .font(AppTheme.Fonts.footnote)
                                    .foregroundStyle(account.closed ? AppTheme.destructive : .secondary)
                            }
                            Spacer()
                            Text(formattedAmount(balancesById[account.id]))
                                .font(AppTheme.Fonts.body.monospacedDigit())
                                .foregroundColor(.primary)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func reload() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let list = try await repository.fetchAccounts()
            var balances = [String: Int]()
            for acc in list {
                balances[acc.id] = try await repository.fetchAccountBalance(accountId: acc.id)
            }
            await MainActor.run {
                self.accounts = list
                self.balancesById = balances
            }
        } catch {
            await MainActor.run { errorMessage = error.localizedDescription }
        }
    }

    private func formattedAmount(_ amount: Int?) -> String {
        return CurrencyFormatter.shared.format(amount ?? 0, currencyCode: appState.currencyCode)
    }

    private func totalFor(accounts: [Account]) -> Int {
        accounts.map { balancesById[$0.id] ?? 0 }.reduce(0, +)
    }

    private func totalAll() -> Int {
        totalFor(accounts: self.accounts)
    }

    private func createAccount(name: String, offbudget: Bool) async {
        do {
            _ = try await repository.createAccount(name: name, offbudget: offbudget)
            await reload()
        } catch {
            await MainActor.run { errorMessage = error.localizedDescription }
        }
    }

    private var emptyState: some View {
        GlassCard(cornerRadius: 15) {
            VStack(alignment: .leading, spacing: 12) {
                Text("No accounts yet")
                    .font(AppTheme.Fonts.headline)
                    .foregroundColor(.primary)
                Text("Create your first account to start tracking balances and transactions.")
                    .font(AppTheme.Fonts.body)
                    .foregroundStyle(.secondary)
                Button("Create your first account") {
                    showingCreate = true
                }
                .buttonStyle(.glassProminent)
                .tint(AppTheme.accent)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct CreateAccountSheet: View {
    var onCreate: (String, Bool) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @State private var offbudget: Bool = false

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                ScrollView {
                    VStack(spacing: 20) {
                        GlassCard(cornerRadius: 15) {
                            VStack(spacing: 16) {
                                TextField("Account Name", text: $name)
                                    .textFieldStyle(GlassTextFieldStyle())
                                
                                Toggle("Off-budget account", isOn: $offbudget)
                                    .tint(AppTheme.accent)
                                    .font(AppTheme.Fonts.body)
                            }
                        }
                    }
                    .padding()
                }
                .applyScrollEdgeEffect()
            }
            .navigationTitle("New Account")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        onCreate(name, offbudget)
                        dismiss()
                    }
                    .disabled(name.isEmpty)
                }
            }
            .tint(AppTheme.accent)
        }
    }
}
