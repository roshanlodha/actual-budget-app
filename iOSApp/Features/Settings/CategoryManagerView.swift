import SwiftUI

struct CategoryManagerView: View {
    @EnvironmentObject private var appState: AppState
    @State private var groups: [CategoryGroup] = []
    @State private var errorMessage: String?
    @State private var isLoading = false
    
    // Add/Edit category state
    @State private var editingCategory: Category?
    @State private var isAddingToGroup: CategoryGroup?
    @State private var categoryName: String = ""
    @State private var categoryColor: String = "#FF9233"
    @State private var categoryIcon: String = "tag.fill"
    
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
    
    private var repository: BudgetRepository {
        guard let repo = appState.repository else { fatalError("Repository unavailable") }
        return repo
    }
    
    struct CategoryGroup: Identifiable {
        let id: String
        let name: String
        let isIncome: Bool
        var categories: [Category]
    }

    var body: some View {
        ZStack {
            AppBackground()
            
            if isLoading {
                ProgressView()
            } else {
                List {
                    ForEach(groups) { group in
                        Section(header: HStack {
                            Text(group.name)
                                .font(AppTheme.Fonts.subtitle)
                                .foregroundColor(.primary)
                            Spacer()
                            Button {
                                prepareAddCategory(in: group)
                            } label: {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundColor(AppTheme.accent)
                                    .font(.title3)
                            }
                        }) {
                            if group.categories.isEmpty {
                                Text("No categories in this group")
                                    .font(AppTheme.Fonts.footnote)
                                    .foregroundColor(.secondary)
                                    .padding(.vertical, 4)
                            } else {
                                ForEach(group.categories) { cat in
                                    Button {
                                        prepareEditCategory(cat)
                                    } label: {
                                        HStack(spacing: 12) {
                                            Image(systemName: cat.icon ?? "tag.fill")
                                                .foregroundColor(.white)
                                                .frame(width: 28, height: 28)
                                                .background(Color(hex: cat.color ?? "#8D93AB"))
                                                .clipShape(Circle())
                                            
                                            Text(cat.name)
                                                .font(AppTheme.Fonts.body)
                                                .foregroundColor(.primary)
                                            
                                            Spacer()
                                            
                                            Image(systemName: "pencil")
                                                .foregroundColor(.secondary)
                                                .font(.footnote)
                                        }
                                    }
                                }
                            }
                        }
                        .listRowBackground(Color.primary.opacity(0.05))
                    }
                }
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle("Manage Categories")
        .task { await loadCategories() }
        .sheet(item: Binding(
            get: { editingCategory },
            set: { if $0 == nil { editingCategory = nil } }
        )) { cat in
            categoryEditSheet(isEdit: true, groupName: getGroupName(for: cat.group_id ?? ""))
        }
        .sheet(item: Binding(
            get: { isAddingToGroup },
            set: { if $0 == nil { isAddingToGroup = nil } }
        )) { group in
            categoryEditSheet(isEdit: false, groupName: group.name)
        }
        .alert("Error", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }
    
    @ViewBuilder
    private func categoryEditSheet(isEdit: Bool, groupName: String) -> some View {
        NavigationStack {
            ZStack {
                Color(red: 0.05, green: 0.08, blue: 0.14).ignoresSafeArea()
                
                VStack(spacing: 20) {
                    Form {
                        Section("Category Information") {
                            TextField("Name", text: $categoryName)
                            
                            HStack {
                                Text("Group")
                                Spacer()
                                Text(groupName)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Section("Color") {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(colors, id: \.self) { c in
                                        Circle()
                                            .fill(Color(hex: c))
                                            .frame(width: 32, height: 32)
                                            .overlay(
                                                Circle().stroke(categoryColor == c ? Color.white : Color.clear, lineWidth: 2)
                                            )
                                            .shadow(radius: categoryColor == c ? 2 : 0)
                                            .onTapGesture { categoryColor = c }
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                        
                        Section("Icon") {
                            let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 6)
                            LazyVGrid(columns: columns, spacing: 10) {
                                ForEach(icons, id: \.self) { icon in
                                    Image(systemName: icon)
                                        .font(.title3)
                                        .foregroundColor(categoryIcon == icon ? .white : .primary)
                                        .frame(width: 44, height: 44)
                                        .background(categoryIcon == icon ? Color(hex: categoryColor) : Color.primary.opacity(0.05))
                                        .clipShape(Circle())
                                        .onTapGesture { categoryIcon = icon }
                                }
                            }
                            .padding(.vertical, 8)
                        }
                        
                        if isEdit {
                            Section {
                                Button(role: .destructive, action: deleteCategory) {
                                    HStack {
                                        Spacer()
                                        Label("Delete Category", systemImage: "trash")
                                        Spacer()
                                    }
                                }
                            }
                        }
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle(isEdit ? "Edit Category" : "Add Category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        editingCategory = nil
                        isAddingToGroup = nil
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveCategory()
                    }
                    .disabled(categoryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
    
    private func loadCategories() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let fetchedGroups = try await repository.fetchCategoryGroups()
            let fetchedCats = try await repository.fetchCategories()
            
            var localGroups = [CategoryGroup]()
            for fg in fetchedGroups {
                let groupCats = fetchedCats.filter { $0.group_id == fg.id }
                localGroups.append(CategoryGroup(
                    id: fg.id,
                    name: fg.name,
                    isIncome: fg.is_income ?? false,
                    categories: groupCats
                ))
            }
            
            let spend = localGroups.filter { !$0.isIncome }
            let income = localGroups.filter { $0.isIncome }
            
            await MainActor.run {
                self.groups = spend + income
            }
        } catch {
            await MainActor.run { errorMessage = error.localizedDescription }
        }
    }
    
    private func getGroupName(for groupId: String) -> String {
        return groups.first(where: { $0.id == groupId })?.name ?? "Unknown"
    }
    
    private func prepareAddCategory(in group: CategoryGroup) {
        categoryName = ""
        categoryColor = colors[0]
        categoryIcon = icons[0]
        isAddingToGroup = group
    }
    
    private func prepareEditCategory(_ category: Category) {
        categoryName = category.name
        categoryColor = category.color ?? colors[0]
        categoryIcon = category.icon ?? icons[0]
        editingCategory = category
    }
    
    private func saveCategory() {
        let name = categoryName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        
        Task {
            do {
                if let cat = editingCategory {
                    let updated = Category(
                        id: cat.id,
                        name: name,
                        is_income: cat.is_income,
                        hidden: cat.hidden,
                        group_id: cat.group_id,
                        color: categoryColor,
                        icon: categoryIcon
                    )
                    try await repository.updateCategory(updated)
                } else if let group = isAddingToGroup {
                    _ = try await repository.createCategory(
                        name: name,
                        isIncome: group.isIncome,
                        groupId: group.id,
                        color: categoryColor,
                        icon: categoryIcon
                    )
                }
                
                await MainActor.run {
                    editingCategory = nil
                    isAddingToGroup = nil
                }
                await loadCategories()
            } catch {
                await MainActor.run { errorMessage = error.localizedDescription }
            }
        }
    }
    
    private func deleteCategory() {
        guard let cat = editingCategory else { return }
        Task {
            do {
                try await repository.deleteCategory(id: cat.id)
                await MainActor.run { editingCategory = nil }
                await loadCategories()
            } catch {
                await MainActor.run { errorMessage = error.localizedDescription }
            }
        }
    }
}
