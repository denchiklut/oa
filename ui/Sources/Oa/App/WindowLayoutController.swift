import AppKit
import Observation
import SwiftUI

/// Arc's window layout controller, the window's content: it derives how the sidebar is shown from its mode, the
/// pointer and what the sidebar is in the middle of, and lays the sidebar, the Library and the page out by where its
/// pager is. The Library is the pager's first page, 417 pt of travel from the Space beside it.
@MainActor
@Observable
final class WindowLayoutController: NSViewController {
    /// What keeps a floating sidebar out with the pointer elsewhere, as Arc's does for its menus, drags and popovers.
    enum Hold { case menu, drag, popover }

    /// As measured in Arc: a floating sidebar is this far in from the window's left, top and bottom.
    static let floatingInset: CGFloat = 5
    private static let homeWidth: CGFloat = 417
    /// The Library opening and closing from a button, as measured in Arc: critically damped.
    private static let homeSpring = (response: 0.205, damping: 1.0)
    /// Arc's lock and unlock: the sidebar and the page change frames together, over 0.08 s on this curve.
    private static let lockAnimation = Animation.timingCurve(0.25, 0.46, 0.45, 0.94, duration: 0.08)
    /// The floating panel's slide as measured in Arc: its code reads a period of 0.18 s at the same damping.
    private static let hoverAnimation = Animation.spring(response: 0.17, dampingFraction: 0.8)

    @ObservationIgnored let model: WindowModel
    private(set) var size = CGSize.zero
    private(set) var sidebarPresentation: SidebarPresentation
    /// Whether the sidebar is drawn as the floating panel. A docked one slides out as it is and becomes the panel
    /// once gone, as Arc moves it into the panel's container after the slide.
    private(set) var sidebarIsPanel: Bool
    /// The width a drag on the sidebar's edge is at, the layout's own until the drag ends, as in Arc.
    private var resizingWidth: CGFloat?
    /// As Arc's: a docked sidebar dragged below its collapse width shows as hidden, and hides if let go there.
    private var isPreviewingGestureHiddenSidebar = false
    @ObservationIgnored private var resize: SidebarResizeState?
    /// Arc's pager over the window's pages, and where it is.
    @ObservationIgnored private let pager = PageSwipeController<WindowLayoutPage>()
    private var pagerPosition = homeWidth
    /// The Space whose page is beside the Library's, as Arc's pager starts its Space pages from one: the window's
    /// Space on the way into the Library and out of it, so neither passes through the Spaces before it, and the first
    /// Space otherwise.
    private var leadingSpace = 0
    /// The Space the pages last came to rest on. As Arc sends the settled theme only after the pages' animation, the
    /// chrome keeps this Space's appearance until they rest again.
    private var restingSpaceID: UUID?
    @ObservationIgnored private let hover = WindowHoverTracker()
    @ObservationIgnored private var holds: Set<Hold> = []
    @ObservationIgnored private var monitor: Any?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    init(model: WindowModel) {
        self.model = model
        sidebarPresentation = model.sidebarMode == .anchored ? .locked : .hidden
        sidebarIsPanel = model.sidebarMode != .anchored
        super.init(nibName: nil, bundle: nil)
        hover.needsUpdate = { [weak self] in self?.updatePresentation() }
        pager.windowProvider = { [weak self] in self?.viewIfLoaded?.window }
        pager.positionUpdateHandler = { [weak self] in self?.pagerPosition = $0 }
        pager.pageSelectionHandler = { [weak self] page in
            guard let model = self?.model else { return }
            switch page {
            case .home:
                model.viewLibrary()
            case .space(let id):
                model.exitLibrary()
                model.selectSpace(id)
            }
        }
        pager.trackingStateUpdateHandler = { [weak self] in self?.updatePages() }
        pager.scrollingShouldBegin = { [weak self] in self?.scrollingShouldBegin($0) ?? false }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let content = NSHostingView(rootView: BrowserWindowView(model: model, layout: self))
        content.sizingOptions = []
        view = content
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        if size != view.bounds.size { size = view.bounds.size }
    }

    /// As Arc's: scroll views send up the horizontal scrolling they have no use for, which the pager takes.
    override func wantsForwardedScrollEvents(for axis: NSEvent.GestureAxis) -> Bool { axis == .horizontal }

    override func scrollWheel(with event: NSEvent) {
        if !pager.scrollWheel(with: event) { super.scrollWheel(with: event) }
    }

    /// Arc's gate on a swipe: between Spaces it starts over the sidebar, and with the Library in view anywhere.
    private func scrollingShouldBegin(_ event: NSEvent) -> Bool {
        guard libraryProgress == 0 else { return true }
        let point = CGPoint(x: event.locationInWindow.x, y: view.bounds.height - event.locationInWindow.y)
        let inset = sidebarPresentation == .floating ? Self.floatingInset : 0
        let sidebar = CGRect(x: 0, y: 0, width: sidebarWidth, height: view.bounds.height - 2 * inset)
        return sidebarPresentation != .hidden && sidebar.offsetBy(dx: inset, dy: inset).contains(point)
    }

    /// How far the Space pages are scrolled, from the first Space's.
    var sidebarScrollOffset: CGFloat {
        CGFloat(leadingSpace) * sidebarWidth + max(pagerPosition - Self.homeWidth, 0)
    }

    /// Arc's progress into the Library: 0 among the Spaces, 1 with the Library open, more past it.
    var libraryProgress: CGFloat { max(Self.homeWidth - pagerPosition, 0) / Self.homeWidth }

    /// The theme the chrome takes its appearance from: the resting Space's.
    var restingTheme: WindowTheme {
        (model.state.space(restingSpaceID ?? model.selectedSpaceID) ?? model.space)?.theme ?? .default
    }

    /// Arc's `.transitioning(from:to:progress:)` for the theme: the Spaces either side of where the pages are and how
    /// far between, nil while they rest on one.
    var themeTransition: (from: WindowTheme, to: WindowTheme, progress: CGFloat)? {
        let page = sidebarScrollOffset / sidebarWidth
        let spaces = model.state.spaces
        // As Arc and open-arch: pages moved to a Space further away than the next blend the resting Space's theme
        // straight into the selected one's, never through the themes of the Spaces between.
        if !pager.isTracking, let from = spaces.firstIndex(where: { $0.id == restingSpaceID }),
            let to = spaces.firstIndex(where: { $0.id == model.selectedSpaceID }), from != to
        {
            let progress = min(max((page - CGFloat(from)) / CGFloat(to - from), 0), 1)
            return (spaces[from].theme, spaces[to].theme, progress)
        }
        let index = Int(page.rounded(.down))
        let progress = page - CGFloat(index)
        guard progress > 0.001, progress < 0.999, index >= 0, index + 1 < spaces.count else { return nil }
        return (spaces[index].theme, spaces[index + 1].theme, progress)
    }

    private func updatePages() {
        let spaces = model.state.spaces
        let index = spaces.firstIndex { $0.id == model.selectedSpaceID } ?? 0
        let target: WindowLayoutPage = model.library == nil ? .space(model.selectedSpaceID) : .home
        let throughHome = target == .home || pager.selectedPageID == .home
        if pager.selectedPageID != target {
            leadingSpace = throughHome ? index : 0
        } else if target != .home, !pager.isTracking, !pager.isAnimating {
            leadingSpace = 0
        }
        let home = PageSwipeController<WindowLayoutPage>.Page(id: .home, width: Self.homeWidth)
        pager.setPages(
            [home] + spaces[min(leadingSpace, spaces.count)...].map { .init(id: .space($0.id), width: sidebarWidth) },
            selecting: target)
        if pager.selectedPageID != target {
            let settle = PageSwipeController<WindowLayoutPage>.settle
            pager.select(target, animated: true, spring: throughHome ? Self.homeSpring : settle)
        }
        if !pager.isTracking, !pager.isAnimating, restingSpaceID != model.selectedSpaceID {
            restingSpaceID = model.selectedSpaceID
        }
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        guard monitor == nil, let window = view.window else { return }
        window.acceptsMouseMovedEvents = true
        let events: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .scrollWheel]
        monitor = NSEvent.addLocalMonitorForEvents(matching: events) { [weak self] event in
            guard let self else { return event }
            // A wheel's ticks have no phases, and a scroll view keeps those to itself: the pager gets them here.
            if event.type == .scrollWheel {
                let isWheel = event.phase.isEmpty && event.momentumPhase.isEmpty && event.window === view.window
                return isWheel && pager.scrollWheel(with: event) ? nil : event
            }
            // A drag from the sidebar has ended by the time the pointer moves again.
            if event.type == .mouseMoved { holds.remove(.drag) }
            trackPointer()
            return event
        }
        func observe(
            _ name: Notification.Name, _ object: NSWindow?,
            _ handle: @escaping @MainActor @Sendable (WindowLayoutController) -> Void
        ) {
            observers.append(
                NotificationCenter.default.addObserver(forName: name, object: object, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self.map(handle) }
                })
        }
        observe(NSWindow.didBecomeKeyNotification, window) { $0.trackPointer() }
        observe(NSWindow.didResignKeyNotification, window) { $0.trackPointer() }
        observe(NSMenu.didBeginTrackingNotification, nil) { $0.setHold(.menu, $0.view.window?.isKeyWindow == true) }
        observe(NSMenu.didEndTrackingNotification, nil) { $0.setHold(.menu, false) }
        observeModel()
    }

    override func viewDidDisappear() {
        super.viewDidDisappear()
        monitor.map(NSEvent.removeMonitor)
        monitor = nil
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
    }

    /// The pointer is measured again in the new mode's regions, so a sidebar hidden from under it stays hidden, as
    /// Arc's did with the pointer left on the toggle.
    func setSidebarMode(_ mode: SidebarMode) {
        model.setSidebarMode(mode)
        trackPointer()
    }

    func toggleSidebar() {
        setSidebarMode(model.sidebarMode == .anchored ? .noChrome : .anchored)
    }

    var sidebarWidth: CGFloat { resizingWidth ?? model.sidebarWidth }

    func libraryWidth(for section: LibrarySection) -> CGFloat {
        LibraryView.width(for: section, spaces: model.state.spaces.count, in: size.width)
    }

    func resizeSidebar(by translation: CGFloat, velocity: CGFloat) {
        var state = resize ?? SidebarResizeState(width: model.sidebarWidth, mode: model.sidebarMode)
        let width = state.width(for: translation, velocity: velocity)
        resize = state
        if let width { resizingWidth = width }
        isPreviewingGestureHiddenSidebar = width == nil
        updatePages()
        updatePresentation()
    }

    /// As Arc: a sidebar let go while it previews as hidden hides, keeping the width it had.
    func endSidebarResize() {
        if isPreviewingGestureHiddenSidebar {
            model.setSidebarMode(.noChrome)
        } else if let resizingWidth {
            model.setSidebarWidth(resizingWidth)
        }
        (resize, resizingWidth, isPreviewingGestureHiddenSidebar) = (nil, nil, false)
        updatePages()
        trackPointer()
    }

    func resetSidebarWidth() {
        model.setSidebarWidth(SidebarResizeState.resetWidth)
    }

    func setHold(_ hold: Hold, _ held: Bool) {
        if held { holds.insert(hold) } else { holds.remove(hold) }
        updatePresentation()
    }

    /// Oa's own, after open-arch: a tab opened from the Library leaves the panel away until the pointer asks for it.
    func dismissSidebar() {
        guard sidebarPresentation == .floating else { return }
        sidebarPresentation = .hidden
        trackPointer()
    }

    private func observeModel() {
        withObservationTracking {
            _ = (model.sidebarMode, model.library, model.selectedTabID, model.selectedSpaceID, model.sidebarWidth)
            _ = model.permissionRequest
            _ = model.state.spaces
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeModel() }
        }
        updatePages()
        updatePresentation()
    }

    private func trackPointer() {
        guard let window = view.window else { return }
        var point: CGPoint?
        if window.isKeyWindow, NSApplication.shared.isActive {
            let location = window.mouseLocationOutsideOfEventStream
            point = CGPoint(x: location.x, y: view.bounds.height - location.y)
        }
        let menuBar = NSApplication.shared.mainMenu?.menuBarHeight ?? 0
        let ceiling = min((window.screen?.frame.height ?? 0) - menuBar, window.frame.maxY + 50)
        let roomAbove = ceiling - window.frame.maxY
        hover.move(
            to: point,
            in: WindowHoverTracker.Geometry(
                size: view.bounds.size,
                sidebarWidth: model.sidebarMode == .anchored && !isPreviewingGestureHiddenSidebar
                    ? sidebarWidth : sidebarPresentation == .floating ? sidebarWidth + 80 : 0,
                showsToolbar: PageToolbar.isShown, roomAbove: roomAbove > 10 ? roomAbove : 0))
        updatePresentation()
    }

    /// Arc's order: a docked sidebar is locked; a hidden one floats while the pointer is in a hover region, while
    /// nothing is selected, while a permission prompt needs the address field it hangs from, and while the sidebar
    /// holds it. Oa's own, by the author's decision, after open-arch: the Library doesn't hide it as Arc's does, so
    /// a panel the pointer is still over comes back with the swipe out of the Library.
    private var derivedPresentation: SidebarPresentation {
        if model.sidebarMode == .anchored { return isPreviewingGestureHiddenSidebar ? .hidden : .locked }
        let floating = sidebarPresentation == .floating
        let allowTop = !PageToolbar.isShown || model.selectedTabID != nil
        let prompts = model.permissionRequest != nil && !PageToolbar.isShown
        if hover.reveals(active: floating, allowTop: allowTop) || model.selectedTabID == nil || prompts {
            return .floating
        }
        return floating && !holds.isEmpty ? .floating : .hidden
    }

    private func updatePresentation() {
        let (old, new) = (sidebarPresentation, derivedPresentation)
        guard new != old else { return }
        switch (old, new) {
        case (.locked, .hidden):
            withAnimation(Self.lockAnimation) {
                sidebarPresentation = new
            } completion: { [weak self] in
                if self?.sidebarPresentation != .locked { self?.sidebarIsPanel = true }
            }
        case (.hidden, .locked):
            // One transaction: SwiftUI flushed a separate unanimated change while the presentation was being set,
            // drew the old value and missed the new one, so ⌘S sometimes left the sidebar hidden.
            withAnimation(Self.lockAnimation) {
                sidebarIsPanel = false
                sidebarPresentation = new
            }
        case (.floating, .locked):
            withAnimation(Self.lockAnimation) {
                sidebarPresentation = new
                sidebarIsPanel = false
            }
        case (.locked, .floating):
            sidebarPresentation = new
            sidebarIsPanel = true
        default:
            withAnimation(Self.hoverAnimation) { sidebarPresentation = new }
        }
    }
}
