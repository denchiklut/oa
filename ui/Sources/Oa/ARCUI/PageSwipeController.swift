import AppKit

/// Arc's pager: pages side by side along one position in points, moved by a two-finger swipe at half the fingers'
/// distance, one page a gesture at most. On lift a flick goes to the next page its way, a held release to the nearest
/// page, and the page is selected before the spring settles on it. A wheel flips one page.
@MainActor
final class PageSwipeController<PageID: Hashable & Sendable> {
    struct Page: Equatable {
        let id: PageID
        let width: CGFloat
    }

    /// The settle as measured in Arc after a held release: its code reads 0.4 and 1.
    static var settle: (response: Double, damping: Double) { (0.22, 0.93) }

    var windowProvider: () -> NSWindow? = { nil }
    var positionUpdateHandler: (CGFloat) -> Void = { _ in }
    var pageSelectionHandler: (PageID) -> Void = { _ in }
    var trackingStateUpdateHandler: () -> Void = {}
    var scrollingShouldBegin: (NSEvent) -> Bool = { _ in true }

    private(set) var pages: [Page] = []
    private(set) var selectedPageID: PageID?
    private(set) var isTracking = false { didSet { if isTracking != oldValue { trackingStateUpdateHandler() } } }
    private(set) var isAnimating = false { didSet { if isAnimating != oldValue { trackingStateUpdateHandler() } } }
    /// What is shown: past the first or last page it gives like a rubber band.
    private(set) var presentationPosition: CGFloat = 0 {
        didSet { if presentationPosition != oldValue { positionUpdateHandler(presentationPosition) } }
    }
    private var position: CGFloat = 0
    private var beginIndex = 0
    private var began: TimeInterval = 0
    private var samples: [(time: TimeInterval, position: CGFloat)] = []
    private var wheel: (sum: CGFloat, time: TimeInterval, flipped: TimeInterval) = (0, 0, 0)
    private var spring:
        (from: CGFloat, to: CGFloat, velocity: CGFloat, time: Double, last: CFTimeInterval?, shape: (Double, Double))?
    private let ticker = DisplayLinkTicker()

    func origin(of id: PageID) -> CGFloat? {
        pages.firstIndex { $0.id == id }.map(origin(at:))
    }

    /// At rest the pager stays on its page as the pages around it change.
    func setPages(_ pages: [Page], selecting id: PageID) {
        guard pages != self.pages || selectedPageID == nil else { return }
        self.pages = pages
        if selectedPageID.flatMap(origin(of:)) == nil { selectedPageID = id }
        guard !isTracking else { return }
        stop()
        guard let origin = selectedPageID.flatMap(origin(of:)) else { return }
        (position, presentationPosition) = (origin, origin)
    }

    /// A nil velocity starts the spring at rest, as a click or a key does.
    func select(
        _ id: PageID, animated: Bool, velocity: CGFloat? = nil, spring shape: (Double, Double) = settle
    ) {
        guard origin(of: id) != nil else { return }
        let changed = selectedPageID != id
        selectedPageID = id
        if changed { pageSelectionHandler(id) }
        // Stopping tells the owner, which may lay the pages out again: the page's place is read after.
        stop()
        guard let target = origin(of: id) else { return }
        position = target
        guard animated, presentationPosition != target, let window = windowProvider() else {
            return presentationPosition = target
        }
        spring = (presentationPosition, target, velocity ?? 0, 0, nil, shape)
        isAnimating = true
        ticker.start(in: window) { [weak self] in self?.step() }
    }

    /// Whether the pager took the event. A scroll view forwards only the start of a swipe it has no use for, so the
    /// pager reads the rest from the window itself, as Arc's does, and hands on what isn't scrolling.
    func scrollWheel(with event: NSEvent) -> Bool {
        guard event.momentumPhase.isEmpty else { return true }
        guard !event.phase.isEmpty else { return flip(with: event) }
        guard event.phase.contains(.began), abs(event.scrollingDeltaY) <= abs(event.scrollingDeltaX) else {
            return false
        }
        // A scroll view at its end hands the same start over a second time once the pager is done with the swipe.
        guard event.timestamp != began else { return true }
        guard scrollingShouldBegin(event), let window = windowProvider() else { return false }
        began = event.timestamp
        isTracking = true
        stop()
        position = unbanded(presentationPosition)
        beginIndex = nearestIndex
        samples = []
        while isTracking,
            let next = window.nextEvent(matching: .any, until: .distantFuture, inMode: .eventTracking, dequeue: true)
        {
            guard next.type == .scrollWheel else {
                NSApplication.shared.sendEvent(next)
                continue
            }
            // As Arc's loop: a swipe that has begun keeps every movement, whichever way it leans, until the lift.
            if next.phase.contains(.changed) {
                position -= 0.5 * next.scrollingDeltaX
                samples = samples.filter { next.timestamp - $0.time <= 0.1 } + [(next.timestamp, position)]
                presentationPosition = banded(position)
            } else if next.phase.contains(.ended) || next.phase.contains(.cancelled) {
                end(at: next.timestamp)
            }
        }
        return true
    }

    private func origin(at index: Int) -> CGFloat {
        pages[..<index].reduce(0) { $0 + $1.width }
    }

    private var range: ClosedRange<CGFloat> { 0...(pages.isEmpty ? 0 : origin(at: pages.count - 1)) }

    /// Arc's rubber band and its inverse, for a spring caught past an end.
    private func banded(_ position: CGFloat) -> CGFloat {
        let edge = min(max(position, range.lowerBound), range.upperBound)
        let over = abs(position - edge)
        return edge + (position < edge ? -1 : 1) * 255 * (1 - 1 / (1 + 0.15 * over / 255))
    }

    private func unbanded(_ shown: CGFloat) -> CGFloat {
        let edge = min(max(shown, range.lowerBound), range.upperBound)
        let over = min(abs(shown - edge), 254)
        return edge + (shown < edge ? -1 : 1) * 255 * (1 / (1 - over / 255) - 1) / 0.15
    }

    private var nearestIndex: Int {
        pages.indices.min { abs(origin(at: $0) - position) < abs(origin(at: $1) - position) } ?? 0
    }

    /// Tracking ends once the settle has begun, so the owner never sees the pager at rest in between.
    private func end(at time: TimeInterval) {
        defer { isTracking = false }
        guard !pages.isEmpty else { return }
        let recent = samples.filter { time - $0.time <= 0.1 }
        var velocity: CGFloat = 0
        if let first = recent.first, let last = recent.last, last.time > first.time {
            velocity = (last.position - first.position) / (last.time - first.time)
        }
        var index = nearestIndex
        if abs(velocity) >= 5 {
            index = (pages.indices.last { origin(at: $0) <= position } ?? 0) + (velocity > 0 ? 1 : 0)
        }
        index = min(max(index, beginIndex - 1, 0), beginIndex + 1, pages.count - 1)
        let toward = (origin(at: index) - presentationPosition) * velocity > 0
        select(pages[index].id, animated: true, velocity: toward ? velocity : 0)
    }

    /// A wheel has no phases: a unit of travel flips a page, then it is ignored for a quarter second.
    private func flip(with event: NSEvent) -> Bool {
        guard abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY), scrollingShouldBegin(event) else { return false }
        let time = event.timestamp
        guard time - wheel.flipped > 0.25 else { return true }
        wheel.sum = (time - wheel.time > 0.05 ? 0 : wheel.sum) + event.scrollingDeltaX
        wheel.time = time
        guard abs(wheel.sum) >= 1, let selected = selectedPageID.flatMap({ id in pages.firstIndex { $0.id == id } })
        else { return true }
        let index = min(max(selected + (wheel.sum < 0 ? 1 : -1), 0), pages.count - 1)
        wheel = (0, time, time)
        select(pages[index].id, animated: true)
        return true
    }

    private func stop() {
        ticker.stop()
        spring = nil
        isAnimating = false
    }

    private func step() {
        guard var spring else { return }
        // The spring's clock starts with its first frame and counts a long frame as two, so what selecting the page
        // or drawing the Library for the first time costs delays the motion rather than skipping it.
        let now = CACurrentMediaTime()
        spring.time += min(now - (spring.last ?? now), 1.0 / 60)
        spring.last = now
        self.spring = spring
        let time = spring.time
        let (response, damping) = spring.shape
        let omega = 2 * Double.pi / response
        let decay = exp(-damping * omega * time)
        let (start, velocity) = (Double(spring.from - spring.to), Double(spring.velocity))
        var offset: Double
        if damping < 1 {
            let damped = omega * (1 - damping * damping).squareRoot()
            offset =
                decay
                * (start * cos(damped * time) + (velocity + damping * omega * start) / damped * sin(damped * time))
        } else {
            offset = decay * (start + (velocity + omega * start) * time)
        }
        // Done once what is left can't be seen, and the spring has had the time to turn back.
        if abs(offset) < 0.05, time > response / 2 { offset = 0 }
        presentationPosition = spring.to + offset
        if offset == 0 { stop() }
    }
}
