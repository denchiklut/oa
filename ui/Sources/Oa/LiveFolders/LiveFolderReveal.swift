import SwiftUI

struct LiveFolderReveal: ViewModifier {
    static let duration = 0.65
    let start: Date?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if let start, !reduceMotion {
            TimelineView(.animation) { tick in
                let elapsed = max(0, tick.date.timeIntervalSince(start))
                content
                    .mask {
                        Canvas { context, size in
                            let edge = (size.width + 16) * min(1, elapsed / 0.24)
                            let gradient = Gradient(colors: [.white, .white.opacity(0.2)])
                            context.fill(
                                Path(CGRect(origin: .zero, size: size)),
                                with: .linearGradient(
                                    gradient, startPoint: CGPoint(x: edge - 16, y: 0),
                                    endPoint: CGPoint(x: edge, y: 0)))
                        }
                    }
                    .overlay {
                        Canvas { context, size in
                            let titleWidth = size.width - 56
                            for index in 0..<24 {
                                let position = Double(index) / 23
                                let age = (elapsed - position * 0.38) / 0.27
                                guard age >= 0, age < 1 else { continue }
                                let spread = sin(Double(index) * 17.3)
                                let x = (titleWidth + 34) * position + age * 18
                                let y = size.height / 2 + spread * (2 + age * 16) + age * age * 5
                                let radius = (index.isMultiple(of: 4) ? 1.5 : 0.9) * (1 - age * 0.5)
                                let dot = CGRect(x: x - radius, y: y - radius, width: 2 * radius, height: 2 * radius)
                                context.fill(Path(ellipseIn: dot), with: .color(.white.opacity(0.8 * (1 - age))))
                            }
                        }
                        .padding(.vertical, -12)
                        .padding(.trailing, -56)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                    }
            }
        } else {
            content
        }
    }
}
