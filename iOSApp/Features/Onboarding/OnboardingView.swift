import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var appState: AppState
    @State private var budgetName: String = ""
    @State private var errorMessage: String?
    
    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 24) {
                Spacer()
                Text("Welcome to Actual")
                    .font(AppTheme.Fonts.largeTitle)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
                
                Text("Create your local budget on-device. Safe, fast, offline-first.")
                    .font(AppTheme.Fonts.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Budget Display Name")
                            .font(AppTheme.Fonts.subheadline)
                            .foregroundColor(.secondary)
                        TextField("", text: $budgetName, prompt: Text("e.g. My Personal Finances").foregroundColor(.secondary.opacity(0.5)))
                            .foregroundColor(.primary)
                            .textFieldStyle(.plain)
                            .padding(10)
                            .background(Color.primary.opacity(0.05))
                            .cornerRadius(8)
                    }
                }
                .padding(.horizontal)

                Button(action: createBudget) {
                    Text("Create New Budget")
                        .font(AppTheme.Fonts.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.accent)
                .disabled(budgetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .padding(.horizontal)
                
                Spacer()
            }
            .padding()
        }
        .alert("Error", isPresented: Binding(
            get: { errorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    errorMessage = nil
                }
            }
        )) {
            Button("OK") { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    private func createBudget() {
        let cleanName = budgetName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return }
        let budgetId = UUID().uuidString
        
        let metaURL = LocalBudgetFileManager.shared.metadataFileURL(for: budgetId)
        do {
            try LocalBudgetFileManager.shared.createBudgetDirectory(for: budgetId)
            
            let metadata: [String: Any] = [
                "displayName": cleanName,
                "createdAt": ISO8601DateFormatter().string(from: Date()),
                "lastModifiedAt": ISO8601DateFormatter().string(from: Date())
            ]
            let data = try JSONSerialization.data(withJSONObject: metadata)
            try data.write(to: metaURL)
            
            appState.selectedBudgetDisplayName = cleanName
            appState.selectedBudgetID = budgetId
            
            if appState.onboardingState == .noBudgetSelected {
                errorMessage = "Failed to initialize the local budget database."
            }
        } catch {
            errorMessage = "Failed to create budget files: \(error.localizedDescription)"
        }
    }
}
