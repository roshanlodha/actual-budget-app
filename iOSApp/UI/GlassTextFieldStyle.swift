import SwiftUI

struct GlassTextFieldStyle: TextFieldStyle {
    @Environment(\.colorScheme) private var colorScheme

    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding(12)
            .foregroundColor(.primary)
            .glassEffect(.clear.interactive(), in: .rect(cornerRadius: 10))
    }
}
