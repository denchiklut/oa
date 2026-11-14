import SwiftUI

/// Arc's loading indicator (`ScrimLoadingIndicatorView`) with its values: a 48 by 4 pt pill that pulses every 1.6 s;
/// a load still going after two pulses stretches it into a 128 pt track that a bar crosses every 1.125 s; one that
/// runs 30 s stops showing. Arc's resting grabber is left out.
struct LoadingIndicator: View {
    private static let size = CGSize(width: 128, height: 4)
    private static let pulseWidth: CGFloat = 48
    private static let pulsePeriod = 1.6
    private static let pulsing = 3.2
    private static let sweepPeriod = 1.125
    private static let opacity = 0.92
    /// LIKELY: which of Arc's two numbers is the response isn't recovered.
    private static let spring = Animation.spring(response: 0.92, dampingFraction: 0.8)

    let isLoading: Bool
    @Environment(\.theme) private var theme
    @State private var start: Date?
    @State private var timedOut = false

    var body: some View {
        let showing = isLoading && !timedOut
        TimelineView(.animation(paused: !showing)) { context in
            let elapsed = start.map { context.date.timeIntervalSince($0) } ?? 0
            let sweep = showing && elapsed >= Self.pulsing ? elapsed - Self.pulsing : nil
            let progress = !showing ? 0 : sweep == nil ? 0.5 - 0.5 * cos(2 * .pi * elapsed / Self.pulsePeriod) : 1
            Capsule()
                .fill(theme.foreground.opacity(sweep == nil ? Self.opacity * progress : theme.loadingTrackOpacity))
                .overlay(alignment: .leading) {
                    if let sweep { bar(at: sweep.truncatingRemainder(dividingBy: Self.sweepPeriod)) }
                }
                .clipShape(Capsule())
                .frame(width: sweep == nil ? Self.pulseWidth : Self.size.width, height: Self.size.height)
                .scaleEffect(0.88 + 0.12 * progress)
                .frame(width: Self.size.width, height: Self.size.height)
                .animation(Self.spring, value: sweep == nil)
                .animation(Self.spring, value: showing)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: isLoading, initial: true) { _, isLoading in
            guard isLoading else { return }
            start = Date()
            timedOut = false
        }
        .task(id: start) {
            guard start != nil else { return }
            try? await Task.sleep(for: .seconds(30))
            if !Task.isCancelled { timedOut = true }
        }
    }

    /// Each end crosses in a third of the period, the leading one first; nothing shows for the last third.
    private func bar(at time: TimeInterval) -> some View {
        let third = Self.sweepPeriod / 3
        let end = time < third ? time / third : time < 2 * third ? 1 : 0
        let start = time >= third && time < 2 * third ? (time - third) / third : 0
        return Capsule()
            .fill(theme.foreground.opacity(Self.opacity))
            .frame(width: max(0, end - start) * Self.size.width, height: Self.size.height)
            .offset(x: start * Self.size.width)
    }
}
