import SwiftUI

struct LiquidBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var animate = false

    var body: some View {
        ZStack {
            if colorScheme == .dark {
                // Dark mode base gradient
                LinearGradient(
                    colors: [
                        Color(red: 0.04, green: 0.05, blue: 0.11),
                        Color(red: 0.01, green: 0.02, blue: 0.04)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                
                // Dark mode glowing mesh circles
                Circle()
                    .fill(Color(red: 0.55, green: 0.36, blue: 0.96).opacity(0.12))
                    .frame(width: 400, height: 400)
                    .blur(radius: 80)
                    .offset(x: animate ? 100 : -100, y: animate ? -120 : 120)
                
                Circle()
                    .fill(Color(red: 0.06, green: 0.73, blue: 0.51).opacity(0.08))
                    .frame(width: 320, height: 320)
                    .blur(radius: 70)
                    .offset(x: animate ? -120 : 100, y: animate ? 100 : -100)
            } else {
                // Light mode base gradient
                LinearGradient(
                    colors: [
                        Color(red: 0.95, green: 0.96, blue: 0.98),
                        Color(red: 0.88, green: 0.91, blue: 0.96)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                
                // Light mode glowing mesh circles (soft/pastels)
                Circle()
                    .fill(Color(red: 0.72, green: 0.55, blue: 0.96).opacity(0.20))
                    .frame(width: 380, height: 380)
                    .blur(radius: 70)
                    .offset(x: animate ? 80 : -80, y: animate ? -100 : 100)
                
                Circle()
                    .fill(Color(red: 0.20, green: 0.82, blue: 0.76).opacity(0.14))
                    .frame(width: 300, height: 300)
                    .blur(radius: 65)
                    .offset(x: animate ? -100 : 80, y: animate ? 80 : -80)
            }
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeInOut(duration: 8.0).repeatForever(autoreverses: true)) {
                animate.toggle()
            }
        }
    }
}