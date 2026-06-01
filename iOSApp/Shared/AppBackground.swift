import SwiftUI

struct AppBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        if colorScheme == .dark {
            LiquidBackground()
        } else {
            Color(.systemGroupedBackground).ignoresSafeArea()
        }
    }
}