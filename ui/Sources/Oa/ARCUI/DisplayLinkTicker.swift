import AppKit

/// The window's display link, which wants an Objective-C target.
@MainActor
final class DisplayLinkTicker: NSObject {
    private var link: CADisplayLink?
    private var tick: () -> Void = {}

    func start(in window: NSWindow, tick: @escaping () -> Void) {
        self.tick = tick
        guard link == nil else { return }
        link = window.displayLink(target: self, selector: #selector(fire))
        link?.add(to: .main, forMode: .common)
    }

    func stop() {
        link?.invalidate()
        link = nil
    }

    @objc private func fire() { tick() }
}
