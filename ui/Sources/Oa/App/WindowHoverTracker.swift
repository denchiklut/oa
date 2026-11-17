import AppKit

/// Arc's hover regions around a window, which bring a hidden sidebar out and keep it. A region counts once the
/// pointer has stayed in it for its linger, or paused in it for 0.08 s; once the sidebar is out, being inside one is
/// enough. Points are in the window, from its top left; `inset` is Arc's 10 pt content inset, which sizes the edges.
@MainActor
final class WindowHoverTracker {
    enum Region: CaseIterable {
        case window, innerLeftEdge, outerLeftEdge, innerTopLeftEdge, sidebar, trafficLight

        var linger: TimeInterval { self == .outerLeftEdge ? 0.16 : 0.15 }
        var countsWhenStopped: Bool { self != .sidebar && self != .window }
        var isUpper: Bool { self == .innerTopLeftEdge || self == .trafficLight }
    }

    struct Geometry {
        var size: CGSize
        /// Arc's `ArcSidebar` region: the sidebar's width docked, 80 pt more while it floats, nothing while hidden.
        var sidebarWidth: CGFloat
        var showsToolbar: Bool
        /// The room above the window, up to 50 pt and never into the menu bar, where the pointer still counts.
        var roomAbove: CGFloat
    }

    private static let inset: CGFloat = 10
    private static let stop: TimeInterval = 0.08

    var needsUpdate: () -> Void = {}
    private var entered: [Region: TimeInterval] = [:]
    private var moved: TimeInterval = 0
    private var wake: DispatchWorkItem?

    /// `point` is nil while the window isn't key, which empties every region as Arc's tracker does.
    func move(to point: CGPoint?, in geometry: Geometry) {
        let now = ProcessInfo.processInfo.systemUptime
        moved = now
        guard let point else { return entered.removeAll() }
        for region in Region.allCases {
            if rect(of: region, in: geometry).contains(point) {
                if entered[region] == nil { entered[region] = now }
            } else {
                entered[region] = nil
            }
        }
    }

    /// `active` is whether the sidebar is out already; `allowTop` is Arc's gate on the two upper regions.
    func reveals(active: Bool, allowTop: Bool) -> Bool {
        let now = ProcessInfo.processInfo.systemUptime
        wake?.cancel()
        var next: TimeInterval?
        for (region, since) in entered where region != .window && (allowTop || !region.isUpper) {
            if active { return true }
            let ready = min(since + region.linger, region.countsWhenStopped ? moved + Self.stop : .infinity)
            if ready <= now { return true }
            next = min(next ?? ready, ready)
        }
        if let next {
            let wake = DispatchWorkItem { [weak self] in self?.needsUpdate() }
            self.wake = wake
            DispatchQueue.main.asyncAfter(deadline: .now() + (next - now), execute: wake)
        }
        return false
    }

    private func rect(of region: Region, in geometry: Geometry) -> CGRect {
        let inset = Self.inset
        let (width, height) = (geometry.size.width, geometry.size.height)
        let overWindow = entered[.window] != nil
        let top: CGFloat = geometry.showsToolbar ? 16 : 0
        func column(_ x: CGFloat, _ width: CGFloat) -> CGRect {
            CGRect(x: x, y: top, width: width, height: height - top)
        }
        switch region {
        case .window:
            return CGRect(x: 0, y: 0, width: width, height: height)
        case .innerLeftEdge:
            return overWindow && entered[region] == nil ? column(0, 0.6 * inset) : column(-2 * inset, 3.5 * inset)
        case .outerLeftEdge:
            return overWindow || entered[region] != nil ? column(-250, 250) : column(-50, 50)
        case .innerTopLeftEdge:
            return overWindow
                ? CGRect(x: 0, y: -1.5 * inset, width: 40, height: 3.5 * inset)
                : CGRect(x: 0, y: inset, width: 40, height: 0.6 * inset)
        case .sidebar:
            return column(0, geometry.sidebarWidth)
        case .trafficLight:
            return CGRect(x: -50, y: -geometry.roomAbove, width: 140, height: geometry.roomAbove)
        }
    }
}
