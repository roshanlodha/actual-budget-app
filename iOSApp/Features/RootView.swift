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
struct MainSplitView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var appStateObserver = AppStateObserver.shared
    @State private var selectedTab: SidebarTab? = .dashboard
    
    enum SidebarTab: Hashable, CaseIterable {
        case dashboard
        case accounts
        case budget
        case settings
        
        var title: String {
            switch self {
            case .dashboard: return "Dashboard"
            case .accounts: return "Accounts"
            case .budget: return "Budget"
            case .settings: return "Settings"
            }
        }
        
        var icon: String {
            switch self {
            case .dashboard: return "chart.pie.fill"
            case .accounts: return "wallet.pass.fill"
            case .budget: return "list.clipboard.fill"
            case .settings: return "gearshape.fill"
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            List(SidebarTab.allCases, id: \.self, selection: $selectedTab) { tab in
                NavigationLink(value: tab) {
                    Label(tab.title, systemImage: tab.icon)
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .background(
                Color.clear.glassEffect(.regular, in: .rect)
            )
            .navigationTitle("Actual")
        } detail: {
            NavigationStack {
                switch selectedTab {
                case .dashboard:
                    DashboardView()
                case .accounts:
                    AccountsView()
                case .budget:
                    BudgetView()
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
            AppStateObserver.shared.requestOpenLogs()
        }
        .sheet(isPresented: $appStateObserver.shouldOpenLogs) {
            NavigationStack { LogsView() }
        }
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