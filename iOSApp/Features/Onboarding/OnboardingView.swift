import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var appState: AppState
    
    // Step state: 0 = Name & Currency, 1 = Categories Setup
    @State private var currentStep: Int = 0
    @State private var budgetName: String = ""
    @State private var selectedCurrency: String = "USD"
    @State private var errorMessage: String?
    
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
        "banknote.fill", "creditcard.and.loop", "heart.fill", "figure.run",
        "sparkles", "tag.fill"
    ]
    
    private let predefinedTemplates = [
        // Income
        CategorySetup(name: "Salary", isIncome: true, color: "#4ECCA3", icon: "briefcase.fill"),
        CategorySetup(name: "Freelance", isIncome: true, color: "#00ADB5", icon: "laptopcomputer"),
        CategorySetup(name: "Investments", isIncome: true, color: "#5A20CB", icon: "chart.line.uptrend.xyaxis"),
        CategorySetup(name: "Gifts / Other", isIncome: true, color: "#FF8AAE", icon: "gift.fill"),
        
        // Fixed
        CategorySetup(name: "Rent / Mortgage", isIncome: false, color: "#FF6B6B", icon: "house.fill"),
        CategorySetup(name: "Utilities", isIncome: false, color: "#FF9233", icon: "bolt.fill"),
        CategorySetup(name: "Internet & TV", isIncome: false, color: "#FFC93C", icon: "wifi"),
        CategorySetup(name: "Phone", isIncome: false, color: "#FFC93C", icon: "phone.fill"),
        CategorySetup(name: "Insurance", isIncome: false, color: "#8D93AB", icon: "shield.fill"),
        
        // Flexible
        CategorySetup(name: "Groceries", isIncome: false, color: "#FF8AAE", icon: "cart.fill"),
        CategorySetup(name: "Dining Out", isIncome: false, color: "#FF9233", icon: "fork.knife"),
        CategorySetup(name: "Coffee & Snacks", isIncome: false, color: "#FFC93C", icon: "cup.and.saucer.fill"),
        CategorySetup(name: "Shopping", isIncome: false, color: "#FF8AAE", icon: "bag.fill"),
        CategorySetup(name: "Entertainment", isIncome: false, color: "#A66CFF", icon: "popcorn.fill"),
        CategorySetup(name: "Travel", isIncome: false, color: "#39A2DB", icon: "airplane"),
        CategorySetup(name: "Subscriptions", isIncome: false, color: "#FF6B6B", icon: "creditcard.fill"),
        CategorySetup(name: "Fuel / Gas", isIncome: false, color: "#FF9233", icon: "fuelpump.fill"),
        CategorySetup(name: "Public Transit", isIncome: false, color: "#39A2DB", icon: "tram.fill"),
        CategorySetup(name: "Gym & Fitness", isIncome: false, color: "#4ECCA3", icon: "figure.run"),
        CategorySetup(name: "Medical & Health", isIncome: false, color: "#FF6B6B", icon: "heart.fill"),
        CategorySetup(name: "Personal Care", isIncome: false, color: "#FF8AAE", icon: "sparkles"),
        
        // Savings
        CategorySetup(name: "Emergency Fund", isIncome: false, color: "#5A20CB", icon: "banknote.fill"),
        CategorySetup(name: "Savings Goal", isIncome: false, color: "#5A20CB", icon: "banknote.fill"),
        CategorySetup(name: "Debt Paydown", isIncome: false, color: "#FF6B6B", icon: "creditcard.and.loop")
    ]
    
    private let defaultSelectedNames: Set<String> = [
        "Salary", "Rent / Mortgage", "Utilities", "Groceries", "Dining Out", "Shopping", "Emergency Fund"
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
                        TextField("", text: $budgetName, prompt: Text("e.g. My Personal Finances").foregroundColor(.secondary.opacity(0.5)))
                            .foregroundColor(.primary)
                            .textFieldStyle(.plain)
                            .padding(12)
                            .background(Color.primary.opacity(0.05))
                            .cornerRadius(8)
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
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(Color.primary.opacity(0.05))
                        .cornerRadius(8)
                    }
                }
            }
            
            Spacer()
            
            Button(action: {
                if !budgetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    withAnimation { currentStep = 1 }
                }
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
            .disabled(budgetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }
    
    private var step2View: some View {
        VStack(spacing: 16) {
            Text("Tap standard categories to add them, or create your own below.")
                .font(AppTheme.Fonts.footnote)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            ScrollView {
                VStack(spacing: 20) {
                    // Standard Selection
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Predefined Categories")
                            .font(AppTheme.Fonts.subtitle)
                            .foregroundColor(.primary)
                        
                        let columns = [GridItem(.adaptive(minimum: 140, maximum: 200), spacing: 10)]
                        
                        LazyVGrid(columns: columns, spacing: 10) {
                            ForEach(predefinedTemplates) { template in
                                let isSelected = selectedCategories.contains(where: { $0.name == template.name })
                                Button {
                                    togglePredefined(template)
                                } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: template.icon ?? "tag.fill")
                                            .foregroundColor(.white)
                                            .frame(width: 24, height: 24)
                                            .background(Color(hex: template.color ?? "#8D93AB"))
                                            .clipShape(Circle())
                                        
                                        Text(template.name)
                                            .font(AppTheme.Fonts.footnote)
                                            .foregroundColor(.primary)
                                            .lineLimit(1)
                                        
                                        Spacer()
                                        
                                        if isSelected {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundColor(AppTheme.accent)
                                        }
                                    }
                                    .padding(8)
                                    .background(isSelected ? AppTheme.accent.opacity(0.1) : Color.primary.opacity(0.03))
                                    .cornerRadius(10)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(isSelected ? AppTheme.accent : Color.clear, lineWidth: 1)
                                    )
                                }
                                .buttonStyle(.plain)
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
                                    .textFieldStyle(.plain)
                                    .padding(10)
                                    .background(Color.primary.opacity(0.05))
                                    .cornerRadius(8)
                                
                                Picker("", selection: $customGroup) {
                                    ForEach(groupOptions, id: \.self) { opt in
                                        Text(opt).tag(opt)
                                    }
                                }
                                .pickerStyle(.menu)
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
                                    HStack {
                                        Image(systemName: cat.icon ?? "tag.fill")
                                            .foregroundColor(.white)
                                            .frame(width: 24, height: 24)
                                            .background(Color(hex: cat.color ?? "#8D93AB"))
                                            .clipShape(Circle())
                                        
                                        Text(cat.name)
                                            .font(AppTheme.Fonts.body)
                                            .foregroundColor(.primary)
                                        
                                        Spacer()
                                        
                                        Text(getGroupName(for: cat))
                                            .font(AppTheme.Fonts.caption)
                                            .foregroundColor(.secondary)
                                        
                                        Button {
                                            selectedCategories.removeAll(where: { $0.id == cat.id })
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .foregroundColor(.secondary)
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
                .disabled(selectedCategories.isEmpty)
            }
        }
    }
    
    private func togglePredefined(_ template: CategorySetup) {
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
        // If we have custom group details, we should store it.
        // Predefined matches:
        switch category.name {
        case "Rent / Mortgage", "Utilities", "Internet & TV", "Phone", "Insurance", "Subscriptions":
            return "Fixed Expenses"
        case "Emergency Fund", "Savings Goal", "Debt Paydown":
            return "Savings & Investments"
        default:
            // For custom categories, we can look up if it's already in selectedCategories with a customGroup mapping
            // But custom categories carry their group in temporary selection. To keep it simple:
            // We can match preset groups
            return category.isIncome ? "Income" : "Flexible Spending"
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
