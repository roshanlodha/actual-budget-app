import SwiftUI
import Charts

struct DashboardView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel = DashboardViewModel()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Section 1: Summary Stat Cards
                HStack(spacing: 16) {
                    // Card A: Expenses
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Monthly Expenses")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text(viewModel.dateRangeLabel)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        if viewModel.isLoading {
                            ProgressView()
                                .padding(.top, 4)
                        } else {
                            Text(formatMoney(viewModel.monthlyExpenseAverage))
                                .font(.system(.largeTitle, design: .monospaced))
                                .foregroundColor(Color(red: 0.85, green: 0.35, blue: 0.19))
                                .minimumScaleFactor(0.5)
                                .lineLimit(1)
                                .padding(.top, 4)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color(.systemBackground))
                    .cornerRadius(12)
                    .shadow(radius: 4)
                    
                    // Card B: Income
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Monthly Income")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text(viewModel.dateRangeLabel)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        if viewModel.isLoading {
                            ProgressView()
                                .padding(.top, 4)
                        } else {
                            Text(formatMoney(viewModel.monthlyIncomeAverage))
                                .font(.system(.largeTitle, design: .monospaced))
                                .foregroundColor(.green)
                                .minimumScaleFactor(0.5)
                                .lineLimit(1)
                                .padding(.top, 4)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color(.systemBackground))
                    .cornerRadius(12)
                    .shadow(radius: 4)
                }
                .padding(.horizontal)
                .padding(.top, 8)
                
                // Section 2: Monthly Expenses Bar Chart
                VStack(alignment: .leading, spacing: 12) {
                    Text("Monthly Expenses")
                        .font(.headline)
                    Text("Year to date")
                        .font(.caption)
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
                        .animation(reduceMotion ? nil : .spring(), value: viewModel.perMonthExpenseBreakdown)
                        .frame(height: 200)
                    }
                }
                .padding()
                .background(Color(.systemBackground))
                .cornerRadius(12)
                .shadow(radius: 4)
                .padding(.horizontal)
                
                // Section 3: Cash Flow Card
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Cash Flow")
                                .font(.headline)
                            Text(viewModel.dateRangeLabel)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        if viewModel.isLoading {
                            ProgressView()
                        } else {
                            let isNetPositive = viewModel.cashFlowNet >= 0
                            let sign = isNetPositive ? "+" : ""
                            Text("\(sign)\(formatMoney(viewModel.cashFlowNet))")
                                .font(.system(.body, design: .monospaced))
                                .foregroundColor(isNetPositive ? .green : .red)
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
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Text(formatMoney(viewModel.ytdExpenseTotal))
                                        .font(.caption)
                                        .monospacedDigit()
                                }
                                GeometryReader { geo in
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color(red: 0.85, green: 0.35, blue: 0.19))
                                        .frame(width: geo.size.width * CGFloat(expenseRatio), height: 8)
                                }
                                .frame(height: 8)
                            }
                            
                            // Income bar
                            VStack(spacing: 4) {
                                HStack {
                                    Text("Income")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Text(formatMoney(viewModel.ytdIncomeTotal))
                                        .font(.caption)
                                        .monospacedDigit()
                                }
                                GeometryReader { geo in
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color.green)
                                        .frame(width: geo.size.width * CGFloat(incomeRatio), height: 8)
                                }
                                .frame(height: 8)
                            }
                        }
                    }
                }
                .padding()
                .background(Color(.systemBackground))
                .cornerRadius(12)
                .shadow(radius: 4)
                .padding(.horizontal)
                
                // Section 4: This Month Mini Chart
                VStack(alignment: .leading, spacing: 12) {
                    Text("Month Expenses")
                        .font(.subheadline)
                        .bold()
                    Text("This month")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if viewModel.isLoading {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                        .frame(height: 100)
                    } else if viewModel.currentMonthCategoryBreakdown.isEmpty {
                        emptyStateView(title: "No Expenses", systemImage: "chart.pie", description: "No expenses recorded this month.")
                            .frame(height: 100)
                    } else {
                        Chart(viewModel.currentMonthCategoryBreakdown) { item in
                            BarMark(
                                x: .value("Category", item.category),
                                y: .value("Amount", item.amount)
                            )
                            .foregroundStyle(by: .value("Category", item.category))
                            .accessibilityLabel("\(item.category) \(formatMoney(Int(item.amount * 100)))")
                        }
                        .chartForegroundStyleScale(domain: Array(viewModel.categoryColorMap.keys), range: Array(viewModel.categoryColorMap.values))
                        .chartXScale(domain: viewModel.currentMonthCategoryBreakdown.map { $0.category })
                        .chartLegend(.hidden)
                        .animation(reduceMotion ? nil : .spring(), value: viewModel.currentMonthCategoryBreakdown)
                        .frame(height: 100)
                    }
                }
                .padding()
                .background(Color(.systemBackground))
                .cornerRadius(12)
                .shadow(radius: 4)
                .padding(.horizontal)
                
                // Section 5: Transaction Calendar
                VStack(alignment: .leading, spacing: 12) {
                    Text("Transaction Calendar")
                        .font(.headline)
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
                                VStack(alignment: .leading, spacing: 12) {
                                    // Header
                                    HStack {
                                        Text(month.monthName)
                                            .font(.subheadline)
                                            .bold()
                                        Spacer()
                                        HStack(spacing: 8) {
                                            Text("↑ \(formatMoney(month.totalIncome))")
                                                .foregroundColor(.green)
                                            Text("↓ \(formatMoney(month.totalExpense))")
                                                .foregroundColor(.red)
                                        }
                                        .font(.caption)
                                        .monospacedDigit()
                                    }
                                    
                                    // Weekday headers
                                    let weekdayHeaders = ["S", "M", "T", "W", "T", "F", "S"]
                                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 8) {
                                        ForEach(weekdayHeaders, id: \.self) { day in
                                            Text(day)
                                                .font(.caption2)
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
                                                            .font(.body)
                                                            .foregroundColor(.primary)
                                                        
                                                        if day.income > 0 || day.expense > 0 {
                                                            let isNetIncome = day.income > day.expense
                                                            RoundedRectangle(cornerRadius: 2)
                                                                .fill(isNetIncome ? Color.green : Color(red: 0.85, green: 0.35, blue: 0.19))
                                                                .frame(width: 24, height: 4)
                                                        } else {
                                                            Spacer()
                                                                .frame(height: 4)
                                                        }
                                                    }
                                                    .frame(width: 44, height: 44)
                                                    .background(
                                                        RoundedRectangle(cornerRadius: 8)
                                                            .fill(dayBackground(day))
                                                    )
                                                }
                                                .buttonStyle(.plain)
                                                .accessibilityLabel(accessibilityLabelForDay(day))
                                            }
                                        }
                                    }
                                }
                                .padding()
                                .background(Color(.systemBackground))
                                .cornerRadius(12)
                                .shadow(radius: 4)
                            }
                        }
                        .padding(.horizontal)
                    }
                }
            }
            .padding(.vertical)
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

    private func formatMoney(_ amount: Int) -> String {
        return CurrencyFormatter.shared.format(amount, currencyCode: appState.currencyCode)
    }

    private func dayBackground(_ day: CalendarDayData) -> Color {
        if day.income == 0 && day.expense == 0 {
            return .clear
        }
        return day.income > day.expense ? Color.green.opacity(0.12) : Color.red.opacity(0.12)
    }

    private func accessibilityLabelForDay(_ day: CalendarDayData) -> String {
        if day.income == 0 && day.expense == 0 {
            return "No transactions on day \(day.dayNumber)"
        }
        return "Day \(day.dayNumber): Income \(formatMoney(day.income)), Expenses \(formatMoney(day.expense))"
    }

    @ViewBuilder
    private func emptyStateView(title: String, systemImage: String, description: String) -> some View {
        if #available(iOS 17.0, *) {
            ContentUnavailableView(
                title,
                systemImage: systemImage,
                description: Text(description)
            )
        } else {
            VStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.title)
                    .foregroundColor(.secondary)
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
        }
    }
}
