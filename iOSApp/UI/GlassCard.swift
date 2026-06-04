import SwiftUI

struct GlassCard<Content: View>: View {
    var cornerRadius: CGFloat = 20
    var isInteractive: Bool = false
    var content: () -> Content

    init(cornerRadius: CGFloat = 20, isInteractive: Bool = false, @ViewBuilder content: @escaping () -> Content) {
        self.cornerRadius = cornerRadius
        self.isInteractive = isInteractive
        self.content = content
    }

    var body: some View {
        if #available(iOS 26, *) {
            content()
                .padding(16)
                .glassEffect(isInteractive ? .regular.interactive() : .regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            content()
                .padding(16)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [Color.white.opacity(0.18), Color.white.opacity(0.06)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
                .shadow(color: Color.black.opacity(0.12), radius: 10, x: 0, y: 5)
        }
    }
}