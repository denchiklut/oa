import AppKit

/// Arc's `ModalWindowLayoutMode`.
enum ModalWindowLayoutMode {
    /// See-through, without a shadow and as big as its screen, the card at `contentRect` on the screen.
    case screen(contentRect: NSRect)
    case intrinsic(rect: NSRect)
}

/// Arc's `ModalV2HostView`: the window's card. It takes no click while it moves.
final class ModalV2HostView: NSView {
    var isInteractive = true

    override func hitTest(_ point: NSPoint) -> NSView? { isInteractive ? super.hitTest(point) : nil }
}

/// Arc's `ModalWindowLayoutController`, with its host's present and dismiss. A link's Little window covers its screen
/// while its card grows out of the point it was opened from and shrinks back into it, so the card is never cut to the
/// frame it ends in.
@MainActor
final class ModalWindowLayoutController {
    private weak var window: NSWindow?
    private let card: ModalV2HostView
    private var background: NSColor?
    private(set) var isScreenSized = false
    private var transitions = 0

    /// Arc's `fullbleed` host: these stay through a transition.
    private static let cornerRadius: CGFloat = 10
    private static let shadowOpacity: Float = 0.475
    /// Arc's `tweenFromSource`: the card starts as wide as this, at its own proportions.
    private static let sourceWidth: CGFloat = 20

    init(window: NSWindow, card: ModalV2HostView) {
        self.window = window
        self.card = card
        card.layer?.shadowColor = .black
        // Oa's own: how far the shadow spreads wasn't read in Arc.
        card.layer?.shadowRadius = 22
        card.layer?.shadowOffset = CGSize(width: 0, height: -10)
        card.layer?.shadowOpacity = 0
    }

    func apply(_ mode: ModalWindowLayoutMode) {
        guard let window, let root = card.superview else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        switch mode {
        case .screen(let contentRect):
            if !isScreenSized { background = window.backgroundColor }
            isScreenSized = true
            window.hasShadow = false
            window.isOpaque = false
            window.backgroundColor = .clear
            // Arc takes the window's screen, which a window not yet shown hasn't.
            let screen = NSScreen.screens.max {
                $0.frame.intersection(contentRect).width < $1.frame.intersection(contentRect).width
            }
            if let frame = (screen ?? window.screen ?? .main)?.frame { window.setFrame(frame, display: true) }
            card.autoresizingMask = []
            card.frame = root.convert(window.convertFromScreen(contentRect), from: nil)
            card.subviews.first?.layer?.cornerRadius = Self.cornerRadius
            card.layer?.shadowPath = CGPath(
                roundedRect: card.bounds, cornerWidth: Self.cornerRadius, cornerHeight: Self.cornerRadius,
                transform: nil)
            card.layer?.shadowOpacity = Self.shadowOpacity
        case .intrinsic(let rect):
            isScreenSized = false
            if window.frame != rect { window.setFrame(rect, display: true) }
            card.frame = root.bounds
            card.autoresizingMask = [.width, .height]
            card.subviews.first?.layer?.cornerRadius = 0
            card.layer?.shadowOpacity = 0
            window.isOpaque = true
            window.backgroundColor = background ?? .windowBackgroundColor
            window.hasShadow = true
        }
        CATransaction.commit()
    }

    /// As Arc's present on Peek's expansion spring, from a point on the screen.
    func present(from source: NSPoint, completion: @escaping () -> Void) {
        transition(at: source, expanding: true, completion: completion)
    }

    /// As Arc's dismiss on Peek's collapse spring, back into the point.
    func dismiss(to source: NSPoint, completion: @escaping () -> Void) {
        transition(at: source, expanding: false, completion: completion)
    }

    private func transition(at source: NSPoint, expanding: Bool, completion: @escaping () -> Void) {
        guard let window, let root = card.superview, let layer = card.layer, card.frame.width > 0 else {
            return completion()
        }
        card.isInteractive = false
        transitions += 1
        CATransaction.begin()
        // A dismiss that takes over a present is the one that finishes.
        CATransaction.setCompletionBlock { [weak self, card, transitions] in
            guard self?.transitions == transitions else { return }
            card.isInteractive = true
            completion()
        }
        // As Arc's with Reduce Motion: the card fades where it is.
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            let fade = CABasicAnimation(keyPath: "opacity")
            (fade.fromValue, fade.toValue) = expanding ? (0, 1) : (1, 0)
            fade.duration = 0.3
            fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
            layer.add(held(fade), forKey: "modalFade")
        } else {
            let point = root.convert(window.convertPoint(fromScreen: source), from: nil)
            let scale = Self.sourceWidth / card.frame.width
            let anchor = layer.position
            let collapsed = CATransform3DConcat(
                CATransform3DMakeScale(scale, scale, 1),
                CATransform3DMakeTranslation(
                    point.x - anchor.x - scale * (card.frame.midX - anchor.x),
                    point.y - anchor.y - scale * (card.frame.midY - anchor.y), 0))
            let transform: (Any, Any) = (collapsed, CATransform3DIdentity)
            let shadow: (Any, Any) = (Float(0), Self.shadowOpacity)
            for (keyPath, values) in [("transform", transform), ("shadowOpacity", shadow)] {
                let spring = Self.spring(keyPath, expanding: expanding)
                (spring.fromValue, spring.toValue) = expanding ? values : (values.1, values.0)
                layer.add(held(spring), forKey: "modal-\(keyPath)")
            }
        }
        CATransaction.commit()
    }

    /// AppKit owns the layer's own values, so a dismiss holds its last frame until the window is ordered out.
    private func held(_ animation: CAAnimation) -> CAAnimation {
        animation.fillMode = .both
        animation.isRemovedOnCompletion = false
        return animation
    }

    /// ARCUI's `CASpringAnimation(dampingRatio:frequencyResponse:)` on Peek's expansion and collapse springs.
    private static func spring(_ keyPath: String, expanding: Bool) -> CASpringAnimation {
        let (response, ratio) = expanding ? (0.245, 0.865) : (0.225, 0.895)
        let spring = CASpringAnimation(keyPath: keyPath)
        spring.mass = 1
        spring.stiffness = pow(2 * .pi / response, 2)
        spring.damping = 4 * .pi * ratio / response
        spring.duration = spring.settlingDuration
        return spring
    }

    /// After a present: the held animations go, with the card where they left it.
    func endTransition() {
        card.layer?.removeAllAnimations()
    }
}
