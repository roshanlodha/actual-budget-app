import SwiftUI
import UIKit

struct LogsView: View {
    @State private var logText: String = ""
    @State private var isSharing: Bool = false

    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 16) {
                GlassCard(cornerRadius: 15) {
                    ScrollView {
                        Text(logText.isEmpty ? "No logs yet." : logText)
                            .font(.system(.footnote, design: .monospaced))
                            .foregroundColor(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 16)
                
                HStack(spacing: 16) {
                    Button {
                        AppLogger.shared.clear()
                        logText = ""
                    } label: {
                        HStack {
                            Image(systemName: "trash")
                            Text("Clear")
                        }
                        .font(AppTheme.Fonts.headline)
                        .foregroundColor(AppTheme.destructive)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    }
                    .background(Color.black.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(AppTheme.destructive.opacity(0.3), lineWidth: 1)
                    )

                    Button {
                        isSharing = true
                    } label: {
                        HStack {
                            Image(systemName: "square.and.arrow.up")
                            Text("Share")
                        }
                        .font(AppTheme.Fonts.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    }
                    .background(AppTheme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .shadow(color: AppTheme.accent.opacity(0.3), radius: 8, x: 0, y: 4)
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
        }
        .navigationTitle("Logs")
        .onAppear { logText = AppLogger.shared.readLogText() }
        .sheet(isPresented: $isSharing) {
            ShareSheet(activityItems: [AppLogger.shared.logFileURL])
        }
    }
}

private struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}


