import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    
    @State private var showingResetAlert = false
    @State private var showingImportConfirmation = false
    @State private var showingFileImporter = false
    @State private var errorMessage: String? = nil
    
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
                    Button {
                        showingImportConfirmation = true
                    } label: {
                        Label("Import from Actual", systemImage: "arrow.down.doc.fill")
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
                    NavigationLink {
                        IgnoredCategoriesView()
                    } label: {
                        Label("Ignored Dashboard Categories", systemImage: "eye.slash.fill")
                    }
                }
                .listRowBackground(Color.primary.opacity(0.05))
                
                Section("Preferences") {

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
        .alert("Import Budget", isPresented: $showingImportConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Import & Overwrite", role: .destructive) {
                showingFileImporter = true
            }
        } message: {
            Text("This will overwrite your existing local budget data. Ensure you have backed up if necessary.")
        }
        .alert("Error", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: [.item],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let selectedURL = urls.first else { return }
                do {
                    try ActualBudgetImporter.importBudget(from: selectedURL, to: appState)
                } catch {
                    errorMessage = "Import failed: \(error.localizedDescription)"
                }
            case .failure(let error):
                errorMessage = "Failed to select file: \(error.localizedDescription)"
            }
        }
    }
}
