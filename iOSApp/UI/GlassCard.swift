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
        content()
            .padding(16)
            .glassEffect(isInteractive ? .regular.interactive() : .regular, in: .rect(cornerRadius: cornerRadius))
    }
}