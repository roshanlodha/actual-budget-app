import SwiftUI

struct AppTheme {
    static let accent = Color(hex: "#8B5CF6") // Neon violet
    static let accentSoft = Color(hex: "#8B5CF6").opacity(0.15)
    static let destructive = Color(hex: "#F43F5E") // Rose crimson
    static let positive = Color(hex: "#10B981") // Emerald teal
    
    struct Fonts {
        static let largeTitle = Font.system(size: 34, weight: .black, design: .rounded)
        static let title = Font.system(size: 24, weight: .bold, design: .rounded)
        static let subtitle = Font.system(size: 18, weight: .bold, design: .rounded)
        static let body = Font.system(size: 16, weight: .regular, design: .rounded)
        static let headline = Font.system(size: 16, weight: .bold, design: .rounded)
        static let subheadline = Font.system(size: 14, weight: .semibold, design: .rounded)
        static let footnote = Font.system(size: 12, weight: .bold, design: .rounded)
        static let caption = Font.system(size: 11, weight: .medium, design: .rounded)
    }
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

extension View {
    func applyScrollEdgeEffect() -> some View {
        self.scrollEdgeEffectStyle(.soft, for: .top)
            .scrollContentBackground(.hidden)
    }
}

struct AdaptiveGlassContainer<Content: View>: View {
    var spacing: CGFloat = 20
    @ViewBuilder var content: () -> Content

    var body: some View {
        GlassEffectContainer(spacing: spacing) {
            content()
        }
    }
}