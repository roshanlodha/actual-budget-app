import SwiftUI

struct TransactionEditor: View {
    enum PayeeInputMode { case picker, custom }

    var transaction: Transaction?
    var initialAccountId: String?
    var onSave: (Transaction) -> Void
    
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var accounts: [Account] = []
    @State private var categoriesById: [String: String] = [:]
    @State private var payees: [Payee] = []
    @State private var errorMessage: String?
    
    @State private var date: Date
    @State private var amountString: String
    @State private var isNegative: Bool
    @State private var selectedPayeeId: String
    @State private var selectedTransferId: String?
    @State private var customPayee: String
    @State private var payeeMode: PayeeInputMode
    @State private var notes: String
    @State private var categoryId: String?
    @State private var selectedAccountId: String

    private var repository: BudgetRepository {
        guard let repo = appState.repository else { fatalError("Repository unavailable") }
        return repo
    }

    init(transaction: Transaction?, initialAccountId: String?, onSave: @escaping (Transaction) -> Void) {
        self.transaction = transaction
        self.initialAccountId = initialAccountId
        self.onSave = onSave

        if let t = transaction {
            _date = State(initialValue: Self.parseDate(t.date) ?? Date())
            _amountString = State(initialValue: Self.formatAmountForDisplay(abs(t.amount ?? 0)))
            _isNegative = State(initialValue: (t.amount ?? 0) < 0)
            
            if let payeeId = t.payee, !payeeId.isEmpty {
                _selectedPayeeId = State(initialValue: payeeId)
                _payeeMode = State(initialValue: .picker)
                _customPayee = State(initialValue: "")
            } else if let payeeName = t.payee_name, !payeeName.isEmpty {
                _customPayee = State(initialValue: payeeName)
                _payeeMode = State(initialValue: .custom)
                _selectedPayeeId = State(initialValue: "")
            } else {
                _payeeMode = State(initialValue: .picker)
                _selectedPayeeId = State(initialValue: "")
                _customPayee = State(initialValue: "")
            }
            
            _notes = State(initialValue: t.notes ?? "")
            _categoryId = State(initialValue: t.category)
            _selectedAccountId = State(initialValue: t.account)
            _selectedTransferId = State(initialValue: t.transfer_id)
        } else {
            _date = State(initialValue: Date())
            _amountString = State(initialValue: "0.00")
            _isNegative = State(initialValue: true)
            _selectedPayeeId = State(initialValue: "")
            _customPayee = State(initialValue: "")
            _payeeMode = State(initialValue: .picker)
            _notes = State(initialValue: "")
            _categoryId = State(initialValue: "auto_detect")
            _selectedAccountId = State(initialValue: initialAccountId ?? "")
            _selectedTransferId = State(initialValue: nil)
        }
    }

    var body: some View {
        NavigationView {
            ZStack {
                AppBackground()
                if accounts.isEmpty && errorMessage == nil {
                    ProgressView().tint(AppTheme.accent)
                } else {
                    formContent
                }
            }
            .navigationTitle(transaction == nil ? "New Transaction" : "Edit Transaction")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).bold() }
            }
            .task { await load() }
            .alert("Error", isPresented: .constant(errorMessage != nil)) {
                Button("OK") { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
        }
        .tint(AppTheme.accent)
    }
    
    private var formContent: some View {
        ScrollView {
            AdaptiveGlassContainer(spacing: 20) {
                VStack(spacing: 20) {
                    // Section 1: Account Choice
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Account")
                            .font(AppTheme.Fonts.subheadline)
                            .foregroundColor(.secondary)
                            .padding(.horizontal)
                        
                        GlassCard(cornerRadius: 15) {
                            Picker("Account", selection: $selectedAccountId) {
                                ForEach(accounts, id: \.id) { acc in
                                    Text(acc.name + (acc.offbudget ? " (Off-Budget)" : "")).tag(acc.id)
                                }
                            }
                            .pickerStyle(.menu)
                            .tint(AppTheme.accent)
                            .font(AppTheme.Fonts.body)
                        }
                    }
                    
                    // Section 2: Details
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Details")
                            .font(AppTheme.Fonts.subheadline)
                            .foregroundColor(.secondary)
                            .padding(.horizontal)
                        
                        GlassCard(cornerRadius: 15) {
                            VStack(spacing: 16) {
                                DatePicker("Date", selection: $date, displayedComponents: .date)
                                    .tint(AppTheme.accent)
                                    .font(AppTheme.Fonts.body)
                                
                                Divider()
                                
                                HStack(spacing: 12) {
                                    TextField("Amount", text: $amountString)
                                        .textFieldStyle(GlassTextFieldStyle())
                                    
                                    Picker("Type", selection: $isNegative) {
                                        Text("Expense").tag(true)
                                        Text("Income").tag(false)
                                    }
                                    .pickerStyle(.segmented)
                                    .frame(width: 150)
                                }
                                
                                Divider()
                                
                                Picker("Payee", selection: $payeeMode) {
                                    Text("Choose").tag(PayeeInputMode.picker)
                                    Text("Custom").tag(PayeeInputMode.custom)
                                }
                                .pickerStyle(.segmented)
                                
                                if payeeMode == .picker {
                                    Picker("Payee", selection: $selectedPayeeId) {
                                        Text("None").tag("")
                                        ForEach(payees, id: \.id) { payee in
                                            Text(payee.name).tag(payee.id)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                    .tint(AppTheme.accent)
                                    .font(AppTheme.Fonts.body)
                                    .onChange(of: selectedPayeeId) { oldValue, newValue in
                                        selectedTransferId = payees.first(where: { $0.id == newValue })?.transfer_acct
                                    }
                                } else {
                                    TextField("Payee Name", text: $customPayee)
                                        .textFieldStyle(GlassTextFieldStyle())
                                }
                                
                                Divider()
                                
                                Picker("Category", selection: $categoryId) {
                                    Text("Auto-Detect").tag(String?.some("auto_detect"))
                                    Text("None").tag(String?.none)
                                    ForEach(categoriesById.sorted { $0.value < $1.value }, id: \.key) { key, value in
                                        Text(value).tag(String?.some(key))
                                    }
                                }
                                .pickerStyle(.menu)
                                .tint(AppTheme.accent)
                                .font(AppTheme.Fonts.body)
                                
                                Divider()
                                
                                TextField("Notes", text: $notes)
                                    .textFieldStyle(GlassTextFieldStyle())
                            }
                        }
                    }
                }
                .padding()
            }
        }
        .applyScrollEdgeEffect()
    }
    
    private func buildTransaction() -> Transaction {
        let units = parseAmountFromDisplay(amountString)
        let signed = isNegative ? -abs(units) : abs(units)
        
        let payeeId: String? = payeeMode == .picker ? (selectedPayeeId.isEmpty ? nil : selectedPayeeId) : nil
        let payeeName: String? = payeeMode == .custom ? (customPayee.isEmpty ? nil : customPayee) : nil
        
        return Transaction(
            id: transaction?.id,
            account: selectedAccountId,
            date: Self.formatDate(date),
            amount: signed,
            payee: payeeId,
            payee_name: payeeName,
            imported_payee: nil,
            category: categoryId,
            notes: notes.isEmpty ? nil : notes,
            imported_id: nil,
            transfer_id: selectedTransferId,
            cleared: false, subtransactions: nil
        )
    }

    private func save() {
        Task {
            do {
                var built = buildTransaction()
                
                if built.category == "auto_detect" {
                    let cats = try await repository.fetchCategories()
                    let payeeName = payeeMode == .picker ? (payees.first(where: { $0.id == selectedPayeeId })?.name ?? "") : customPayee
                    
                    if let detectedId = await AutoClassifier.shared.autoCategorize(payeeName: payeeName, notes: notes, categories: cats) {
                        built = Transaction(
                            id: built.id,
                            account: built.account,
                            date: built.date,
                            amount: built.amount,
                            payee: built.payee,
                            payee_name: built.payee_name,
                            imported_payee: built.imported_payee,
                            category: detectedId,
                            notes: built.notes,
                            imported_id: built.imported_id,
                            transfer_id: built.transfer_id,
                            cleared: built.cleared,
                            subtransactions: built.subtransactions
                        )
                    } else {
                        let otherCat = cats.first(where: { $0.name.localizedCaseInsensitiveCompare("Other") == .orderedSame })
                        built = Transaction(
                            id: built.id,
                            account: built.account,
                            date: built.date,
                            amount: built.amount,
                            payee: built.payee,
                            payee_name: built.payee_name,
                            imported_payee: built.imported_payee,
                            category: otherCat?.id,
                            notes: built.notes,
                            imported_id: built.imported_id,
                            transfer_id: built.transfer_id,
                            cleared: built.cleared,
                            subtransactions: built.subtransactions
                        )
                    }
                }
                
                if let _ = transaction {
                    try await repository.updateTransaction(built)
                } else {
                    try await repository.createTransaction(built)
                }
                onSave(built)
                dismiss()
            } catch {
                await MainActor.run { errorMessage = error.localizedDescription }
            }
        }
    }

    private func load() async {
        do {
            let a = try await repository.fetchAccounts()
            let c = try await repository.fetchCategories()
            let p = try await repository.fetchPayees()
            await MainActor.run {
                accounts = a.filter { !$0.closed }
                categoriesById = Dictionary(uniqueKeysWithValues: c.map { ($0.id, $0.name) })
                payees = p.sorted { $0.name < $1.name }
                
                if transaction == nil && selectedAccountId.isEmpty {
                    selectedAccountId = initialAccountId ?? accounts.first?.id ?? ""
                }
            }
        } catch {
            await MainActor.run { errorMessage = error.localizedDescription }
        }
    }

    private static func parseDate(_ str: String) -> Date? {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.date(from: str)
    }
    private static func formatDate(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.string(from: date)
    }
    private static func formatAmountForDisplay(_ amount: Int) -> String {
        String(format: "%.2f", Double(amount) / 100.0)
    }
    private func parseAmountFromDisplay(_ display: String) -> Int {
        Int((Double(display.replacingOccurrences(of: ",", with: ".")) ?? 0.0) * 100)
    }
}
