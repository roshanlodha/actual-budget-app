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
                        // Section 1: Summary Stat Cards
                        HStack(spacing: 16) {
                            // Card A: Expenses
                            GlassCard {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Monthly Expenses")
                                        .font(AppTheme.Fonts.subheadline)
                                        .foregroundColor(.secondary)
                                    Text(viewModel.dateRangeLabel)
                                        .font(AppTheme.Fonts.caption)
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
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                            }
                            
                            // Card B: Income
                            GlassCard {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Monthly Income")
                                        .font(AppTheme.Fonts.subheadline)
                                        .foregroundColor(.secondary)
                                    Text(viewModel.dateRangeLabel)
                                        .font(AppTheme.Fonts.caption)
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
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                            }
                        }
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal)
                        .padding(.top, 8)
                        
                        // Section 2: Monthly Expenses Bar Chart
                        GlassCard {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Monthly Expenses")
                                    .font(AppTheme.Fonts.headline)
                                Text("Year to date")
                                    .font(AppTheme.Fonts.caption)
                                    .foregroundColor(.secondary)
                                
                                if viewModel.isLoading {
                                    HStack {
                                        Spacer()
                                        ProgressView()
                                        Spacer()
                                    }
                                    .frame(height: 200)
                                } else if viewModel.perMonthExpenseBreakdown.isEmpty || (viewModel.perMonthExpenseBreakdown.count == 1 && viewModel.perMonthExpenseBreakdown[0].category.isEmpty) {
                                    emptyStateView(title: "No Data", systemImage: "chart.bar.fill", description: "No expenses recorded for this year yet.")
                                        .frame(height: 200)
                                } else {
                                    Chart(viewModel.perMonthExpenseBreakdown) { item in
                                        if !item.category.isEmpty {
                                            BarMark(
                                                x: .value("Month", item.monthLabel),
                                                y: .value("Amount", item.amount)
                                            )
                                            .foregroundStyle(by: .value("Category", item.category))
                                            .accessibilityLabel("\(item.monthLabel) \(item.category) \(formatMoney(Int(item.amount * 100)))")
                                        } else {
                                            BarMark(
                                                x: .value("Month", item.monthLabel),
                                                y: .value("Amount", 0.0)
                                            )
                                            .foregroundStyle(.clear)
                                        }
                                    }
                                    .chartForegroundStyleScale(domain: Array(viewModel.categoryColorMap.keys), range: Array(viewModel.categoryColorMap.values))
                                    .chartXAxis {
                                        AxisMarks(values: .automatic) { value in
                                            AxisValueLabel()
                                        }
                                    }
                                    .chartLegend(.hidden)
                                    .animation(reduceMotion ? nil : .spring(), value: viewModel.perMonthExpenseBreakdown)
                                    .frame(height: 200)
                                    
                                    // Custom scrollable legend that only lists categories with actual expenses
                                    ScrollView(.horizontal, showsIndicators: false) {
                                        HStack(spacing: 12) {
                                            ForEach(Array(viewModel.categoryColorMap.keys.sorted()), id: \.self) { catName in
                                                if viewModel.perMonthExpenseBreakdown.contains(where: { $0.category == catName && $0.amount > 0 }) {
                                                    HStack(spacing: 4) {
                                                        Circle()
                                                            .fill(viewModel.categoryColorMap[catName] ?? .gray)
                                                            .frame(width: 8, height: 8)
                                                        Text(catName)
                                                            .font(AppTheme.Fonts.caption)
                                                            .foregroundColor(.secondary)
                                                    }
                                                }
                                            }
                                        }
                                        .padding(.horizontal, 4)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal)
                        
                        // Section 3: Cash Flow Card
                        GlassCard {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack(alignment: .top) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Cash Flow")
                                            .font(AppTheme.Fonts.headline)
                                        Text(viewModel.dateRangeLabel)
                                            .font(AppTheme.Fonts.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    if viewModel.isLoading {
                                        ProgressView()
                                    } else {
                                        let isNetPositive = viewModel.cashFlowNet >= 0
                                        let sign = isNetPositive ? "+" : ""
                                        Text("\(sign)\(formatMoney(viewModel.cashFlowNet))")
                                            .font(AppTheme.Fonts.body.monospacedDigit())
                                            .foregroundColor(isNetPositive ? AppTheme.positive : AppTheme.destructive)
                                    }
                                }
                                
                                if viewModel.isLoading {
                                    ProgressView()
                                        .frame(height: 80)
                                } else {
                                    VStack(spacing: 8) {
                                        let maxTotal = max(viewModel.ytdExpenseTotal, viewModel.ytdIncomeTotal)
                                        let expenseRatio = maxTotal > 0 ? Double(viewModel.ytdExpenseTotal) / Double(maxTotal) : 0.0
                                        let incomeRatio = maxTotal > 0 ? Double(viewModel.ytdIncomeTotal) / Double(maxTotal) : 0.0
                                        
                                        // Expenses bar
                                        VStack(spacing: 4) {
                                            HStack {
                                                Text("Expenses")
                                                    .font(AppTheme.Fonts.caption)
                                                    .foregroundColor(.secondary)
                                                Spacer()
                                                Text(formatMoney(viewModel.ytdExpenseTotal))
                                                    .font(AppTheme.Fonts.caption)
                                                    .monospacedDigit()
                                            }
                                            GeometryReader { geo in
                                                RoundedRectangle(cornerRadius: 4)
                                                    .fill(AppTheme.destructive)
                                                    .frame(width: geo.size.width * CGFloat(expenseRatio), height: 8)
                                            }
                                            .frame(height: 8)
                                        }
                                        
                                        // Income bar
                                        VStack(spacing: 4) {
                                            HStack {
                                                Text("Income")
                                                    .font(AppTheme.Fonts.caption)
                                                    .foregroundColor(.secondary)
                                                Spacer()
                                                Text(formatMoney(viewModel.ytdIncomeTotal))
                                                    .font(AppTheme.Fonts.caption)
                                                    .monospacedDigit()
                                            }
                                            GeometryReader { geo in
                                                RoundedRectangle(cornerRadius: 4)
                                                    .fill(AppTheme.positive)
                                                    .frame(width: geo.size.width * CGFloat(incomeRatio), height: 8)
                                            }
                                            .frame(height: 8)
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.horizontal)
                        
                        // Section 4: This Month Mini Chart (Pie/Donut)
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
                                                
                                                Text("Selected")
                                                    .font(.system(size: 9, weight: .bold, design: .rounded))
                                                    .foregroundColor(.secondary)
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
                                    
                                    // Interactive Legend Pills
                                    ScrollView(.horizontal, showsIndicators: false) {
                                        HStack(spacing: 8) {
                                            ForEach(viewModel.currentMonthCategoryBreakdown) { item in
                                                let isSelected = selectedCategoryName == item.category
                                                let catColor = viewModel.categoryColorMap[item.category] ?? .gray
                                                
                                                Button {
                                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                                                        if isSelected {
                                                            selectedCategoryName = nil
                                                            selectedAngle = nil
                                                        } else {
                                                            selectedCategoryName = item.category
                                                            selectedAngle = findAngleForCategory(item.category)
                                                        }
                                                    }
                                                } label: {
                                                    HStack(spacing: 6) {
                                                        Circle()
                                                            .fill(catColor)
                                                            .frame(width: 8, height: 8)
                                                        
                                                        Text(item.category)
                                                            .font(AppTheme.Fonts.caption)
                                                            .foregroundColor(isSelected ? .white : .primary)
                                                    }
                                                    .padding(.horizontal, 12)
                                                    .padding(.vertical, 6)
                                                    .background(
                                                        isSelected ? 
                                                        AppTheme.accent : 
                                                        Color.primary.opacity(0.06)
                                                    )
                                                    .clipShape(Capsule())
                                                    .overlay(
                                                        Capsule()
                                                            .stroke(isSelected ? AppTheme.accent : Color.primary.opacity(0.12), lineWidth: 1)
                                                    )
                                                }
                                                .buttonStyle(.plain)
                                            }
                                        }
                                        .padding(.horizontal, 4)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal)
                        
                        // Section 5: Transaction Calendar
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
                                                    Button(action: {
                                                        viewModel.calendarMonthOffset -= 1
                                                        Task {
                                                            await viewModel.loadData()
                                                        }
                                                    }) {
                                                        Image(systemName: "chevron.left")
                                                            .font(.body)
                                                            .foregroundColor(AppTheme.accent)
                                                            .padding(.trailing, 8)
                                                    }
                                                    .buttonStyle(.plain)
                                                    
                                                    Text(month.monthName)
                                                        .font(AppTheme.Fonts.subheadline)
                                                        .bold()
                                                    
                                                    Button(action: {
                                                        viewModel.calendarMonthOffset += 1
                                                        Task {
                                                            await viewModel.loadData()
                                                        }
                                                    }) {
                                                        Image(systemName: "chevron.right")
                                                            .font(.body)
                                                            .foregroundColor(AppTheme.accent)
                                                            .padding(.leading, 8)
                                                    }
                                                    .buttonStyle(.plain)
                                                    
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
