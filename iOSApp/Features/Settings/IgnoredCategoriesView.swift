import SwiftUI

struct IgnoredCategoriesView: View {
    @EnvironmentObject private var appState: AppState
    @State private var groups: [CategoryGroup] = []
    @State private var ignoredIDs: Set<String> = []
    @State private var errorMessage: String?
    @State private var isLoading = false
    
    private var repository: BudgetRepository {
        guard let repo = appState.repository else { fatalError("Repository unavailable") }
        return repo
    }
    
    struct CategoryGroup: Identifiable {
        let id: String
        let name: String
        let isIncome: Bool
        var categories: [Category]
    }
    
    var body: some View {
        ZStack {
            AppBackground()
            
            if isLoading {
                ProgressView()
                    .tint(AppTheme.accent)
            } else {
                ScrollView {
                    AdaptiveGlassContainer(spacing: 24) {
                        VStack(spacing: 24) {
                            // Intro/Footnote card
                            GlassCard(cornerRadius: 15) {
                                Text("Selected categories will be hidden and excluded from all calculations on the Dashboard (averages, charts, cash flow, calendar). Useful for reimbursements or shared group bills.")
                                    .font(AppTheme.Fonts.footnote)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.leading)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            
                            ForEach(groups) { group in
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(group.name)
                                        .font(AppTheme.Fonts.subtitle)
                                        .foregroundColor(.primary)
                                        .padding(.horizontal)
                                    
                                    GlassCard(cornerRadius: 15) {
                                        VStack(spacing: 14) {
                                            if group.categories.isEmpty {
                                                Text("No categories in this group")
                                                    .font(AppTheme.Fonts.footnote)
                                                    .foregroundColor(.secondary)
                                                    .frame(maxWidth: .infinity, alignment: .leading)
                                            } else {
                                                ForEach(Array(group.categories.enumerated()), id: \.1.id) { index, cat in
                                                    let isIgnored = ignoredIDs.contains(cat.id)
                                                    
                                                    Button {
                                                        toggleIgnore(categoryId: cat.id)
                                                    } label: {
                                                        HStack(spacing: 12) {
                                                            Image(systemName: cat.icon ?? "tag.fill")
                                                                .foregroundColor(.white)
                                                                .frame(width: 28, height: 28)
                                                                .background(Color(hex: cat.color ?? "#8D93AB"))
                                                                .clipShape(Circle())
                                                            
                                                            Text(cat.name)
                                                                .font(AppTheme.Fonts.body)
                                                                .foregroundColor(.primary)
                                                            
                                                            Spacer()
                                                            
                                                            if isIgnored {
                                                                Image(systemName: "eye.slash.fill")
                                                                    .foregroundColor(AppTheme.destructive)
                                                            } else {
                                                                Image(systemName: "eye.fill")
                                                                    .foregroundColor(AppTheme.positive)
                                                            }
                                                        }
                                                    }
                                                    .buttonStyle(.plain)
                                                    
                                                    if index < group.categories.count - 1 {
                                                        Divider()
                                                            .background(Color.primary.opacity(0.08))
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        .padding()
                    }
                }
                .applyScrollEdgeEffect()
            }
        }
        .navigationTitle("Ignored Categories")
        .task {
            loadIgnored()
            await loadCategories()
        }
        .alert("Error", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }
    
    private func loadIgnored() {
        let saved = UserDefaults.standard.stringArray(forKey: "IgnoredCategoryIDs") ?? []
        ignoredIDs = Set(saved)
    }
    
    private func toggleIgnore(categoryId: String) {
        if ignoredIDs.contains(categoryId) {
            ignoredIDs.remove(categoryId)
        } else {
            ignoredIDs.insert(categoryId)
        }
        UserDefaults.standard.set(Array(ignoredIDs), forKey: "IgnoredCategoryIDs")
        NotificationCenter.default.post(name: NSNotification.Name("IgnoredCategoriesChanged"), object: nil)
    }
    
    private func loadCategories() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let fetchedGroups = try await repository.fetchCategoryGroups()
            let fetchedCats = try await repository.fetchCategories()
            
            var localGroups = [CategoryGroup]()
            for fg in fetchedGroups {
                let groupCats = fetchedCats.filter { $0.group_id == fg.id }
                localGroups.append(CategoryGroup(
                    id: fg.id,
                    name: fg.name,
                    isIncome: fg.is_income ?? false,
                    categories: groupCats
                ))
            }
            
            let spend = localGroups.filter { !$0.isIncome }
            let income = localGroups.filter { $0.isIncome }
            
            await MainActor.run {
                self.groups = spend + income
            }
        } catch {
            await MainActor.run { errorMessage = error.localizedDescription }
        }
    }
}
