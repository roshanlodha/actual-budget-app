import SwiftUI

struct GlassTextFieldStyle: TextFieldStyle {
    @Environment(\.colorScheme) private var colorScheme

    func _body(configuration: TextField<Self._Label>) -> some View {
        if #available(iOS 26, *) {
            configuration
                .padding(12)
                .foregroundColor(.primary)
                .glassEffect(.clear.interactive(), in: .rect(cornerRadius: 10))
        } else {
            configuration
                .padding(12)
                .foregroundColor(.primary)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.04))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(colorScheme == .dark ? Color.white.opacity(0.18) : Color.black.opacity(0.10), lineWidth: 1)
                )
        }
    }
}
