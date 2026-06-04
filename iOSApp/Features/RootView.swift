// RootView.swift

import SwiftUI

struct MainTabView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var appStateObserver = AppStateObserver.shared
    

    
    var body: some View {
        TabView {
            NavigationStack { DashboardView() }
                .tabItem { Label("Dashboard", systemImage: "chart.pie.fill") }

            NavigationStack { AccountsView() }
                .tabItem { Label("Accounts", systemImage: "wallet.pass.fill") }
            
            NavigationStack { BudgetView() }
                .tabItem { Label("Budget", systemImage: "list.clipboard.fill") }

            NavigationStack { SettingsView() }
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
        }
        .tint(AppTheme.accent)
        .sheet(isPresented: $appStateObserver.shouldShowAddSheet) {
            TransactionEditor(transaction: nil, initialAccountId: nil, onSave: { _ in })
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("OpenLogsView"))) { _ in
            AppStateObserver.shared.requestOpenLogs()
        }
        .sheet(isPresented: $appStateObserver.shouldOpenLogs) {
            NavigationStack { LogsView() }
        }

    }
}

#if os(macOS)
enum SidebarSelection: Hashable {
    case dashboard
    case budget
    case allTransactions
    case account(id: String)
    case manageCategories
    case logs
    case settings
}

struct SidebarAccount: Identifiable, Hashable {
    let id: String
    let name: String
    let offbudget: Bool
    let closed: Bool
    let balance: Int
}

struct MainSplitView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var appStateObserver = AppStateObserver.shared
    @State private var selectedSelection: SidebarSelection? = .dashboard
    @State private var sidebarAccounts: [SidebarAccount] = []
    @State private var accounts: [Account] = []

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedSelection) {
                Section(header: Text("Navigator")) {
                    NavigationLink(value: SidebarSelection.dashboard) {
                        Label("Dashboard", systemImage: "chart.pie.fill")
                    }
                    NavigationLink(value: SidebarSelection.budget) {
                        Label("Budget", systemImage: "list.clipboard.fill")
                    }
                    NavigationLink(value: SidebarSelection.allTransactions) {
                        Label("All Transactions", systemImage: "arrow.left.arrow.right.circle.fill")
                    }
                }
                
                let onBudgetAccs = sidebarAccounts.filter { !$0.offbudget && !$0.closed }
                if !onBudgetAccs.isEmpty {
                    Section(header: Text("On-Budget Accounts")) {
                        ForEach(onBudgetAccs) { acc in
                            NavigationLink(value: SidebarSelection.account(id: acc.id)) {
                                HStack {
                                    Label(acc.name, systemImage: "creditcard.fill")
                                    Spacer()
                                    Text(formatMoney(acc.balance))
                                        .font(.subheadline.monospacedDigit())
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }
                
                let offBudgetAccs = sidebarAccounts.filter { $0.offbudget && !$0.closed }
                if !offBudgetAccs.isEmpty {
                    Section(header: Text("Off-Budget Accounts")) {
                        ForEach(offBudgetAccs) { acc in
                            NavigationLink(value: SidebarSelection.account(id: acc.id)) {
                                HStack {
                                    Label(acc.name, systemImage: "creditcard")
                                    Spacer()
                                    Text(formatMoney(acc.balance))
                                        .font(.subheadline.monospacedDigit())
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }
                
                Section(header: Text("Preferences")) {
                    NavigationLink(value: SidebarSelection.manageCategories) {
                        Label("Manage Categories", systemImage: "tag.fill")
                    }
                    NavigationLink(value: SidebarSelection.logs) {
                        Label("System Logs", systemImage: "doc.text.magnifyingglass")
                    }
                    NavigationLink(value: SidebarSelection.settings) {
                        Label("Settings", systemImage: "gearshape.fill")
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .background(
                Color.clear.glassEffect(.regular, in: .rect)
            )
            .navigationTitle("Actual")
            .task {
                await reloadSidebarAccounts()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("BudgetDataChanged"))) { _ in
                Task {
                    await reloadSidebarAccounts()
                }
            }
            .onChange(of: appState.selectedBudgetID) {
                Task {
                    await reloadSidebarAccounts()
                }
            }
        } detail: {
            NavigationStack {
                switch selectedSelection {
                case .dashboard:
                    DashboardView()
                case .budget:
                    BudgetView()
                case .allTransactions:
                    AllTransactionsView()
                case .account(let id):
                    if let account = accounts.first(where: { $0.id == id }) {
                        TransactionsView(account: account)
                    } else {
                        Text("Select an Account")
                            .font(AppTheme.Fonts.title)
                            .foregroundColor(.secondary)
                    }
                case .manageCategories:
                    CategoryManagerView()
                case .logs:
                    LogsView()
                case .settings:
                    SettingsView()
                case nil:
                    Text("Select a section")
                        .font(AppTheme.Fonts.title)
                        .foregroundColor(.secondary)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.clear)
        }
        .sheet(isPresented: $appStateObserver.shouldShowAddSheet) {
            TransactionEditor(transaction: nil, initialAccountId: nil, onSave: { _ in })
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("OpenLogsView"))) { _ in
            selectedSelection = .logs
        }
        .sheet(isPresented: $appStateObserver.shouldOpenLogs) {
            NavigationStack { LogsView() }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    appStateObserver.requestAddTransaction()
                } label: {
                    Label("Add Transaction", systemImage: "plus")
                }
                .keyboardShortcut("n", modifiers: .command)
                .help("Add a new transaction (⌘N)")
            }
        }
    }

    private func reloadSidebarAccounts() async {
        guard let repo = appState.repository else { return }
        do {
            let list = try await repo.fetchAccounts()
            var sideList: [SidebarAccount] = []
            for acc in list {
                let bal = try await repo.fetchAccountBalance(accountId: acc.id)
                sideList.append(SidebarAccount(id: acc.id, name: acc.name, offbudget: acc.offbudget, closed: acc.closed, balance: bal))
            }
            await MainActor.run {
                self.accounts = list
                self.sidebarAccounts = sideList
            }
        } catch {
            print("Error loading sidebar accounts: \(error)")
        }
    }

    private func formatMoney(_ amount: Int) -> String {
        return CurrencyFormatter.shared.format(amount, currencyCode: appState.currencyCode)
    }
}
#endif

struct RootView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ZStack {
            #if os(macOS)
            LiquidBackground()
            #endif
            
            if appState.onboardingState == .ready {
                #if os(macOS)
                MainSplitView()
                #else
                MainTabView()
                #endif
            } else {
                OnboardingView()
            }
        }
    }
}