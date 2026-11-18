import SwiftUI

/// Arc's `EdgeFeedbackView` on the sidebar's trailing edge for the new-Space pull, 85 pt wide. With `reveal` a radial
/// glow twice the view's width slides in until it is centred on the edge, at twice the reveal's opacity, and a 30 pt
/// `CircularProgressView` with a plus slides from 5 pt outside the edge to 12 pt inside. Its ring fills with
/// `progress`, and it is activated once armed.
struct EdgeFeedbackView: View {
    private static let width: CGFloat = 85

    let progress: CGFloat
    let reveal: CGFloat
    @Environment(\.theme) private var theme

    var body: some View {
        let key = theme.cutout.opacity(0.22)
        ZStack(alignment: .topLeading) {
            EllipticalGradient(colors: [key, key.opacity(0)])
                .frame(width: 2 * Self.width)
                .offset(x: (Self.width - 10) * (1 - reveal))
                .opacity(min(2 * reveal, 1))
            CircularProgressView(symbol: "plus", progress: progress, isActivated: progress >= 1)
                .frame(maxHeight: .infinity)
                .offset(x: Self.width + 5 - 47 * reveal)
                .opacity(min(reveal / 0.2, 1))
        }
        .frame(width: Self.width, alignment: .topLeading)
        .frame(maxHeight: .infinity)
        .clipped()
        .opacity(reveal > 0.001 ? 1 : 0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
