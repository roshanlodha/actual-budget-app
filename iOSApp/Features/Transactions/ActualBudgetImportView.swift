import SwiftUI
import UniformTypeIdentifiers

struct ActualBudgetImportView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    
    @State private var step = 1
    @State private var csvText = ""
    @State private var importedFileName: String?
    @State private var budgetName = "Actual Import"
    
    @State private var parsedCategories: [ParsedCategory] = []
    @State private var selectedCategoryKeys = Set<String>()
    
    @State private var showingFileImporter = false
    @State private var isImporting = false
    @State private var errorMessage: String?
    
    private var categoriesByGroup: [String: [ParsedCategory]] {
        Dictionary(grouping: parsedCategories, by: { $0.groupName })
    }
    
    private var sortedGroupNames: [String] {
        categoriesByGroup.keys.sorted {
            if $0.localizedCaseInsensitiveCompare("income") == .orderedSame {
                return true
            }
            if $1.localizedCaseInsensitiveCompare("income") == .orderedSame {
                return false
            }
            return $0 < $1
        }
    }
    
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
                                fileSelectionStep
                            case 2:
                                categorySelectionStep
                            case 3:
                                confirmationStep
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
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(AppTheme.accent)
                        Text("Importing Budget...")
                            .font(AppTheme.Fonts.headline)
                            .foregroundColor(.white)
                    }
                    .padding(24)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(UIColor.systemBackground).opacity(0.95))
                            .shadow(radius: 20)
                    )
                }
            }
            .navigationTitle("Import Actual Budget")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert("Error", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
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
        }
        .tint(AppTheme.accent)
    }
    
    // MARK: - Step Indicator
    private var stepIndicator: some View {
        HStack(spacing: 8) {
            stepBadge(num: 1, label: "File")
            lineConnector(active: step > 1)
            stepBadge(num: 2, label: "Categories")
            lineConnector(active: step > 2)
            stepBadge(num: 3, label: "Import")
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
                        let parsed = ActualBudgetImporter.parseCategoriesFromCSV(text: csvText)
                        if parsed.isEmpty {
                            errorMessage = "No categories found in CSV file. Please make sure the CSV has Category and Category_Group headers."
                        } else {
                            parsedCategories = parsed
                            // Select all by default
                            selectedCategoryKeys = Set(parsed.map { $0.id })
                            withAnimation { step = 2 }
                        }
                    } else {
                        withAnimation { step = 3 }
                    }
                } label: {
                    Text("Next")
                        .font(AppTheme.Fonts.headline)
                        .foregroundColor(.black)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 32)
                        .background(csvText.isEmpty ? Color.gray : AppTheme.accent)
                        .cornerRadius(10)
                }
                .disabled(csvText.isEmpty)
                .buttonStyle(.plain)
            } else {
                Button {
                    performImport()
                } label: {
                    Text("Import Budget")
                        .font(AppTheme.Fonts.headline)
                        .foregroundColor(.black)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 32)
                        .background(AppTheme.accent)
                        .cornerRadius(10)
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    // MARK: - Step 1: File Selection
    private var fileSelectionStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Select Actual Budget CSV Export")
                .font(AppTheme.Fonts.title)
                .foregroundColor(.primary)
            
            Text("Select the transaction CSV file exported from Actual Budget desktop app. The CSV file must contain at least Account, Date, Payee, Category, and Amount columns.")
                .font(AppTheme.Fonts.body)
                .foregroundColor(.secondary)
            
            GlassCard {
                VStack(spacing: 12) {
                    Image(systemName: "arrow.down.doc.fill")
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
            
            if importedFileName != nil {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Budget Name")
                        .font(AppTheme.Fonts.headline)
                        .foregroundColor(.primary)
                    
                    TextField("Enter budget name", text: $budgetName)
                        .foregroundColor(.primary)
                        .textFieldStyle(.plain)
                        .padding(12)
                        .background(Color.white.opacity(0.05))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.white.opacity(0.15), lineWidth: 1)
                        )
                }
            }
        }
    }
    
    // MARK: - Step 2: Category Selection
    private var categorySelectionStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("Select Categories to Import")
                    .font(AppTheme.Fonts.title)
                    .foregroundColor(.primary)
                Spacer()
                
                Button(allSelected ? "Deselect All" : "Select All") {
                    if allSelected {
                        selectedCategoryKeys.removeAll()
                    } else {
                        selectedCategoryKeys = Set(parsedCategories.map { $0.id })
                    }
                }
                .font(AppTheme.Fonts.footnote)
                .foregroundColor(AppTheme.accent)
            }
            
            Text("Uncheck categories you do not want to import. Transactions belonging to unchecked categories will be imported uncategorized.")
                .font(AppTheme.Fonts.body)
                .foregroundColor(.secondary)
            
            ForEach(sortedGroupNames, id: \.self) { groupName in
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(groupName)
                            .font(AppTheme.Fonts.subtitle)
                            .foregroundColor(AppTheme.accent)
                        Spacer()
                        
                        let groupCats = categoriesByGroup[groupName] ?? []
                        let groupSelected = groupCats.allSatisfy { selectedCategoryKeys.contains($0.id) }
                        
                        Button(groupSelected ? "Deselect" : "Select") {
                            if groupSelected {
                                for cat in groupCats {
                                    selectedCategoryKeys.remove(cat.id)
                                }
                            } else {
                                for cat in groupCats {
                                    selectedCategoryKeys.insert(cat.id)
                                }
                            }
                        }
                        .font(AppTheme.Fonts.caption)
                        .foregroundColor(AppTheme.accent.opacity(0.8))
                    }
                    
                    GlassCard {
                        VStack(spacing: 0) {
                            let groupCats = categoriesByGroup[groupName] ?? []
                            ForEach(groupCats) { cat in
                                let isSelected = selectedCategoryKeys.contains(cat.id)
                                
                                Toggle(isOn: Binding(
                                    get: { isSelected },
                                    set: { selected in
                                        if selected {
                                            selectedCategoryKeys.insert(cat.id)
                                        } else {
                                            selectedCategoryKeys.remove(cat.id)
                                        }
                                    }
                                )) {
                                    Text(cat.name)
                                        .font(AppTheme.Fonts.body)
                                        .foregroundColor(.primary)
                                }
                                .tint(AppTheme.accent)
                                .padding(.vertical, 8)
                                
                                if cat.id != groupCats.last?.id {
                                    Divider()
                                        .background(Color.white.opacity(0.1))
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    
    private var allSelected: Bool {
        selectedCategoryKeys.count == parsedCategories.count
    }
    
    // MARK: - Step 3: Confirmation
    private var confirmationStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Ready to Import")
                .font(AppTheme.Fonts.title)
                .foregroundColor(.primary)
            
            Text("Review your import settings. Clicking 'Import Budget' will create a new budget in Actual.")
                .font(AppTheme.Fonts.body)
                .foregroundColor(.secondary)
            
            GlassCard {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("Budget Name")
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(budgetName)
                            .foregroundColor(.primary)
                            .bold()
                    }
                    
                    Divider().background(Color.white.opacity(0.1))
                    
                    HStack {
                        Text("File")
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(importedFileName ?? "")
                            .foregroundColor(.primary)
                    }
                    
                    Divider().background(Color.white.opacity(0.1))
                    
                    HStack {
                        Text("Categories to Create")
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(selectedCategoryKeys.count) of \(parsedCategories.count)")
                            .foregroundColor(.primary)
                            .bold()
                    }
                }
            }
        }
    }
    
    // MARK: - File Import Handler
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
                    
                    // Auto detect budget name from file name
                    let name = url.deletingPathExtension().lastPathComponent
                    budgetName = name.replacingOccurrences(of: "-", with: " ")
                                     .replacingOccurrences(of: "_", with: " ")
                                     .capitalized
                } else if let text = String(data: data, encoding: .ascii) {
                    csvText = text
                    importedFileName = url.lastPathComponent
                    
                    let name = url.deletingPathExtension().lastPathComponent
                    budgetName = name.replacingOccurrences(of: "-", with: " ")
                                     .replacingOccurrences(of: "_", with: " ")
                                     .capitalized
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
    
    // MARK: - Perform Import
    private func performImport() {
        isImporting = true
        
        // Dispatch to background thread
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try ActualBudgetImporter.importBudgetFromCSV(
                    text: csvText,
                    displayName: budgetName,
                    selectedCategories: selectedCategoryKeys,
                    to: appState
                )
                DispatchQueue.main.async {
                    isImporting = false
                    dismiss()
                }
            } catch {
                DispatchQueue.main.async {
                    isImporting = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}
