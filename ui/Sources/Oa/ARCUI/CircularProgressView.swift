import SwiftUI

/// Arc's `CircularProgressView`: a disc in the theme's cutout colour with a symbol in its strongest, ringed in the
/// strongest as far as the progress goes. Activated, the two colours swap in 0.05 s and the disc then bounces once to
/// 1.15; going back swaps them with no bounce.
struct CircularProgressView: View {
    let symbol: String
    var progress: CGFloat = 0
    let isActivated: Bool
    var diameter: CGFloat = 30
    var symbolSize: CGFloat = 16
    @Environment(\.theme) private var theme
    @State private var swapped = false
    @State private var scale = 1.0

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: symbolSize, weight: .medium))
            .foregroundStyle(swapped ? theme.cutout : theme.maxContrast)
            .frame(width: diameter, height: diameter)
            .background(swapped ? theme.maxContrast : theme.cutout, in: Circle())
            .overlay {
                if progress > 0 {
                    Circle()
                        .trim(from: 0, to: min(progress, 1))
                        .stroke(theme.maxContrast, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .padding(1.25)
                }
            }
            .shadow(color: .black.opacity(0.3), radius: 1.5, y: 1)
            .scaleEffect(scale)
            .onAppear { swapped = isActivated }
            .onChange(of: isActivated) { _, activated in
                withAnimation(.linear(duration: 0.05)) { swapped = activated }
                guard activated else { return }
                withAnimation(.easeOut(duration: 0.07).delay(0.05)) {
                    scale = 1.15
                } completion: {
                    withAnimation(.easeIn(duration: 0.07)) { scale = 1 }
                }
            }
    }
}
