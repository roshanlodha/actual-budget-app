import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @AppStorage("hideYtdMonthlyExpenses") private var hideYtdMonthlyExpenses: Bool = true
    
    @State private var showingResetAlert = false
    @State private var showingImportConfirmation = false
    @State private var showingActualImportSheet = false
    @State private var errorMessage: String? = nil
    
    var body: some View {
        ZStack {
            AppBackground()
            ScrollView {
                AdaptiveGlassContainer(spacing: 24) {
                    VStack(spacing: 24) {
                        // Section 1: Active Budget
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Active Budget")
                                .font(AppTheme.Fonts.subheadline)
                                .foregroundColor(.secondary)
                                .padding(.horizontal)
                            
                            GlassCard(cornerRadius: 15) {
                                VStack(spacing: 14) {
                                    Button {
                                        showingImportConfirmation = true
                                    } label: {
                                        HStack {
                                            Label("Import from Actual", systemImage: "arrow.down.doc.fill")
                                                .font(AppTheme.Fonts.body)
                                                .foregroundColor(AppTheme.accent)
                                            Spacer()
                                            Image(systemName: "chevron.right")
                                                .font(.footnote)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        
                        // Section 2: Budget Structure
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Budget Structure")
                                .font(AppTheme.Fonts.subheadline)
                                .foregroundColor(.secondary)
                                .padding(.horizontal)
                            
                            GlassCard(cornerRadius: 15) {
                                VStack(spacing: 14) {
                                    NavigationLink {
                                        CategoryManagerView()
                                    } label: {
                                        HStack {
                                            Label("Manage Categories", systemImage: "tag.fill")
                                                .font(AppTheme.Fonts.body)
                                            Spacer()
                                            Image(systemName: "chevron.right")
                                                .font(.footnote)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                    
                                    Divider()
                                    
                                    NavigationLink {
                                        IgnoredCategoriesView()
                                    } label: {
                                        HStack {
                                            Label("Ignored Dashboard Categories", systemImage: "eye.slash.fill")
                                                .font(AppTheme.Fonts.body)
                                            Spacer()
                                            Image(systemName: "chevron.right")
                                                .font(.footnote)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        
                        // Section 3: Preferences
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Dashboard Preferences")
                                .font(AppTheme.Fonts.subheadline)
                                .foregroundColor(.secondary)
                                .padding(.horizontal)
                            
                            GlassCard(cornerRadius: 15) {
                                Toggle(isOn: $hideYtdMonthlyExpenses) {
                                    Label("Hide YTD Monthly Expenses", systemImage: "chart.bar.fill")
                                        .font(AppTheme.Fonts.body)
                                }
                                .tint(AppTheme.accent)
                            }
                        }
                        
                        // Section 4: Logs
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Logs")
                                .font(AppTheme.Fonts.subheadline)
                                .foregroundColor(.secondary)
                                .padding(.horizontal)
                            
                            GlassCard(cornerRadius: 15) {
                                NavigationLink {
                                    LogsView()
                                } label: {
                                    HStack {
                                        Label("View System Logs", systemImage: "doc.text.magnifyingglass")
                                            .font(AppTheme.Fonts.body)
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.footnote)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        
                        // Section 5: Danger Zone
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Danger Zone")
                                .font(AppTheme.Fonts.subheadline)
                                .foregroundColor(AppTheme.destructive)
                                .padding(.horizontal)
                            
                            GlassCard(cornerRadius: 15) {
                                Button {
                                    showingResetAlert = true
                                } label: {
                                    HStack {
                                        Label("Reset App & Delete Data", systemImage: "trash.fill")
                                            .font(AppTheme.Fonts.body)
                                            .foregroundColor(AppTheme.destructive)
                                        Spacer()
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding()
                }
                .macContentWidth()
            }
            .applyScrollEdgeEffect()
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
                showingActualImportSheet = true
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
        .sheet(isPresented: $showingActualImportSheet) {
            ActualBudgetImportView()
        }
    }
}
