import SwiftUI
import Charts

struct DashboardView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel = DashboardViewModel()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedAngle: Double? = nil
    @State private var selectedCategoryName: String? = nil

    var body: some View {
        ZStack {
            AppBackground()
            
            ScrollView {
                AdaptiveGlassContainer(spacing: 20) {
                    VStack(spacing: 20) {
                        // Month Selector Header at top of Dashboard content
                        HStack {
                            Button(action: {
                                viewModel.calendarMonthOffset -= 1
                                Task {
                                    await viewModel.loadData()
                                }
                            }) {
                                Image(systemName: "chevron.left")
                                    .font(.title3.bold())
                                    .foregroundColor(AppTheme.accent)
                                    .padding(10)
                                    .background(Circle().fill(Color.primary.opacity(0.06)))
                            }
                            .buttonStyle(.plain)
                            
                            Spacer()
                            
                            if let activeMonth = viewModel.calendarMonths.first {
                                Text(activeMonth.monthName)
                                    .font(AppTheme.Fonts.title)
                                    .foregroundColor(.primary)
                            } else {
                                Text("Select Month")
                                    .font(AppTheme.Fonts.title)
                                    .foregroundColor(.primary)
                            }
                            
                            Spacer()
                            
                            Button(action: {
                                viewModel.calendarMonthOffset += 1
                                Task {
                                    await viewModel.loadData()
                                }
                            }) {
                                Image(systemName: "chevron.right")
                                    .font(.title3.bold())
                                    .foregroundColor(AppTheme.accent)
                                    .padding(10)
                                    .background(Circle().fill(Color.primary.opacity(0.06)))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal)
                        .padding(.top, 8)

                        // Section 1: Summary Stat Cards
                        HStack(spacing: 16) {
                            // Card A: Average Expenses
                            GlassCard {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Average Expenses")
                                        .font(AppTheme.Fonts.subheadline)
                                        .foregroundColor(.secondary)
                                    
                                    if viewModel.isLoading {
                                        ProgressView()
                                            .padding(.top, 4)
                                    } else {
                                        Text(formatMoney(viewModel.monthlyExpenseAverage))
                                            .font(AppTheme.Fonts.largeTitle.monospacedDigit())
                                            .foregroundColor(AppTheme.destructive)
                                            .minimumScaleFactor(0.5)
                                            .lineLimit(1)
                                            .padding(.top, 4)
                                        
                                        Text("YTD: \(formatMoney(viewModel.ytdExpenseTotal))")
                                            .font(AppTheme.Fonts.caption)
                                            .foregroundColor(.secondary)
                                            .padding(.top, 2)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                            }
                            
                            // Card B: Average Income
                            GlassCard {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Average Income")
                                        .font(AppTheme.Fonts.subheadline)
                                        .foregroundColor(.secondary)
                                    
                                    if viewModel.isLoading {
                                        ProgressView()
                                            .padding(.top, 4)
                                    } else {
                                        Text(formatMoney(viewModel.monthlyIncomeAverage))
                                            .font(AppTheme.Fonts.largeTitle.monospacedDigit())
                                            .foregroundColor(AppTheme.positive)
                                            .minimumScaleFactor(0.5)
                                            .lineLimit(1)
                                            .padding(.top, 4)
                                        
                                        Text("YTD: \(formatMoney(viewModel.ytdIncomeTotal))")
                                            .font(AppTheme.Fonts.caption)
                                            .foregroundColor(.secondary)
                                            .padding(.top, 2)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                            }
                        }
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal)
                        
                        // Section 2: Month Expenses Mini Chart (Pie/Donut)
                        GlassCard {
                            VStack(alignment: .leading, spacing: 16) {
                                Text("Month Expenses")
                                    .font(AppTheme.Fonts.headline)
                                
                                if viewModel.isLoading {
                                    HStack {
                                        Spacer()
                                        ProgressView()
                                        Spacer()
                                    }
                                    .frame(height: 180)
                                } else if viewModel.currentMonthCategoryBreakdown.isEmpty {
                                    emptyStateView(title: "No Expenses", systemImage: "chart.pie", description: "No expenses recorded this month.")
                                        .frame(height: 180)
                                } else {
                                    ZStack {
                                        Chart(viewModel.currentMonthCategoryBreakdown) { item in
                                            SectorMark(
                                                angle: .value("Amount", item.amount),
                                                innerRadius: .ratio(0.65),
                                                outerRadius: selectedCategoryName == item.category ? .ratio(1.0) : .ratio(0.9),
                                                angularInset: 1.5
                                            )
                                            .foregroundStyle(by: .value("Category", item.category))
                                            .opacity(selectedCategoryName == nil || selectedCategoryName == item.category ? 1.0 : 0.35)
                                            .accessibilityLabel("\(item.category) \(formatMoney(Int(item.amount * 100)))")
                                        }
                                        .chartForegroundStyleScale(domain: Array(viewModel.categoryColorMap.keys), range: Array(viewModel.categoryColorMap.values))
                                        .chartAngleSelection(value: $selectedAngle)
                                        .chartLegend(.hidden)
                                        .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.7), value: viewModel.currentMonthCategoryBreakdown)
                                        .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.7), value: selectedCategoryName)
                                        .frame(height: 180)
                                        
                                        // Dynamic central text and glass indicator
                                        VStack(spacing: 2) {
                                            if let activeCategoryName = selectedCategoryName,
                                               let categoryExpense = viewModel.currentMonthCategoryBreakdown.first(where: { $0.category == activeCategoryName }) {
                                                Text(activeCategoryName)
                                                    .font(AppTheme.Fonts.caption)
                                                    .bold()
                                                    .foregroundColor(viewModel.categoryColorMap[activeCategoryName] ?? .primary)
                                                    .lineLimit(1)
                                                    .minimumScaleFactor(0.6)
                                                    .padding(.horizontal, 8)
                                                
                                                Text(formatMoney(Int(categoryExpense.amount * 100)))
                                                    .font(AppTheme.Fonts.subtitle)
                                                    .bold()
                                                    .foregroundColor(.primary)
                                                    .minimumScaleFactor(0.5)
                                                    .lineLimit(1)
                                            } else {
                                                Text("Total")
                                                    .font(AppTheme.Fonts.caption)
                                                    .foregroundColor(.secondary)
                                                
                                                let total = Int(viewModel.currentMonthCategoryBreakdown.map { $0.amount }.reduce(0, +) * 100)
                                                Text(formatMoney(total))
                                                    .font(AppTheme.Fonts.subtitle)
                                                    .bold()
                                                    .foregroundColor(.primary)
                                                    .minimumScaleFactor(0.5)
                                                    .lineLimit(1)
                                            }
                                        }
                                        .frame(width: 100, height: 100)
                                        .background(
                                            Circle()
                                                .glassEffect(.clear, in: .circle)
                                        )
                                        .contentShape(Circle())
                                        .onTapGesture {
                                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                                selectedCategoryName = nil
                                                selectedAngle = nil
                                            }
                                        }
                                    }
                                    .onChange(of: selectedAngle) { newValue in
                                        if let newValue {
                                            var cumulativeSum = 0.0
                                            for item in viewModel.currentMonthCategoryBreakdown {
                                                cumulativeSum += item.amount
                                                if newValue <= cumulativeSum {
                                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                                                        selectedCategoryName = item.category
                                                    }
                                                    return
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.horizontal)
                        
                        // Section 3: Transaction Calendar
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Transaction Calendar")
                                .font(AppTheme.Fonts.subtitle)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal)
                                .padding(.top, 8)
                            
                            if viewModel.isLoading {
                                HStack {
                                    Spacer()
                                    ProgressView()
                                    Spacer()
                                }
                                .frame(height: 150)
                            } else {
                                VStack(spacing: 16) {
                                    ForEach(viewModel.calendarMonths) { month in
                                        GlassCard {
                                            VStack(alignment: .leading, spacing: 12) {
                                                // Header
                                                HStack {
                                                    Text("Day Grid")
                                                        .font(AppTheme.Fonts.subheadline)
                                                        .bold()
                                                    
                                                    Spacer()
                                                    HStack(spacing: 8) {
                                                        Text("↑ \(formatMoney(month.totalIncome))")
                                                            .foregroundColor(AppTheme.positive)
                                                        Text("↓ \(formatMoney(month.totalExpense))")
                                                            .foregroundColor(AppTheme.destructive)
                                                    }
                                                    .font(AppTheme.Fonts.caption)
                                                    .monospacedDigit()
                                                }
                                                
                                                // Weekday headers
                                                let weekdayHeaders = ["S", "M", "T", "W", "T", "F", "S"]
                                                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 8) {
                                                    ForEach(weekdayHeaders, id: \.self) { day in
                                                        Text(day)
                                                            .font(AppTheme.Fonts.caption)
                                                            .foregroundColor(.secondary)
                                                            .frame(maxWidth: .infinity)
                                                    }
                                                    
                                                    // Day cells
                                                    ForEach(month.days) { day in
                                                        if day.isPadding {
                                                            Spacer()
                                                                .frame(width: 44, height: 44)
                                                        } else {
                                                            Button(action: {
                                                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                                                viewModel.selectDate(day)
                                                            }) {
                                                                VStack(spacing: 2) {
                                                                    Text("\(day.dayNumber)")
                                                                        .font(AppTheme.Fonts.body)
                                                                        .foregroundColor(.primary)
                                                                    
                                                                    if day.income > 0 || day.expense > 0 {
                                                                        let isNetIncome = day.income > day.expense
                                                                        RoundedRectangle(cornerRadius: 2)
                                                                            .fill(isNetIncome ? AppTheme.positive : AppTheme.destructive)
                                                                            .frame(width: 24, height: 4)
                                                                    } else {
                                                                        Spacer()
                                                                            .frame(height: 4)
                                                                    }
                                                                }
                                                                .frame(width: 44, height: 44)
                                                                .background(
                                                                    RoundedRectangle(cornerRadius: 8)
                                                                        .fill(dayBackground(day, in: month))
                                                                )
                                                            }
                                                            .buttonStyle(.plain)
                                                            .accessibilityLabel(accessibilityLabelForDay(day))
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }
                    }
                    .padding(.vertical)
                }
            }
            .applyScrollEdgeEffect()
        }
        .navigationTitle("Dashboard")
        .navigationBarTitleDisplayMode(.large)
        .task {
            if let repo = appState.repository {
                viewModel.configure(repository: repo)
                await viewModel.loadData()
            }
        }
        .onChange(of: appState.selectedBudgetID) { _ in
            Task {
                if let repo = appState.repository {
                    viewModel.configure(repository: repo)
                    await viewModel.loadData()
                }
            }
        }
        .sheet(isPresented: $viewModel.showDetailSheet) {
            NavigationStack {
                List {
                    if viewModel.selectedDateTransactions.isEmpty {
                        Text("No transactions on this day.")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(viewModel.selectedDateTransactions, id: \.id) { tx in
                            TransactionRow(
                                transaction: tx,
                                accounts: viewModel.accounts,
                                payeesById: viewModel.payeesById,
                                categoriesById: viewModel.categoriesById,
                                currencyCode: appState.currencyCode,
                                onEdit: { _ in },
                                onDelete: { _ in }
                            )
                        }
                    }
                }
                .navigationTitle(viewModel.selectedDateLabel)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") {
                            viewModel.showDetailSheet = false
                        }
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
    }

    private func findAngleForCategory(_ categoryName: String) -> Double? {
        var cumulativeSum = 0.0
        for item in viewModel.currentMonthCategoryBreakdown {
            let prevSum = cumulativeSum
            cumulativeSum += item.amount
            if item.category == categoryName {
                return (prevSum + cumulativeSum) / 2.0
            }
        }
        return nil
    }

    private func formatMoney(_ amount: Int) -> String {
        return CurrencyFormatter.shared.format(amount, currencyCode: appState.currencyCode)
    }

    private func dayBackground(_ day: CalendarDayData, in month: CalendarMonthData) -> Color {
        if day.isPadding || (day.income == 0 && day.expense == 0) {
            return .clear
        }
        
        if day.income > day.expense {
            // Profitable day
            let maxIncome = month.days.filter { !$0.isPadding }.map { $0.income }.max() ?? 1
            let ratio = maxIncome > 0 ? Double(day.income) / Double(maxIncome) : 0.0
            return AppTheme.positive.opacity(0.10 + ratio * 0.30)
        } else {
            // Expense day
            let maxExpense = month.days.filter { !$0.isPadding }.map { $0.expense }.max() ?? 1
            let ratio = maxExpense > 0 ? Double(day.expense) / Double(maxExpense) : 0.0
            return AppTheme.destructive.opacity(0.10 + ratio * 0.30)
        }
    }

    private func accessibilityLabelForDay(_ day: CalendarDayData) -> String {
        if day.income == 0 && day.expense == 0 {
            return "No transactions on day \(day.dayNumber)"
        }
        return "Day \(day.dayNumber): Income \(formatMoney(day.income)), Expenses \(formatMoney(day.expense))"
    }

    private func emptyStateView(title: String, systemImage: String, description: String) -> some View {
        ContentUnavailableView(
            title,
            systemImage: systemImage,
            description: Text(description)
        )
    }
}
