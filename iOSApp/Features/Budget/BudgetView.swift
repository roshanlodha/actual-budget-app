import SwiftUI

struct BudgetView: View {
    @EnvironmentObject private var appState: AppState
    @State private var monthDate: Date = Date()
    @State private var budget: BudgetMonth?
    @State private var monthGroups: [BudgetMonthCategoryGroup] = []
    @State private var expandedGroups: Set<String> = []
    @State private var errorMessage: String?
    
    @State private var editingCategory: BudgetMonthCategory?
    @State private var editBudgetString: String = ""

    private var repository: BudgetRepository {
        guard let repo = appState.repository else { fatalError("Repository unavailable") }
        return repo
    }

    var body: some View {
        ZStack {
            AppBackground()
            ScrollView {
                AdaptiveGlassContainer(spacing: 24) {
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
                .macContentWidth()
            }
            .applyScrollEdgeEffect()
        }
        .navigationTitle(monthTitle())
        .toolbar {
            #if os(iOS)
            ToolbarItem(placement: .navigationBarLeading) {
                Button { moveMonth(-1) } label: { Image(systemName: "chevron.left") }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { moveMonth(+1) } label: { Image(systemName: "chevron.right") }
            }
            #else
            ToolbarItem(placement: .navigation) {
                Button { moveMonth(-1) } label: { Image(systemName: "chevron.left") }
            }
            ToolbarItem(placement: .primaryAction) {
                Button { moveMonth(+1) } label: { Image(systemName: "chevron.right") }
            }
            #endif
        }
        .task { await loadAll() }
        #if os(iOS)
        .alert("Budget Amount", isPresented: Binding(
            get: { editingCategory != nil },
            set: { if !$0 { editingCategory = nil } }
        )) {
            TextField("Amount", text: $editBudgetString)
                .keyboardType(.decimalPad)
            Button("Cancel", role: .cancel) { editingCategory = nil }
            Button("Save") {
                if let cat = editingCategory {
                    saveBudget(for: cat)
                }
            }
        } message: {
            if let cat = editingCategory {
                Text("Enter budgeted amount for \(cat.name)")
            }
        }
        #else
        .popover(item: $editingCategory) { cat in
            VStack(alignment: .leading, spacing: 12) {
                Text("Budget for \(cat.name)")
                    .font(AppTheme.Fonts.headline)
                
                TextField("Amount", text: $editBudgetString)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)
                
                HStack {
                    Button("Cancel") {
                        editingCategory = nil
                    }
                    .buttonStyle(.bordered)
                    
                    Spacer()
                    
                    Button("Save") {
                        saveBudget(for: cat)
                        editingCategory = nil
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.accent)
                }
            }
            .padding()
            .frame(width: 240)
        }
        #endif
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("BudgetDataChanged"))) { _ in
            Task {
                await loadAll()
            }
        }
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
            GlassCard(cornerRadius: 15) {
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
            }
        }
    }

    private func categoryRow(_ category: BudgetMonthCategory) -> some View {
        Button {
            editingCategory = category
            editBudgetString = String(format: "%.2f", Double(category.budgeted ?? 0) / 100.0)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 12) {
                    let color = Color(hex: category.color ?? "#8D93AB")
                    let iconName = category.icon ?? "tag.fill"
                    
                    Image(systemName: iconName)
                        .font(.caption)
                        .foregroundColor(.white)
                        .frame(width: 24, height: 24)
                        .background(color)
                        .clipShape(Circle())
                    
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
                let progress = budgeted > 0 ? min(Double(spent) / Double(budgeted), 1.0) : (spent > 0 ? 1.0 : 0.0)
                
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
        .buttonStyle(.plain)
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

    private func loadAll() async {
        do {
            let monthKey = String(format: "%04d-%02d", Calendar.current.component(.year, from: monthDate), Calendar.current.component(.month, from: monthDate))
            let bm = try await repository.fetchBudgetMonth(monthKey)
            let g = try await repository.fetchBudgetMonthCategoryGroups(monthKey)
            await MainActor.run {
                budget = bm
                monthGroups = g
            }
        } catch {
            await MainActor.run { errorMessage = error.localizedDescription }
        }
    }

    private func saveBudget(for category: BudgetMonthCategory) {
        let amountDouble = Double(editBudgetString.replacingOccurrences(of: ",", with: ".")) ?? 0.0
        let budgetedCents = Int(amountDouble * 100)
        let monthKey = String(format: "%04d-%02d", Calendar.current.component(.year, from: monthDate), Calendar.current.component(.month, from: monthDate))
        
        Task {
            do {
                try await repository.updateBudgetAmount(month: monthKey, categoryId: category.id, budgeted: budgetedCents)
                await loadAll()
            } catch {
                await MainActor.run { errorMessage = error.localizedDescription }
            }
        }
    }
}
