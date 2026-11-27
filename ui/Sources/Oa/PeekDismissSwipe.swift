import AppKit
import SwiftUI

@MainActor
@Observable
final class PeekDismissSwipe {
    private(set) var offset: CGFloat = 0
    private(set) var dismissing: UUID?

    @ObservationIgnored private var tracking: UUID?
    @ObservationIgnored private var deferredBegin: NSEvent?
    @ObservationIgnored private var translation: CGFloat = 0
    @ObservationIgnored private var lastRightwardMotion: TimeInterval?
    @ObservationIgnored private var consumesTail = false

    func handle(_ event: NSEvent, pageID: UUID?, startsInContent: @autoclosure () -> Bool, close: @escaping () -> Void)
        -> Bool
    {
        if !event.momentumPhase.isEmpty { return consumesTail }
        let phase = event.phase
        guard event.hasPreciseScrollingDeltas, !phase.isEmpty, !phase.contains(.mayBegin) else { return false }

        if phase.contains(.began) {
            consumesTail = false
            tracking = pageID != nil && dismissing == nil && startsInContent() ? pageID : nil
            deferredBegin = nil
            translation = 0
            lastRightwardMotion = nil
        }
        guard let tracking else { return consumesTail }
        guard tracking == pageID else {
            cancel()
            return consumesTail
        }

        let dx = event.scrollingDeltaX
        let dy = event.scrollingDeltaY
        if !consumesTail {
            // A trackpad can begin with zero deltas. Give the page its original begin if it owns the first movement.
            if dx == 0, dy == 0, phase.contains(.began) {
                deferredBegin = event
                return true
            }
            if dx == 0, dy == 0, phase.contains(.changed) { return true }
            guard dx > abs(dy), !phase.contains(.cancelled), !phase.contains(.ended) else {
                self.tracking = nil
                if let deferredBegin { event.window?.sendEvent(deferredBegin) }
                deferredBegin = nil
                return false
            }
            deferredBegin = nil
            consumesTail = true
        }

        translation += dx
        if dx > 0 { lastRightwardMotion = event.timestamp }
        if dx < 0 { lastRightwardMotion = nil }
        offset = max(0, translation) * 0.06
        guard phase.contains(.ended) || phase.contains(.cancelled) else { return true }

        self.tracking = nil
        // Arc's modal uses 75 pt with rightward velocity, 152 pt without, and displays 6% of the translation.
        let movingRight = lastRightwardMotion.map { event.timestamp - $0 < 0.1 } ?? false
        if phase.contains(.ended), translation >= (movingRight ? 75 : 152) {
            let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            withAnimation(.easeOut(duration: reduceMotion ? 0 : 0.15), completionCriteria: .removed) {
                dismissing = tracking
            } completion: { [weak self] in
                guard self?.dismissing == tracking else { return }
                close()
            }
        } else {
            withAnimation(.spring(duration: 0.2)) { offset = 0 }
        }
        return true
    }

    func validate(pageID: UUID?) {
        if let id = tracking ?? dismissing, id != pageID { cancel() }
    }

    func cancel() {
        if deferredBegin != nil { consumesTail = true }
        tracking = nil
        deferredBegin = nil
        offset = 0
        dismissing = nil
    }
}
