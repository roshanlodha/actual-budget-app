import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var appState: AppState
    @State private var baseURL: String = ""
    @State private var apiKey: String = ""
    @State private var syncId: String = ""
    @State private var password: String = ""

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 24) {
                Spacer()
                Text("Connect to Actual Server")
                    .font(AppTheme.Fonts.largeTitle)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)

                GlassCard {
                    VStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Base URL")
                                .font(AppTheme.Fonts.subheadline)
                                .foregroundColor(.white.opacity(0.8))
                            TextField("", text: $baseURL, prompt: Text("https://example.com/v1").foregroundColor(.white.opacity(0.6)))
                                .foregroundColor(.white)
                                .tint(Color.white.opacity(0.85))
                                .textContentType(.URL)
                                .keyboardType(.URL)
                                .autocapitalization(.none)
                                .textInputAutocapitalization(.never)
                                .disableAutocorrection(true)
                           
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("API Key")
                                .font(AppTheme.Fonts.subheadline)
                                .foregroundColor(.white.opacity(0.8))
                            TextField("", text: $apiKey, prompt: Text("Your API Key").foregroundColor(.white.opacity(0.6)))
                                .foregroundColor(.white)
                                .tint(Color.white.opacity(0.85))
                                .textContentType(.password)
                                .autocapitalization(.none)
                                .textInputAutocapitalization(.never)
                                .disableAutocorrection(true)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Sync ID")
                                .font(AppTheme.Fonts.subheadline)
                                .foregroundColor(.white.opacity(0.8))
                            TextField("", text: $syncId, prompt: Text("Your Sync ID").foregroundColor(.white.opacity(0.6)))
                                .foregroundColor(.white)
                                .tint(Color.white.opacity(0.85))
                                .autocapitalization(.none)
                                .textInputAutocapitalization(.never)
                                .disableAutocorrection(true)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Budget Encryption Password (optional)")
                                .font(AppTheme.Fonts.subheadline)
                                .foregroundColor(.white.opacity(0.8))
                            SecureField("", text: $password, prompt: Text("Password (if set)").foregroundColor(.white.opacity(0.6)))
                                .foregroundColor(.white)
                                .tint(Color.white.opacity(0.85))
                        }
                    }
                    .textFieldStyle(GlassTextFieldStyle())
                }
                .padding(.horizontal)

                Button(action: save) {
                    Text("Continue")
                        .font(AppTheme.Fonts.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.accent)
                .disabled(!isValid)
                .padding(.horizontal)
                
                Spacer()
            }
            .padding()
        }
        .onAppear {
            baseURL = appState.baseURLString
            apiKey = appState.apiKey
            syncId = appState.syncId
            password = appState.budgetEncryptionPassword
        }
    }

    private var isValid: Bool { !baseURL.isEmpty && !apiKey.isEmpty && !syncId.isEmpty }

    private func save() {
        appState.baseURLString = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        appState.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        appState.syncId = syncId.trimmingCharacters(in: .whitespacesAndNewlines)
        appState.budgetEncryptionPassword = password
    }
}
