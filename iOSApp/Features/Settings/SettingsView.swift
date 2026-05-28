import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    
    @State private var showingResetAlert = false
    
    var body: some View {
        ZStack {
            AppBackground()
            List {
                Section("Active Budget") {
                    HStack {
                        Text("Name")
                        Spacer()
                        Text(appState.selectedBudgetDisplayName)
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("ID")
                        Spacer()
                        Text(appState.selectedBudgetID ?? "Unknown")
                            .font(.caption.monospaced())
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    Button(role: .destructive) {
                        showingResetAlert = true
                    } label: {
                        Label("Reset App & Delete Data", systemImage: "trash.fill")
                    }
                }
                .listRowBackground(Color.primary.opacity(0.05))
                
                Section("Budget Structure") {
                    NavigationLink {
                        CategoryManagerView()
                    } label: {
                        Label("Manage Categories", systemImage: "tag.fill")
                    }
                }
                .listRowBackground(Color.primary.opacity(0.05))
                
                Section("Preferences") {
                    Picker("Theme", selection: $appState.currentTheme) {
                        ForEach(AppState.Theme.allCases) { theme in
                            Text(theme.rawValue).tag(theme)
                        }
                    }
                    Picker("Currency", selection: $appState.currencyCode) {
                        ForEach(CurrencyFormatter.supportedCurrencies, id: \.0) { code, name in
                            Text("\(code) - \(name)").tag(code)
                        }
                    }
                }
                .listRowBackground(Color.primary.opacity(0.05))
                
                Section("Logs") {
                    NavigationLink {
                        LogsView()
                    } label: {
                        Label("View System Logs", systemImage: "doc.text.magnifyingglass")
                    }
                }
                .listRowBackground(Color.primary.opacity(0.05))
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Settings")
        .alert("Reset App", isPresented: $showingResetAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete Everything", role: .destructive) {
                appState.resetBudget()
            }
        } message: {
            Text("This will permanently delete your budget, transactions, and categories. This action cannot be undone.")
        }
    }
}
