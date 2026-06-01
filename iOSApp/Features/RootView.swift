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

struct RootView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        if appState.onboardingState == .ready {
            MainTabView()
        } else {
            OnboardingView()
        }
    }
}