import SwiftUI
import UniformTypeIdentifiers

struct CSVPreviewTransaction: Identifiable {
    let id = UUID()
    var dateString: String // yyyy-MM-dd
    var rawDate: String
    var payeeName: String
    var payeeId: String?
    var categoryId: String?
    var categoryName: String?
    var amount: Int // in cents
    var notes: String?
    var isSelected: Bool = true
    var isDuplicate: Bool = false
}

struct CSVImportView: View {
    let account: Account
    var onImport: () -> Void
    
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    
    @State private var step = 1
    @State private var csvText = ""
    @State private var importedFileName: String?
    
    // CSV configuration
    @State private var delimiter = ","
    @State private var hasHeader = true
    @State private var skipStartLines = 0
    @State private var skipEndLines = 0
    
    // Field mappings
    @State private var dateColumn = ""
    @State private var payeeColumn = ""
    @State private var notesColumn = ""
    @State private var categoryColumn = "__auto__"
    @State private var amountColumn = ""
    
    // Split amount options
    @State private var splitInflowOutflow = false
    @State private var inflowColumn = ""
    @State private var outflowColumn = ""
    
    // Date formatting & Amount manipulation
    @State private var dateFormat = "MM/dd/yy"
    @State private var flipAmount = false
    @State private var multiplyAmount = false
    @State private var multiplierString = "1.0"
    
    // Final options
    @State private var clearTransactions = false
    @State private var mergeWithExisting = true
    
    // State lists
    @State private var categories: [Category] = []
    @State private var payees: [Payee] = []
    @State private var existingTransactions: [Transaction] = []
    @State private var previewTransactions: [CSVPreviewTransaction] = []
    
    // UI states
    @State private var errorMessage: String?
    @State private var showingFileImporter = false
    @State private var isImporting = false
    @State private var importProgress: Double = 0.0
    @State private var importStatusText = ""
    
    private var repository: BudgetRepository {
        guard let repo = appState.repository else { fatalError("Repository unavailable") }
        return repo
    }
    
    private var parsedHeaders: [String] {
        let rows = CSVParser.parse(
            text: csvText,
            delimiter: delimiter.first ?? ",",
            skipStartLines: skipStartLines,
            skipEndLines: skipEndLines
        )
        guard !rows.isEmpty else { return [] }
        if hasHeader {
            return rows.first ?? []
        } else {
            return (1...rows[0].count).map { "Column \($0)" }
        }
    }
    
    // Samples
    private let bankSampleText = """
Details,Posting Date,Description,Amount,Type,Balance,Check or Slip #
DEBIT,5/21/26,Rent,-2244.66,MISC_DEBIT,50,
"""
    
    private let creditCardSampleText = """
Transaction Date,Post Date,Description,Category,Type,Amount,Memo
5/25/26,5/27/26,United,Travel,Sale,-38.92,
5/27/26,5/27/26,Woot,Shopping,Sale,-56.29,
5/24/26,5/25/26,Amazon,Shopping,Sale,-29.48,
5/25/26,5/25/26,Amazon,Shopping,Sale,-35.39,
5/21/26,5/24/26,United,Travel,Sale,-5.6,
5/23/26,5/24/26,Grocery Store,Groceries,Sale,-84.01,
"""
    
    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                
                VStack(spacing: 0) {
                    stepIndicator
                        .padding(.vertical, 12)
                    
                    Divider()
                        .background(Color.white.opacity(0.1))
                    
                    ScrollView {
                        VStack(spacing: 20) {
                            switch step {
                            case 1:
                                sourceSelectionStep
                            case 2:
                                mappingStep
                            case 3:
                                previewStep
                            default:
                                EmptyView()
                            }
                        }
                        .padding()
                    }
                    
                    Divider()
                        .background(Color.white.opacity(0.1))
                    
                    navigationBarBottom
                        .padding()
                }
                
                if isImporting {
                    Color.black.opacity(0.6).ignoresSafeArea()
                    VStack(spacing: 20) {
                        ProgressView(value: importProgress, total: 1.0)
                            .progressViewStyle(.linear)
                            .tint(AppTheme.accent)
                        Text(importStatusText)
                            .font(AppTheme.Fonts.headline)
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                    }
                    .padding(24)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(UIColor.systemBackground).opacity(0.95))
                            .shadow(radius: 20)
                    )
                    .padding(40)
                }
            }
            .navigationTitle("Import CSV")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task {
                await loadMetaData()
            }
            .alert("Error", isPresented: .constant(errorMessage != nil)) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
            .fileImporter(
                isPresented: $showingFileImporter,
                allowedContentTypes: [.commaSeparatedText, .text, .plainText, .item]
            ) { result in
                handleFileImport(result: result)
            }
            .onChange(of: dateColumn) { oldValue, newValue in
                detectDateFormat(columnName: newValue)
            }
        }
        .tint(AppTheme.accent)
    }
    
    // MARK: - Step indicator
    private var stepIndicator: some View {
        HStack(spacing: 8) {
            stepBadge(num: 1, label: "Source")
            lineConnector(active: step > 1)
            stepBadge(num: 2, label: "Map")
            lineConnector(active: step > 2)
            stepBadge(num: 3, label: "Preview")
        }
        .padding(.horizontal)
    }
    
    private func stepBadge(num: Int, label: String) -> some View {
        HStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(step == num ? AppTheme.accent : (step > num ? AppTheme.positive : Color.white.opacity(0.1)))
                    .frame(width: 24, height: 24)
                
                if step > num {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.black)
                } else {
                    Text("\(num)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(step == num ? .black : .primary)
                }
            }
            Text(label)
                .font(AppTheme.Fonts.caption)
                .foregroundColor(step >= num ? .primary : .secondary)
        }
    }
    
    private func lineConnector(active: Bool) -> some View {
        Rectangle()
            .fill(active ? AppTheme.accent : Color.white.opacity(0.1))
            .frame(height: 2)
            .frame(maxWidth: .infinity)
    }
    
    // MARK: - Navigation bottom
    private var navigationBarBottom: some View {
        HStack {
            if step > 1 {
                Button {
                    withAnimation { step -= 1 }
                } label: {
                    Text("Back")
                        .font(AppTheme.Fonts.headline)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 24)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(10)
                }
                .buttonStyle(.plain)
            }
            
            Spacer()
            
            if step < 3 {
                Button {
                    if step == 1 {
                        parseCSV()
                        autoMapColumns()
                        withAnimation { step = 2 }
                    } else {
                        Task {
                            if categories.isEmpty {
                                await loadMetaData()
                            }
                            await MainActor.run {
                                generatePreview()
                                withAnimation { step = 3 }
                            }
                        }
                    }
                } label: {
                    Text("Next")
                        .font(AppTheme.Fonts.headline)
                        .foregroundColor(.black)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 32)
                        .background(csvText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.gray : AppTheme.accent)
                        .cornerRadius(10)
                }
                .disabled(csvText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .buttonStyle(.plain)
            } else {
                Button {
                    Task { await performImport() }
                } label: {
                    let selectedCount = previewTransactions.filter { $0.isSelected }.count
                    Text("Import \(selectedCount) Transaction\(selectedCount == 1 ? "" : "s")")
                        .font(AppTheme.Fonts.headline)
                        .foregroundColor(.black)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 24)
                        .background(selectedCount == 0 ? Color.gray : AppTheme.accent)
                        .cornerRadius(10)
                }
                .disabled(previewTransactions.filter { $0.isSelected }.count == 0)
                .buttonStyle(.plain)
            }
        }
    }
    
    // MARK: - Step 1 View
    private var sourceSelectionStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Choose CSV Data Source")
                .font(AppTheme.Fonts.title)
                .foregroundColor(.primary)
            
            GlassCard {
                VStack(spacing: 12) {
                    Image(systemName: "doc.text.fill")
                        .font(.system(size: 40))
                        .foregroundColor(AppTheme.accent)
                    
                    if let filename = importedFileName {
                        Text(filename)
                            .font(AppTheme.Fonts.headline)
                            .foregroundColor(.primary)
                    }
                    
                    Button {
                        showingFileImporter = true
                    } label: {
                        Text(importedFileName == nil ? "Choose CSV File..." : "Choose Different File...")
                            .font(AppTheme.Fonts.body)
                            .bold()
                            .padding(.vertical, 10)
                            .padding(.horizontal, 20)
                            .background(AppTheme.accentSoft)
                            .foregroundColor(AppTheme.accent)
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            
            HStack {
                Rectangle().fill(Color.white.opacity(0.1)).frame(height: 1)
                Text("OR").font(AppTheme.Fonts.footnote).foregroundColor(.secondary)
                Rectangle().fill(Color.white.opacity(0.1)).frame(height: 1)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Paste CSV Content directly:")
                    .font(AppTheme.Fonts.headline)
                    .foregroundColor(.primary)
                
                TextEditor(text: $csvText)
                    .font(.system(.body, design: .monospaced))
                    .frame(height: 150)
                    .padding(4)
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.white.opacity(0.15), lineWidth: 1)
                    )
            }
            
            HStack {
                Rectangle().fill(Color.white.opacity(0.1)).frame(height: 1)
                Text("OR").font(AppTheme.Fonts.footnote).foregroundColor(.secondary)
                Rectangle().fill(Color.white.opacity(0.1)).frame(height: 1)
            }
            
            VStack(alignment: .leading, spacing: 10) {
                Text("Try Sample Data (Demo)")
                    .font(AppTheme.Fonts.headline)
                    .foregroundColor(.primary)
                
                HStack(spacing: 12) {
                    Button {
                        csvText = bankSampleText
                        importedFileName = "bank_ex.CSV"
                        parseCSV()
                        autoMapColumns()
                        withAnimation { step = 2 }
                    } label: {
                        HStack {
                            Image(systemName: "building.2.fill")
                            Text("Bank Sample")
                        }
                        .font(AppTheme.Fonts.body)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 16)
                        .background(Color.white.opacity(0.08))
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    
                    Button {
                        csvText = creditCardSampleText
                        importedFileName = "creditcard_ex.CSV"
                        parseCSV()
                        autoMapColumns()
                        withAnimation { step = 2 }
                    } label: {
                        HStack {
                            Image(systemName: "creditcard.fill")
                            Text("Credit Card Sample")
                        }
                        .font(AppTheme.Fonts.body)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 16)
                        .background(Color.white.opacity(0.08))
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
    
    // MARK: - Step 2 View
    private var mappingStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Parser Settings & Mappings")
                .font(AppTheme.Fonts.title)
                .foregroundColor(.primary)
            
            VStack(alignment: .leading, spacing: 12) {
                Text("CSV Format & Settings")
                    .font(AppTheme.Fonts.subtitle)
                    .foregroundColor(AppTheme.accent)
                
                GlassCard {
                    VStack(spacing: 14) {
                        HStack {
                            Text("Delimiter")
                            Spacer()
                            Picker("Delimiter", selection: $delimiter) {
                                Text("Comma ( , )").tag(",")
                                Text("Semicolon ( ; )").tag(";")
                                Text("Tab ( \\t )").tag("\t")
                            }
                            .pickerStyle(.menu)
                        }
                        
                        Toggle("First row is header", isOn: $hasHeader)
                            .toggleStyle(SwitchToggleStyle(tint: AppTheme.accent))
                        
                        HStack {
                            Text("Skip start lines")
                            Spacer()
                            Stepper("\(skipStartLines)", value: $skipStartLines, in: 0...100)
                        }
                        
                        HStack {
                            Text("Skip end lines")
                            Spacer()
                            Stepper("\(skipEndLines)", value: $skipEndLines, in: 0...100)
                        }
                    }
                }
            }
            
            VStack(alignment: .leading, spacing: 12) {
                Text("Field Column Mappings")
                    .font(AppTheme.Fonts.subtitle)
                    .foregroundColor(AppTheme.accent)
                
                GlassCard {
                    VStack(spacing: 14) {
                        columnPicker(label: "Date Column *", selection: $dateColumn)
                        columnPicker(label: "Payee Column *", selection: $payeeColumn)
                        columnPicker(label: "Notes Column", selection: $notesColumn, isOptional: true)
                        categoryColumnPicker
                        
                        Toggle("Split Inflow/Outflow Columns", isOn: $splitInflowOutflow)
                            .toggleStyle(SwitchToggleStyle(tint: AppTheme.accent))
                        
                        if splitInflowOutflow {
                            columnPicker(label: "Inflow Column *", selection: $inflowColumn)
                            columnPicker(label: "Outflow Column *", selection: $outflowColumn)
                        } else {
                            columnPicker(label: "Amount Column *", selection: $amountColumn)
                        }
                    }
                }
            }
            
            VStack(alignment: .leading, spacing: 12) {
                Text("Parsing & Amount Options")
                    .font(AppTheme.Fonts.subtitle)
                    .foregroundColor(AppTheme.accent)
                
                GlassCard {
                    VStack(spacing: 14) {
                        HStack {
                            Text("Date Format")
                            Spacer()
                            Picker("Date Format", selection: $dateFormat) {
                                Text("MM/DD/YY (e.g. 5/21/26)").tag("MM/dd/yy")
                                Text("MM/DD/YYYY").tag("MM/dd/yyyy")
                                Text("DD/MM/YY").tag("dd/MM/yy")
                                Text("DD/MM/YYYY").tag("dd/MM/yyyy")
                                Text("YYYY-MM-DD").tag("yyyy-MM-dd")
                                Text("YYYY/MM/DD").tag("yyyy/MM/dd")
                            }
                            .pickerStyle(.menu)
                        }
                        
                        Toggle("Flip amount signs", isOn: $flipAmount)
                            .toggleStyle(SwitchToggleStyle(tint: AppTheme.accent))
                        
                        Toggle("Multiply amount", isOn: $multiplyAmount)
                            .toggleStyle(SwitchToggleStyle(tint: AppTheme.accent))
                        
                        if multiplyAmount {
                            HStack {
                                Text("Multiplier")
                                Spacer()
                                TextField("1.0", text: $multiplierString)
                                    .keyboardType(.decimalPad)
                                    .frame(width: 80)
                                    .multilineTextAlignment(.trailing)
                                    .textFieldStyle(.roundedBorder)
                            }
                        }
                    }
                }
            }
        }
    }
    
    /// Special picker for the Category field with Auto as the default option.
    private var categoryColumnPicker: some View {
        HStack {
            Text("Category Column")
            Spacer()
            Picker("Category Column", selection: $categoryColumn) {
                Text("Auto").tag("__auto__")
                ForEach(parsedHeaders, id: \.self) { header in
                    Text(header).tag(header)
                }
            }
            .pickerStyle(.menu)
        }
    }
    
    private func columnPicker(label: String, selection: Binding<String>, isOptional: Bool = false) -> some View {
        HStack {
            Text(label)
            Spacer()
            Picker(label, selection: selection) {
                if isOptional {
                    Text("None").tag("")
                } else if selection.wrappedValue.isEmpty {
                    Text("Select...").tag("")
                }
                ForEach(parsedHeaders, id: \.self) { header in
                    Text(header).tag(header)
                }
            }
            .pickerStyle(.menu)
        }
    }
    
    // MARK: - Step 3 View
    private var previewStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Preview Transactions")
                .font(AppTheme.Fonts.title)
                .foregroundColor(.primary)
            
            Text("Verify fields. Uncheck any items you do not wish to import. Yellow highlights indicate detected duplicates.")
                .font(AppTheme.Fonts.body)
                .foregroundColor(.secondary)
            
            VStack(alignment: .leading, spacing: 12) {
                Text("Import Settings")
                    .font(AppTheme.Fonts.subtitle)
                    .foregroundColor(AppTheme.accent)
                
                GlassCard {
                    VStack(spacing: 12) {
                        Toggle("Merge & Deduplicate", isOn: $mergeWithExisting)
                            .toggleStyle(SwitchToggleStyle(tint: AppTheme.accent))
                        
                        Toggle("Clear existing transactions first", isOn: $clearTransactions)
                            .toggleStyle(SwitchToggleStyle(tint: AppTheme.accent))
                    }
                }
            }
            
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Transactions (\(previewTransactions.count) found)")
                        .font(AppTheme.Fonts.subtitle)
                        .foregroundColor(AppTheme.accent)
                    Spacer()
                    Button(allSelected ? "Deselect All" : "Select All") {
                        toggleSelectAll()
                    }
                    .font(AppTheme.Fonts.footnote)
                    .foregroundColor(AppTheme.accent)
                }
                
                if previewTransactions.isEmpty {
                    Text("No transactions parsed. Check mapping settings.")
                        .font(AppTheme.Fonts.body)
                        .foregroundColor(.yellow)
                        .padding()
                } else {
                    VStack(spacing: 12) {
                        ForEach($previewTransactions) { $tx in
                            GlassCard {
                                HStack(alignment: .center, spacing: 12) {
                                    Toggle("", isOn: $tx.isSelected)
                                        .toggleStyle(SwitchToggleStyle(tint: AppTheme.accent))
                                        .labelsHidden()
                                    
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack(alignment: .firstTextBaseline) {
                                            Text(tx.payeeName)
                                                .font(AppTheme.Fonts.headline)
                                                .foregroundColor(.primary)
                                            if let catName = tx.categoryName {
                                                Text(catName)
                                                    .font(AppTheme.Fonts.caption)
                                                    .padding(.horizontal, 6)
                                                    .padding(.vertical, 2)
                                                    .background(AppTheme.accentSoft)
                                                    .foregroundColor(AppTheme.accent)
                                                    .cornerRadius(4)
                                            }
                                        }
                                        
                                        if let notes = tx.notes {
                                            Text(notes)
                                                .font(AppTheme.Fonts.footnote)
                                                .foregroundColor(.secondary)
                                        }
                                        
                                        HStack(spacing: 6) {
                                            Text(formatDate(tx.dateString))
                                                .font(AppTheme.Fonts.footnote)
                                                .foregroundColor(.secondary)
                                            if tx.rawDate != tx.dateString {
                                                Text("(\(tx.rawDate))")
                                                    .font(AppTheme.Fonts.caption)
                                                    .foregroundColor(.secondary.opacity(0.6))
                                            }
                                            
                                            if tx.isDuplicate {
                                                Text("Duplicate")
                                                    .font(AppTheme.Fonts.caption)
                                                    .padding(.horizontal, 6)
                                                    .padding(.vertical, 1)
                                                    .background(Color.yellow.opacity(0.2))
                                                    .foregroundColor(.yellow)
                                                    .cornerRadius(4)
                                            }
                                        }
                                    }
                                    
                                    Spacer()
                                    
                                    Text(formattedAmount(tx.amount))
                                        .font(AppTheme.Fonts.body.monospacedDigit())
                                        .foregroundColor(tx.amount >= 0 ? AppTheme.positive : .primary)
                                }
                            }
                            .overlay(
                                RoundedRectangle(cornerRadius: 20)
                                    .stroke(tx.isDuplicate ? Color.yellow.opacity(0.3) : Color.clear, lineWidth: 1.5)
                            )
                        }
                    }
                }
            }
        }
    }
    
    private var allSelected: Bool {
        previewTransactions.allSatisfy { $0.isSelected }
    }
    
    private func toggleSelectAll() {
        let target = !allSelected
        for idx in 0..<previewTransactions.count {
            previewTransactions[idx].isSelected = target
        }
    }
    
    // MARK: - CSV Parsing logic
    private func parseCSV() {
        // Parsing is done automatically via computed property `parsedHeaders`
        // We trigger mapping setup when csvText parsed
    }
    
    private func autoMapColumns() {
        let headers = parsedHeaders
        guard !headers.isEmpty else { return }
        
        dateColumn = ""
        payeeColumn = ""
        notesColumn = ""
        categoryColumn = "__auto__"  // Always default to Auto
        amountColumn = ""
        inflowColumn = ""
        outflowColumn = ""
        splitInflowOutflow = false
        
        for h in headers {
            let clean = h.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if clean.contains("date") {
                if dateColumn.isEmpty || clean == "post date" || clean == "posting date" {
                    dateColumn = h
                }
            } else if clean.contains("desc") || clean.contains("payee") {
                payeeColumn = h
            } else if clean.contains("memo") || clean.contains("note") || clean.contains("details") {
                notesColumn = h
            } else if clean.contains("amount") {  // category column intentionally NOT auto-mapped
                amountColumn = h
            } else if clean.contains("inflow") {
                inflowColumn = h
                splitInflowOutflow = true
            } else if clean.contains("outflow") {
                outflowColumn = h
                splitInflowOutflow = true
            }
        }
        
        // Fallback defaults
        if dateColumn.isEmpty && !headers.isEmpty { dateColumn = headers[0] }
        if payeeColumn.isEmpty && headers.count > 1 { payeeColumn = headers[1] }
        if amountColumn.isEmpty && !splitInflowOutflow {
            if headers.count > 2 {
                // Look for columns containing amount or number
                if let found = headers.first(where: { $0.lowercased().contains("amt") || $0.lowercased().contains("bal") }) {
                    amountColumn = found
                } else {
                    amountColumn = headers[headers.count - 1]
                }
            }
        }
    }
    
    private func generatePreview() {
        let rows = CSVParser.parse(
            text: csvText,
            delimiter: delimiter.first ?? ",",
            skipStartLines: skipStartLines,
            skipEndLines: skipEndLines
        )
        guard !rows.isEmpty else {
            previewTransactions = []
            return
        }
        
        var dataRows = rows
        if hasHeader && !dataRows.isEmpty {
            dataRows.removeFirst()
        }
        
        let headers = parsedHeaders
        let dateIdx = headers.firstIndex(of: dateColumn) ?? -1
        let payeeIdx = headers.firstIndex(of: payeeColumn) ?? -1
        let notesIdx = notesColumn.isEmpty ? -1 : (headers.firstIndex(of: notesColumn) ?? -1)
        // "__auto__" means LLM at import time — no column index needed
        let categoryIdx = (categoryColumn.isEmpty || categoryColumn == "__auto__") ? -1 : (headers.firstIndex(of: categoryColumn) ?? -1)
        
        let amtIdx = amountColumn.isEmpty ? -1 : (headers.firstIndex(of: amountColumn) ?? -1)
        let inflowIdx = inflowColumn.isEmpty ? -1 : (headers.firstIndex(of: inflowColumn) ?? -1)
        let outflowIdx = outflowColumn.isEmpty ? -1 : (headers.firstIndex(of: outflowColumn) ?? -1)
        
        var list: [CSVPreviewTransaction] = []
        let doubleMultiplier = multiplyAmount ? (Double(multiplierString) ?? 1.0) : 1.0
        
        for row in dataRows {
            guard dateIdx < row.count, payeeIdx < row.count else { continue }
            let rawDateStr = row[dateIdx]
            let payeeStr = row[payeeIdx]
            
            // Date Parsing
            let parsedDate = parseDateString(rawDateStr, format: dateFormat)
            let finalDateStr = formatDateToRepoString(parsedDate ?? Date())
            
            // Payee Matching
            var matchedPayeeId: String? = nil
            if let matched = payees.first(where: { $0.name.localizedCaseInsensitiveCompare(payeeStr) == .orderedSame }) {
                matchedPayeeId = matched.id
            }
            
            // Category Matching
            var matchedCategoryId: String? = nil
            var matchedCategoryName: String? = nil
            if categoryIdx >= 0 && categoryIdx < row.count {
                let rowCatName = row[categoryIdx]
                if !rowCatName.isEmpty {
                    if let matchedCat = categories.first(where: { $0.name.localizedCaseInsensitiveCompare(rowCatName) == .orderedSame }) {
                        matchedCategoryId = matchedCat.id
                        matchedCategoryName = matchedCat.name
                    } else {
                        matchedCategoryName = rowCatName
                    }
                }
            }
            
            // Notes
            var noteStr: String? = nil
            if notesIdx >= 0 && notesIdx < row.count {
                let cell = row[notesIdx]
                noteStr = cell.isEmpty ? nil : cell
            }
            
            // Amount Parsing
            var doubleAmount = 0.0
            if splitInflowOutflow {
                let inflowVal = inflowIdx >= 0 && inflowIdx < row.count ? parseDouble(row[inflowIdx]) : 0.0
                let outflowVal = outflowIdx >= 0 && outflowIdx < row.count ? parseDouble(row[outflowIdx]) : 0.0
                if inflowVal > 0 {
                    doubleAmount = inflowVal
                } else if outflowVal > 0 {
                    doubleAmount = -outflowVal
                }
            } else if amtIdx >= 0 && amtIdx < row.count {
                doubleAmount = parseDouble(row[amtIdx])
            }
            
            if flipAmount {
                doubleAmount = -doubleAmount
            }
            doubleAmount *= doubleMultiplier
            
            let amountCents = Int(round(doubleAmount * 100))
            
            // Duplicate Check
            let isDup = existingTransactions.contains { ext in
                ext.date == finalDateStr &&
                ext.amount == amountCents &&
                (ext.payee_name?.localizedCaseInsensitiveCompare(payeeStr) == .orderedSame ||
                 (ext.payee != nil && payees.first(where: { $0.id == ext.payee })?.name.localizedCaseInsensitiveCompare(payeeStr) == .orderedSame))
            }
            
            list.append(CSVPreviewTransaction(
                dateString: finalDateStr,
                rawDate: rawDateStr,
                payeeName: payeeStr,
                payeeId: matchedPayeeId,
                categoryId: matchedCategoryId,
                categoryName: matchedCategoryName,
                amount: amountCents,
                notes: noteStr,
                isSelected: !isDup, // auto uncheck duplicates
                isDuplicate: isDup
            ))
        }
        
        self.previewTransactions = list
    }
    
    // MARK: - Core DB helpers
    private func loadMetaData() async {
        do {
            let catsList = try await repository.fetchCategories()
            let payeesList = try await repository.fetchPayees()
            let txs = try await repository.fetchTransactions(accountId: account.id, since: nil)
            
            await MainActor.run {
                self.categories = catsList
                self.payees = payeesList
                self.existingTransactions = txs
            }
        } catch {
            await MainActor.run { errorMessage = error.localizedDescription }
        }
    }
    
    private func performImport() async {
        await MainActor.run {
            isImporting = true
            importProgress = 0.0
            importStatusText = "Preparing import..."
        }
        
        do {
            if categories.isEmpty {
                await loadMetaData()
            }
            let toImport = previewTransactions.filter { $0.isSelected }
            let total = Double(toImport.count)
            
            if clearTransactions {
                // Delete all transactions from the current account
                let toDelete = existingTransactions.filter { $0.account == account.id }
                for tx in toDelete {
                    if let txId = tx.id {
                        try await repository.deleteTransaction(id: txId)
                    }
                }
            }
            
            for (index, pTx) in toImport.enumerated() {
                await MainActor.run {
                    importStatusText = "Processing \(pTx.payeeName)..."
                }
                
                var finalPayeeId = pTx.payeeId
                var finalPayeeName: String? = pTx.payeeName
                
                // If it exists in DB, use payee ID
                if let pid = finalPayeeId {
                    finalPayeeName = nil
                } else {
                    // Try to match or create payee if not exists
                    if let pid = payees.first(where: { $0.name.localizedCaseInsensitiveCompare(pTx.payeeName) == .orderedSame })?.id {
                        finalPayeeId = pid
                        finalPayeeName = nil
                    }
                }
                
                var finalCategoryId = pTx.categoryId
                if finalCategoryId == nil {
                    let noteText = pTx.notes ?? ""
                    if let detectedId = await AutoClassifier.shared.autoCategorize(payeeName: pTx.payeeName, notes: noteText, categories: categories) {
                        finalCategoryId = detectedId
                        let catName = categories.first(where: { $0.id == detectedId })?.name ?? "Unknown"
                        await MainActor.run {
                            importStatusText = "Categorized '\(pTx.payeeName)' as '\(catName)'"
                        }
                    } else {
                        if let otherCat = categories.first(where: { $0.name.localizedCaseInsensitiveCompare("Other") == .orderedSame }) {
                            finalCategoryId = otherCat.id
                        }
                        await MainActor.run {
                            importStatusText = "Categorized '\(pTx.payeeName)' as 'Other'"
                        }
                    }
                } else {
                    await MainActor.run {
                        importStatusText = "Importing \(pTx.payeeName)..."
                    }
                }
                
                let tx = Transaction(
                    id: UUID().uuidString,
                    account: account.id,
                    date: pTx.dateString,
                    amount: pTx.amount,
                    payee: finalPayeeId,
                    payee_name: finalPayeeName,
                    imported_payee: pTx.payeeName,
                    category: finalCategoryId,
                    notes: pTx.notes,
                    imported_id: "csv_import_\(UUID().uuidString.prefix(8))",
                    transfer_id: nil,
                    cleared: true
                )
                try await repository.createTransaction(tx)
                
                await MainActor.run {
                    importProgress = Double(index + 1) / total
                }
            }
            
            try? await Task.sleep(nanoseconds: 500_000_000)
            await MainActor.run {
                onImport()
                dismiss()
            }
        } catch {
            await MainActor.run { 
                isImporting = false
                errorMessage = error.localizedDescription 
            }
        }
    }
    
    private func detectDateFormat(columnName: String) {
        guard !columnName.isEmpty else { return }
        let rows = CSVParser.parse(
            text: csvText,
            delimiter: delimiter.first ?? ",",
            skipStartLines: skipStartLines,
            skipEndLines: skipEndLines
        )
        var dataRows = rows
        if hasHeader && !dataRows.isEmpty {
            dataRows.removeFirst()
        }
        guard let firstDataRow = dataRows.first,
              let dateIdx = parsedHeaders.firstIndex(of: columnName),
              dateIdx < firstDataRow.count else { return }
        
        let sampleDateStr = firstDataRow[dateIdx]
        autoDetectDateFormat(dateString: sampleDateStr)
    }
    
    private func autoDetectDateFormat(dateString: String) {
        let formats = [
            "MM/dd/yy",
            "MM/dd/yyyy",
            "dd/MM/yy",
            "dd/MM/yyyy",
            "yyyy-MM-dd",
            "yyyy/MM/dd"
        ]
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        for format in formats {
            f.dateFormat = format
            if f.date(from: dateString.trimmingCharacters(in: .whitespacesAndNewlines)) != nil {
                self.dateFormat = format
                return
            }
        }
    }
    
    // MARK: - Utility formatting helpers
    private func parseDateString(_ str: String, format: String) -> Date? {
        let f = DateFormatter()
        f.dateFormat = format
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.date(from: str)
    }
    
    private func formatDateToRepoString(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
    
    private func formatDate(_ dateStr: String) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: dateStr) else { return dateStr }
        f.dateStyle = .medium
        return f.string(from: d)
    }
    
    private func parseDouble(_ val: String) -> Double {
        let cleaned = val.replacingOccurrences(of: "$", with: "")
                         .replacingOccurrences(of: ",", with: "")
                         .trimmingCharacters(in: .whitespacesAndNewlines)
        return Double(cleaned) ?? 0.0
    }
    
    private func formattedAmount(_ amount: Int) -> String {
        return CurrencyFormatter.shared.formatSigned(amount, currencyCode: appState.currencyCode)
    }
    
    private func handleFileImport(result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            guard url.startAccessingSecurityScopedResource() else {
                errorMessage = "Could not access selected file."
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }
            
            do {
                let data = try Data(contentsOf: url)
                if let text = String(data: data, encoding: .utf8) {
                    csvText = text
                    importedFileName = url.lastPathComponent
                    parseCSV()
                    autoMapColumns()
                    withAnimation { step = 2 }
                } else if let text = String(data: data, encoding: .ascii) {
                    csvText = text
                    importedFileName = url.lastPathComponent
                    parseCSV()
                    autoMapColumns()
                    withAnimation { step = 2 }
                } else {
                    errorMessage = "Failed to decode CSV text."
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }
}
