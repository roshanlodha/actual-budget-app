import SwiftUI

struct BudgetView: View {
    @EnvironmentObject private var appState: AppState
    @State private var monthDate: Date = Date()
    @State private var budget: BudgetMonth?
    @State private var monthGroups: [BudgetMonthCategoryGroup] = []
    @State private var expandedGroups: Set<String> = []
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            AppBackground()
            ScrollView {
                VStack(spacing: 24) {
                    header()
                    
                    if monthGroups.isEmpty {
                        GlassCard {
                             Text("No budget categories found for this month.")
                                 .font(AppTheme.Fonts.body)
                                 .foregroundStyle(.secondary)
                                 .frame(maxWidth: .infinity, minHeight: 100)
                         }
                    } else {
                        categoryGroups
                    }
                }
                .padding()
            }
        }
        .navigationTitle(monthTitle())
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button { moveMonth(-1) } label: { Image(systemName: "chevron.left") }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { moveMonth(+1) } label: { Image(systemName: "chevron.right") }
            }
        }
        .task { await loadAll() }
        .alert("Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    private func header() -> some View {
        GlassCard {
            VStack(alignment: .leading) {
                Text("To Be Budgeted")
                    .font(AppTheme.Fonts.body)
                    .foregroundStyle(.secondary) 
                Text(formatMoney(budget?.toBudget ?? 0))
                    .font(AppTheme.Fonts.title)
                    .foregroundColor( (budget?.toBudget ?? 0) < 0 ? AppTheme.destructive : .primary) 
                    .monospacedDigit()
                
                Divider().padding(.vertical, 8)
                
                HStack {
                    metric(label: "Available", value: budget?.incomeAvailable ?? 0)
                    Spacer()
                    metric(label: "Budgeted", value: budget?.totalBudgeted ?? 0)
                    Spacer()
                    metric(label: "Spent", value: budget?.totalSpent ?? 0)
                }
            }
        }
    }
    
    private var categoryGroups: some View {
        ForEach(sortedGroups(), id: \.id) { group in
            VStack(alignment: .leading, spacing: 12) {
                DisclosureGroup(isExpanded: Binding(
                    get: { expandedGroups.contains(group.id) },
                    set: { isExpanded in
                        if isExpanded { expandedGroups.insert(group.id) } else { expandedGroups.remove(group.id) }
                    }
                )) {
                    ForEach(group.categories ?? [], id: \.id) { cat in
                        categoryRow(cat)
                            .padding(.top, 8)
                    }
                } label: {
                    HStack {
                        Text(group.name)
                            .font(AppTheme.Fonts.subtitle)
                            .foregroundColor(.primary) 
                        Spacer()
                        Text(formatMoney(group.balance ?? 0))
                            .font(AppTheme.Fonts.body.monospacedDigit())
                            .foregroundStyle(.secondary) 
                    }
                }
                .accentColor(.secondary) 
            }
            .padding()
            .background(Color.primary.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        }
    }

    private func categoryRow(_ category: BudgetMonthCategory) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(category.name)
                    .font(AppTheme.Fonts.headline)
                    .foregroundColor(.primary) 
                Spacer()
                Text(formatMoney(category.balance ?? 0))
                    .font(AppTheme.Fonts.subheadline.monospacedDigit())
                    .foregroundColor( (category.balance ?? 0) < 0 ? AppTheme.destructive : .primary) 
            }
            
            let spent = abs(category.spent ?? 0)
            let budgeted = category.budgeted ?? 0
            let progress = budgeted > 0 ? min(Double(spent) / Double(budgeted), 1.0) : 0.0
            
            ProgressView(value: progress)
                .tint(progress > 0.85 ? AppTheme.destructive : AppTheme.accent)
                .padding(.top, 2)
            
            HStack {
                Text("Spent: \(formatMoney(spent))")
                Spacer()
                Text("Budgeted: \(formatMoney(budgeted))")
            }
            .font(AppTheme.Fonts.footnote)
            .foregroundStyle(.secondary) 
        }
    }

    private func metric(label: String, value: Int) -> some View {
        VStack(alignment: .leading) {
            Text(label)
                .font(AppTheme.Fonts.footnote)
                .foregroundStyle(.secondary) 
            Text(formatMoney(value))
                .font(AppTheme.Fonts.subheadline.monospacedDigit())
                .foregroundStyle(.primary) 
        }
    }
    
    private func sortedGroups() -> [BudgetMonthCategoryGroup] {
        let income = monthGroups.filter { $0.is_income == true }
        let spend = monthGroups.filter { $0.is_income != true }
        return spend + income
    }

    private func moveMonth(_ delta: Int) {
        monthDate = Calendar(identifier: .gregorian).date(
            byAdding: .month,
            value: delta,
            to: monthDate
        ) ?? monthDate
        Task { await loadAll() }
    }

    private func monthTitle() -> String {
        let f = DateFormatter(); f.dateFormat = "LLLL yyyy"; return f.string(from: monthDate)
    }

    private func formatMoney(_ amount: Int) -> String {
        return CurrencyFormatter.shared.format(amount, currencyCode: appState.currencyCode)
    }

    private func client() throws -> ActualAPIClient {
        try ActualAPIClient(
            baseURLString: appState.baseURLString,
            apiKey: appState.apiKey,
            syncId: appState.syncId,
            budgetEncryptionPassword: appState.budgetEncryptionPassword
        )
    }

    private func loadAll() async {
        do {
            let monthKey = String(format: "%04d-%02d", Calendar.current.component(.year, from: monthDate), Calendar.current.component(.month, from: monthDate))
            async let budgetMonth = try client().fetchBudgetMonth(monthKey)
            async let groups = try client().fetchBudgetMonthCategoryGroups(monthKey)
            let (bm, g) = try await (budgetMonth, groups)
            await MainActor.run {
                budget = bm
                monthGroups = g
            }
        } catch {
            await MainActor.run { errorMessage = error.localizedDescription }
        }
    }
}
