import SwiftUI

/// Arc's `SplashView` after Create Space, as measured on Arc: once the panel has faded, a 49 pt white tile with the new
/// Space's icon grows in 45 % of the way down the sidebar, holds, then flies into the Space's place in the dock,
/// shrinking to 20 pt, and the Space is made 1.28 s after the click.
struct SpaceCreationSplashView: View {
    private enum Phase { case hidden, shown, landed }

    let icon: String
    /// The dock's place for the new Space, in the sidebar's coordinates.
    let target: CGPoint
    let complete: () -> Void
    @State private var phase = Phase.hidden

    var body: some View {
        GeometryReader { geometry in
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(.white)
                .frame(width: 49, height: 49)
                .overlay {
                    SpaceIconGlyph(icon: icon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.black.opacity(0.8))
                }
                .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
                .scaleEffect(phase == .hidden ? 35.0 / 49 : phase == .landed ? 20.0 / 49 : 1)
                .opacity(phase == .hidden ? 0 : 1)
                .position(
                    phase == .landed ? target : CGPoint(x: geometry.size.width / 2, y: geometry.size.height * 0.45))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task {
            try? await Task.sleep(for: .milliseconds(280))
            withAnimation(.easeOut(duration: 0.12)) { phase = .shown }
            try? await Task.sleep(for: .milliseconds(600))
            withAnimation(.easeIn(duration: 0.3)) { phase = .landed }
            try? await Task.sleep(for: .milliseconds(400))
            complete()
        }
    }
}
