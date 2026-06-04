import SwiftUI
import UniformTypeIdentifiers

struct OnboardingView: View {
    @EnvironmentObject private var appState: AppState
    
    // Step state: 0 = Name & Currency, 1 = Categories Setup
    @State private var currentStep: Int = 0
    @State private var budgetName: String = "My Budget"
    @State private var selectedCurrency: String = "USD"
    @State private var errorMessage: String?
    @State private var showingActualImportSheet = false
    
    // Categories state
    @State private var selectedCategories: [CategorySetup] = []
    
    // Custom category builder state
    @State private var customName: String = ""
    @State private var customGroup: String = "Flexible Spending"
    @State private var customColor: String = "#FF9233"
    @State private var customIcon: String = "tag.fill"
    
    // Lists for selectors
    private let groupOptions = ["Income", "Fixed Expenses", "Flexible Spending", "Savings & Investments"]
    
    private let colors = [
        "#FF6B6B", "#FF9233", "#FFC93C", "#4ECCA3", "#00ADB5",
        "#39A2DB", "#5A20CB", "#A66CFF", "#FF8AAE", "#8D93AB"
    ]
    
    private let icons = [
        "briefcase.fill", "dollarsign.circle.fill", "laptopcomputer", "chart.line.uptrend.xyaxis",
        "house.fill", "bolt.fill", "wifi", "phone.fill", "shield.fill",
        "cart.fill", "fork.knife", "cup.and.saucer.fill", "bag.fill",
        "popcorn.fill", "airplane", "creditcard.fill", "fuelpump.fill",
        "banknote.fill", "creditcard", "heart.fill", "figure.run",
        "sparkles", "tag.fill"
    ]
    
    private let predefinedTemplates = [
        CategorySetup(name: "Taxes", isIncome: false, color: "#8D93AB", icon: "percent"),
        CategorySetup(name: "Savings", isIncome: false, color: "#5A20CB", icon: "banknote.fill"),
        CategorySetup(name: "Travel", isIncome: false, color: "#39A2DB", icon: "airplane"),
        CategorySetup(name: "Groceries", isIncome: false, color: "#FF8AAE", icon: "cart.fill"),
        CategorySetup(name: "Eating Out", isIncome: false, color: "#FF9233", icon: "fork.knife"),
        CategorySetup(name: "Clothes & Hair", isIncome: false, color: "#A66CFF", icon: "tshirt.fill"),
        CategorySetup(name: "Business", isIncome: true, color: "#4ECCA3", icon: "briefcase.fill"),
        CategorySetup(name: "Rent", isIncome: false, color: "#FF6B6B", icon: "house.fill"),
        CategorySetup(name: "Utilities, Internet, Insurance", isIncome: false, color: "#FFC93C", icon: "bolt.fill"),
        CategorySetup(name: "Transportation and Gas", isIncome: false, color: "#39A2DB", icon: "car.fill"),
        CategorySetup(name: "Other", isIncome: false, color: "#8D93AB", icon: "tag.fill")
    ]
    
    private let defaultSelectedNames: Set<String> = [
        "Business", "Rent", "Utilities, Internet, Insurance", "Groceries", "Eating Out", "Transportation and Gas", "Savings", "Other"
    ]
    
    init() {
        // Initialize default selected categories
        let preselected = predefinedTemplates.filter { defaultSelectedNames.contains($0.name) }
        _selectedCategories = State(initialValue: preselected)
    }

    var body: some View {
        ZStack {
            AppBackground()
            
            VStack(spacing: 20) {
                // Header with Progress Indicator
                HStack(spacing: 8) {
                    Circle()
                        .fill(currentStep >= 0 ? AppTheme.accent : Color.secondary)
                        .frame(width: 8, height: 8)
                    Circle()
                        .fill(currentStep >= 1 ? AppTheme.accent : Color.secondary)
                        .frame(width: 8, height: 8)
                }
                .padding(.top)
                
                Text(currentStep == 0 ? "Set Up Your Budget" : "Choose Categories")
                    .font(AppTheme.Fonts.largeTitle)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
                
                if currentStep == 0 {
                    step1View
                } else {
                    step2View
                }
            }
            .padding()
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
    
    private var step1View: some View {
        VStack(spacing: 24) {
            Text("Create your local budget on-device. Safe, fast, offline-first.")
                .font(AppTheme.Fonts.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Spacer()
            
            GlassCard {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Budget Name")
                            .font(AppTheme.Fonts.subheadline)
                            .foregroundColor(.secondary)
                        TextField("My Budget", text: $budgetName)
                            .textFieldStyle(GlassTextFieldStyle())
                    }
                    
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Currency")
                            .font(AppTheme.Fonts.subheadline)
                            .foregroundColor(.secondary)
                        
                        Picker("Currency", selection: $selectedCurrency) {
                            ForEach(CurrencyFormatter.supportedCurrencies, id: \.0) { code, name in
                                Text("\(code) - \(name)").tag(code)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(AppTheme.accent)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            
            Spacer()
            
            Button(action: {
                withAnimation { currentStep = 1 }
            }) {
                HStack {
                    Text("Continue")
                    Image(systemName: "chevron.right")
                }
                .font(AppTheme.Fonts.headline)
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.accent)
            
            HStack {
                Rectangle()
                    .fill(Color.secondary.opacity(0.2))
                    .frame(height: 1)
                Text("or")
                    .font(AppTheme.Fonts.footnote)
                    .foregroundColor(.secondary)
                Rectangle()
                    .fill(Color.secondary.opacity(0.2))
                    .frame(height: 1)
            }
            .padding(.vertical, 8)
            
            Button(action: {
                showingActualImportSheet = true
            }) {
                HStack {
                    Image(systemName: "arrow.down.doc.fill")
                    Text("Import from Actual")
                }
                .font(AppTheme.Fonts.headline)
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(AppTheme.accent)
        }
    }
    
    private var step2View: some View {
        VStack(spacing: 16) {
            Text("Select categories to add to your budget. \"Other\" is required.")
                .font(AppTheme.Fonts.footnote)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            ScrollView {
                AdaptiveGlassContainer(spacing: 20) {
                    VStack(spacing: 20) {
                        // Standard Selection in a clean list structure
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Standard Categories")
                                .font(AppTheme.Fonts.subtitle)
                                .foregroundColor(.primary)
                            
                            GlassCard {
                                VStack(spacing: 0) {
                                    ForEach(predefinedTemplates) { template in
                                        let isSelected = selectedCategories.contains(where: { $0.name == template.name })
                                        let isOther = template.name == "Other"
                                        
                                        HStack(spacing: 16) {
                                            Image(systemName: template.icon ?? "tag.fill")
                                                .font(.body)
                                                .foregroundColor(Color(hex: template.color ?? "#8D93AB"))
                                                .frame(width: 24, height: 24)
                                            
                                            Text(template.name)
                                                .font(AppTheme.Fonts.body)
                                                .foregroundColor(.primary)
                                            
                                            Spacer()
                                            
                                            if isOther {
                                                Text("Mandatory")
                                                    .font(AppTheme.Fonts.footnote)
                                                    .foregroundColor(.secondary)
                                                    .padding(.trailing, 8)
                                            } else {
                                                Toggle("", isOn: Binding(
                                                    get: { isSelected },
                                                    set: { shouldSelect in
                                                        if shouldSelect {
                                                            if !selectedCategories.contains(where: { $0.name == template.name }) {
                                                                selectedCategories.append(template)
                                                            }
                                                        } else {
                                                            selectedCategories.removeAll(where: { $0.name == template.name })
                                                        }
                                                    }
                                                ))
                                                .labelsHidden()
                                                .tint(AppTheme.accent)
                                            }
                                        }
                                        .padding(.vertical, 10)
                                        
                                        if template.id != predefinedTemplates.last?.id {
                                            Divider()
                                        }
                                    }
                                }
                            }
                        }
                        
                        Divider()
                        
                        // Custom Categories Builder
                        GlassCard {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Create Custom Category")
                                    .font(AppTheme.Fonts.subtitle)
                                    .foregroundColor(.primary)
                                
                                HStack(spacing: 10) {
                                    TextField("Category Name", text: $customName)
                                        .textFieldStyle(GlassTextFieldStyle())
                                    
                                    Picker("", selection: $customGroup) {
                                        ForEach(groupOptions, id: \.self) { opt in
                                            Text(opt).tag(opt)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                    .tint(AppTheme.accent)
                                }
                                
                                // Color selection
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Choose Color")
                                        .font(AppTheme.Fonts.footnote)
                                        .foregroundColor(.secondary)
                                    ScrollView(.horizontal, showsIndicators: false) {
                                        HStack(spacing: 8) {
                                            ForEach(colors, id: \.self) { c in
                                                Circle()
                                                    .fill(Color(hex: c))
                                                    .frame(width: 28, height: 28)
                                                    .overlay(
                                                        Circle().stroke(customColor == c ? Color.white : Color.clear, lineWidth: 2)
                                                    )
                                                    .shadow(radius: customColor == c ? 2 : 0)
                                                    .onTapGesture { customColor = c }
                                            }
                                        }
                                        .padding(.vertical, 2)
                                    }
                                }
                                
                                // Icon selection
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Choose Icon")
                                        .font(AppTheme.Fonts.footnote)
                                        .foregroundColor(.secondary)
                                    ScrollView(.horizontal, showsIndicators: false) {
                                        HStack(spacing: 8) {
                                            ForEach(icons, id: \.self) { icon in
                                                Image(systemName: icon)
                                                    .font(.body)
                                                    .foregroundColor(customIcon == icon ? .white : .primary)
                                                    .frame(width: 32, height: 32)
                                                    .background(customIcon == icon ? Color(hex: customColor) : Color.primary.opacity(0.05))
                                                    .clipShape(Circle())
                                                    .onTapGesture { customIcon = icon }
                                            }
                                        }
                                        .padding(.vertical, 2)
                                    }
                                }
                                
                                Button(action: addCustomCategory) {
                                    Label("Add Custom Category", systemImage: "plus")
                                        .font(AppTheme.Fonts.headline)
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)
                                .tint(AppTheme.accent)
                                .disabled(customName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }
                        }
                        
                        // Selected List preview
                        if !selectedCategories.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Categories to Create (\(selectedCategories.count))")
                                    .font(AppTheme.Fonts.subtitle)
                                    .foregroundColor(.primary)
                                
                                VStack(alignment: .leading, spacing: 8) {
                                    ForEach(selectedCategories) { cat in
                                        let isOther = cat.name == "Other"
                                        HStack {
                                            Image(systemName: cat.icon ?? "tag.fill")
                                                .foregroundColor(Color(hex: cat.color ?? "#8D93AB"))
                                                .frame(width: 24, height: 24)
                                            
                                            Text(cat.name)
                                                .font(AppTheme.Fonts.body)
                                                .foregroundColor(.primary)
                                            
                                            Spacer()
                                            
                                            Text(getGroupName(for: cat))
                                                .font(AppTheme.Fonts.caption)
                                                .foregroundColor(.secondary)
                                            
                                            if !isOther {
                                                Button {
                                                    selectedCategories.removeAll(where: { $0.id == cat.id })
                                                } label: {
                                                    Image(systemName: "xmark.circle.fill")
                                                        .foregroundColor(.secondary)
                                                }
                                            }
                                        }
                                        .padding(8)
                                        .background(Color.primary.opacity(0.02))
                                        .cornerRadius(8)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .applyScrollEdgeEffect()
            
            HStack {
                Button(action: {
                    withAnimation { currentStep = 0 }
                }) {
                    HStack {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                    .font(AppTheme.Fonts.headline)
                }
                .buttonStyle(.bordered)
                
                Spacer()
                
                Button(action: finishSetup) {
                    Text("Launch My Budget")
                        .font(AppTheme.Fonts.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.accent)
                .disabled(selectedCategories.isEmpty || !selectedCategories.contains(where: { $0.name == "Other" }))
            }
        }
    }
    
    private func togglePredefined(_ template: CategorySetup) {
        if template.name == "Other" { return }
        if let idx = selectedCategories.firstIndex(where: { $0.name == template.name }) {
            selectedCategories.remove(at: idx)
        } else {
            selectedCategories.append(template)
        }
    }
    
    private func addCustomCategory() {
        let name = customName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        
        let isIncome = (customGroup == "Income")
        let newCat = CategorySetup(
            name: name,
            isIncome: isIncome,
            color: customColor,
            icon: customIcon
        )
        
        selectedCategories.append(newCat)
        customName = ""
    }
    
    private func getGroupName(for category: CategorySetup) -> String {
        if category.isIncome { return "Income" }
        switch category.name {
        case "Rent", "Utilities, Internet, Insurance", "Taxes":
            return "Fixed Expenses"
        case "Savings":
            return "Savings & Investments"
        default:
            return "Flexible Spending"
        }
    }
    
    private func finishSetup() {
        let cleanName = budgetName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return }
        let budgetId = UUID().uuidString
        
        // Group the categories
        var groupsMap = [String: [CategorySetup]]()
        for cat in selectedCategories {
            let groupName: String
            if cat.isIncome {
                groupName = "Income"
            } else {
                groupName = getGroupName(for: cat)
            }
            groupsMap[groupName, default: []].append(cat)
        }
        
        // Always ensure all 4 standard groups exist even if empty
        for grp in groupOptions {
            if groupsMap[grp] == nil {
                groupsMap[grp] = []
            }
        }
        
        let finalGroups = groupsMap.map { (key, value) -> CategoryGroupSetup in
            CategoryGroupSetup(
                name: key,
                isIncome: key == "Income",
                categories: value
            )
        }
        
        // Apply currency choice
        appState.currencyCode = selectedCurrency
        
        do {
            try appState.setupBudget(
                id: budgetId,
                displayName: cleanName,
                categoryGroups: finalGroups
            )
        } catch {
            errorMessage = "Failed to initialize budget: \(error.localizedDescription)"
        }
    }
}
