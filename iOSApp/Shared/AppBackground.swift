import SwiftUI

struct AppBackground: View {
    var body: some View {
        #if os(iOS)
        LiquidBackground()
        #else
        Color.clear
        #endif
    }
}