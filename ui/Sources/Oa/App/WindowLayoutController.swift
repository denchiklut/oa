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
    /// The pager settling back once the Create a Space page goes, as measured in Arc.
    private static let spaceCreationCloseSpring = (response: 0.175, damping: 1.0)
    /// Lock and unlock, the sidebar and the page changing frames together. Oa's own, by the author's decision:
    /// open-arch's 0.18 s ease in and out, not Arc's measured 0.08 s on (0.25, 0.46, 0.45, 0.94).
    private static let lockAnimation = Animation.easeInOut(duration: 0.18)
    /// The floating panel's slide as measured in Arc: its code reads a period of 0.18 s at the same damping.
    private static let hoverAnimation = Animation.spring(response: 0.17, dampingFraction: 0.8)

    @ObservationIgnored let model: WindowModel
    private(set) var size = CGSize.zero
    private(set) var sidebarPresentation: SidebarPresentation
    /// Whether the sidebar is drawn as the floating panel, over the page: from the start of undocking to the end of
    /// docking, as open-arch's `isPanel`.
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
    private var restingSpaceID: UUID?
    /// The Spaces' order as the Library opened.
    private var homeOrder: [UUID]?
    /// Arc's new-Space pull: the overshoot past the last Space's page over 22.5 pt fills the feedback view's ring and
    /// arms it, over 15 pt slides it in, through a spring of 0.4 s at 0.8 that the display link drives, as SwiftUI's
    /// don't run while the pager tracks the swipe. Released more than 0.1 s after arming, it opens the Create a Space
    /// panel.
    private(set) var spaceCreationPull: (progress: CGFloat, reveal: CGFloat) = (0, 0)
    @ObservationIgnored private var pullTarget: CGFloat = 0
    @ObservationIgnored private var pullVelocity: CGFloat = 0
    @ObservationIgnored private var pullTick: CFTimeInterval?
    @ObservationIgnored private let pullTicker = DisplayLinkTicker()
    @ObservationIgnored private var pullArmedAt: CFTimeInterval?
    /// As Arc: only a swipe that starts on the last Space, with no panel open, pulls.
    @ObservationIgnored private var pullAllowed: Bool?
    /// Oa's own, by the author's decision, as open-arch: the Create a Space panel opens and closes in place, the page
    /// going and the page coming cross-fading over 0.2 s and the window's theme blending over 0.25 s, where Arc's
    /// pager slides the panel's page in and cuts it away. Only a swipe moves it.
    private var runningFade: SpaceCreationFade?
    @ObservationIgnored private let fadeTicker = DisplayLinkTicker()
    /// The panel as last laid out, to fade it out once it has gone.
    @ObservationIgnored private var laidOutSpaceCreation: SpaceCreationState?
    /// As open-arch: a swipe away from the panel selects its Space once the slide is done, so the panel goes with
    /// the pages already at rest rather than cutting away mid-slide.
    @ObservationIgnored private var pendingSpaceSelection: UUID?
    /// Where this window's Library last left its Spaces row scrolled.
    @ObservationIgnored var spacesPageScroll: CGFloat = 0
    /// The Space whose name shows the icon picker its menu asked for.
    var iconPickerSpaceID: UUID?
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
        pager.positionUpdateHandler = { [weak self] in
            self?.pagerPosition = $0
            self?.updatePull()
            self?.updateDock()
        }
        pager.pageSelectionHandler = { [weak self] page in
            guard let self else { return }
            switch page {
            case .home:
                model.viewLibrary()
            case .space(let id):
                guard model.spaceCreation == nil else { return pendingSpaceSelection = id }
                model.exitLibrary()
                model.selectSpace(id)
            case .spaceCreation:
                pendingSpaceSelection = nil
            }
        }
        pager.trackingStateUpdateHandler = { [weak self] in
            guard let self else { return }
            if pager.isTracking, model.spaceCreation != nil { spaceCreationSwiped = true }
            if !pager.isTracking, !pager.isAnimating, let id = pendingSpaceSelection {
                pendingSpaceSelection = nil
                model.selectSpace(id)
            }
            trackPull()
            updatePages()
        }
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
        guard model.spaceCreation?.phase != .animating, spaceCreationFade == nil else { return false }
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

    /// Arc's sidebar pages in order: one per Space, and while the Create a Space panel is open its page, at the slot
    /// the Space will take.
    var sidebarPages: [WindowLayoutPage] {
        var pages = model.state.spaces.map { WindowLayoutPage.space($0.id) }
        if let index = model.spaceCreationIndex { pages.insert(.spaceCreation, at: index) }
        return pages
    }

    /// Where the sidebar's pages are, in pages from the first.
    var sidebarPage: CGFloat { sidebarScrollOffset / sidebarWidth }

    /// 0 among the Spaces and 1 on the Create a Space page.
    var spaceCreationProgress: CGFloat {
        guard let index = model.spaceCreationIndex else { return 0 }
        return max(0, 1 - abs(sidebarPage - CGFloat(index)))
    }

    /// The dock's share of the Create a Space slot. Oa's own, by the author's decision, as open-arch's
    /// `draftProgress`: it eases to 1 as the panel opens, on its own rather than with the pull's one-frame cut, and
    /// follows the pager once a swipe has moved the panel. Driven here rather than by a SwiftUI animation, which
    /// would also ease the dock's colours from the theme the panel has already cut away from.
    private(set) var dockSpaceCreationProgress: CGFloat = 0
    private var spaceCreationSwiped = false
    @ObservationIgnored private let dockTicker = DisplayLinkTicker()
    @ObservationIgnored private var dockEase: (from: CGFloat, to: CGFloat, start: CFTimeInterval)?

    /// As measured in open-arch: the dock settles in about 0.2 s, easing in and out.
    private func updateDock() {
        if spaceCreationSwiped, model.spaceCreation != nil {
            (dockEase, dockSpaceCreationProgress) = (nil, spaceCreationProgress)
            return dockTicker.stop()
        }
        let target: CGFloat = model.spaceCreation == nil ? 0 : 1
        guard target != (dockEase?.to ?? dockSpaceCreationProgress) else { return }
        guard let window = view.window else { return dockSpaceCreationProgress = target }
        dockEase = (dockSpaceCreationProgress, target, CACurrentMediaTime())
        dockTicker.start(in: window) { [weak self] in
            guard let self, let ease = dockEase else { return }
            let t = min((CACurrentMediaTime() - ease.start) / 0.2, 1)
            dockSpaceCreationProgress = ease.from + (ease.to - ease.from) * Self.ease(t)
            guard t == 1 else { return }
            dockEase = nil
            dockTicker.stop()
        }
    }

    /// Arc's progress into the Library: 0 among the Spaces, 1 with the Library open, more past it.
    var libraryProgress: CGFloat { max(Self.homeWidth - pagerPosition, 0) / Self.homeWidth }

    /// Oa's own, by the author's decision, after open-arch: the Library is in the first Space's theme, blended in
    /// with the Library's progress. Arc's is the window's Space's.
    var libraryTheme: WindowTheme { model.state.spaces.first?.theme ?? .default }

    var spaceCreationFade: SpaceCreationFade? {
        if let runningFade { return runningFade }
        // A frame can be drawn before the pager has caught up with the panel opening or closing: the fade's first.
        if model.spaceCreation != nil, laidOutSpaceCreation == nil, !spaceCreationSwiped {
            return SpaceCreationFade(panel: nil, themes: (theme(of: .space(model.selectedSpaceID)), .default))
        }
        if model.spaceCreation == nil, let panel = laidOutSpaceCreation, panel.phase == .editing,
            pager.selectedPageID == .spaceCreation
        {
            return SpaceCreationFade(panel: panel, themes: (.default, theme(of: .space(model.selectedSpaceID))))
        }
        return nil
    }

    /// Where the URL field is while the Create a Space panel is in: nil where it always is, otherwise drawn over the
    /// pages without taking room, this far across, the Space's page held below it. As open-arch's, it fades with the
    /// page under it and slides with it as a swipe brings it back.
    var addressFieldShift: CGFloat? {
        if spaceCreationFade != nil { return 0 }
        guard model.spaceCreation != nil, spaceCreationSwiped, let index = model.spaceCreationIndex else { return nil }
        let beside = sidebarPage <= CGFloat(index) ? index - 1 : index + 1
        return (CGFloat(beside) - sidebarPage) * sidebarWidth
    }

    /// The theme the sidebar's and the page's chrome take: the Space's, or the default one on the Create a Space
    /// panel. As open-arch, the panel's cross-fade and a swipe away from it switch it halfway.
    var chromeTheme: WindowTheme {
        if let fade = spaceCreationFade { return fade.theme < 0.5 ? fade.themes.from : fade.themes.to }
        guard model.spaceCreation != nil else { return model.space?.theme ?? .default }
        let pages = sidebarPages
        guard spaceCreationSwiped, !pages.isEmpty else { return .default }
        return theme(of: pages[min(max(Int(sidebarPage.rounded()), 0), pages.count - 1)])
    }

    private func theme(of page: WindowLayoutPage) -> WindowTheme {
        if case .space(let id) = page { model.state.space(id)?.theme ?? .default } else { .default }
    }

    var backgroundThemes: (base: WindowTheme, blend: (theme: WindowTheme, progress: CGFloat)?) {
        if let fade = spaceCreationFade { return (fade.themes.from, (fade.themes.to, fade.theme)) }
        let spaces = model.state.spaces
        guard restingSpaceID != nil, !spaces.isEmpty else { return (model.space?.theme ?? .default, nil) }
        let progress = min(libraryProgress, 1)
        guard progress > 0 else { return spaceThemes }
        let beside = spaces[min(leadingSpace, spaces.count - 1)]
        if progress == 1 || beside.id == spaces[0].id { return (libraryTheme, nil) }
        return (beside.theme, (libraryTheme, progress))
    }

    private var spaceThemes: (base: WindowTheme, blend: (theme: WindowTheme, progress: CGFloat)?) {
        let pages = sidebarPages
        guard let restingSpaceID, !pages.isEmpty else { return (model.space?.theme ?? .default, nil) }
        // As Arc: the Create a Space page is in the default theme until one is chosen.
        let themes = pages.map(theme(of:))
        let last = pages.count - 1
        let page = min(max(sidebarPage, 0), CGFloat(last))
        let from: Int
        let to: Int
        // As Arc and open-arch: pages moved to a Space further away than the next blend the resting Space's theme
        // straight into the selected one's, never through the themes of the Spaces between.
        if !pager.isTracking, restingSpaceID != model.selectedSpaceID,
            let source = pages.firstIndex(of: .space(restingSpaceID)),
            let destination = pages.firstIndex(of: .space(model.selectedSpaceID))
        {
            from = source
            to = destination
        } else {
            from = Int(page.rounded(.down))
            to = min(from + 1, last)
        }
        guard from != to else { return (themes[from], nil) }
        let progress = (page - CGFloat(from)) / CGFloat(to - from)
        if progress <= 0 { return (themes[from], nil) }
        if progress >= 1 { return (themes[to], nil) }
        return (themes[from], (themes[to], progress))
    }

    private func updatePages() {
        let spaces = model.state.spaces
        let sidebarPages = sidebarPages
        let index = sidebarPages.firstIndex(of: .space(model.selectedSpaceID)) ?? 0
        if model.spaceCreation == nil { pendingSpaceSelection = nil }
        let target: WindowLayoutPage =
            model.library != nil
            ? .home
            : model.spaceCreation == nil
                ? .space(model.selectedSpaceID) : pendingSpaceSelection.map { .space($0) } ?? .spaceCreation
        // Oa's own: the icon picker goes with its Space's page, from the moment a swipe starts.
        if let id = iconPickerSpaceID, pager.isTracking || target != .space(id) { iconPickerSpaceID = nil }
        let throughHome = target == .home || pager.selectedPageID == .home
        if pager.selectedPageID != target {
            leadingSpace = throughHome ? index : 0
            if target == .home { homeOrder = spaces.map(\.id) }
        } else if target == .home, !pager.isTracking {
            // Oa's own, by the author's decision: Spaces reordered in the Library put the first beside it, so a
            // swipe back lands there.
            let order = spaces.map(\.id)
            if homeOrder == nil { homeOrder = order } else if homeOrder != order { leadingSpace = 0 }
        } else if target != .home, !pager.isTracking, !pager.isAnimating {
            leadingSpace = 0
        }
        if target != .home { homeOrder = nil }
        if model.spaceCreation == nil, spaceCreationSwiped { spaceCreationSwiped = false }
        let home = PageSwipeController<WindowLayoutPage>.Page(id: .home, width: Self.homeWidth)
        let pages =
            [home] + sidebarPages[min(leadingSpace, sidebarPages.count)...].map { .init(id: $0, width: sidebarWidth) }
        let closing = laidOutSpaceCreation.flatMap { model.spaceCreation == nil ? $0 : nil }
        let shownPanel =
            pager.selectedPageID == .spaceCreation || (runningFade != nil && runningFade?.panel == nil)
        laidOutSpaceCreation = model.spaceCreation
        // As measured on Arc: after Create Space, the panel goes in one frame and the pager settles back from where
        // it was.
        pager.setPages(pages, selecting: target, settling: Self.spaceCreationCloseSpring)
        if let closing, closing.phase == .editing, shownPanel, pager.selectedPageID == target {
            fadeSpaceCreation(SpaceCreationFade(panel: closing, themes: (.default, theme(of: target))))
            pager.select(target, animated: false, notifying: false)
        } else if target == .spaceCreation, pager.selectedPageID != target {
            guard runningFade == nil else { return updateDock() }
            // As Arc: the Library goes at once. The Space's page stays and settles back from a pull as the panel
            // fades in over it. The fade starts first, as selecting lays the pages out again from here.
            let space = WindowLayoutPage.space(model.selectedSpaceID)
            fadeSpaceCreation(SpaceCreationFade(panel: nil, themes: (theme(of: space), .default)))
            pager.select(space, animated: pager.selectedPageID != .home, notifying: false)
        } else if pager.selectedPageID != target {
            let settle = PageSwipeController<WindowLayoutPage>.settle
            pager.select(target, animated: true, spring: throughHome ? Self.homeSpring : settle)
        }
        if !pager.isTracking, !pager.isAnimating, restingSpaceID != model.selectedSpaceID {
            restingSpaceID = model.selectedSpaceID
        }
        updateDock()
    }

    private func updatePull() {
        var overshoot: CGFloat = 0
        if pullAllowed == true, let last = pager.pages.last, let origin = pager.origin(of: last.id) {
            overshoot = max(pagerPosition - origin, 0)
        }
        spaceCreationPull.progress = min(overshoot / 22.5, 1)
        springPull(to: min(overshoot / 15, 1))
        guard pager.isTracking else { return }
        let armed = spaceCreationPull.progress >= 1
        guard armed != (pullArmedAt != nil) else { return }
        pullArmedAt = armed ? CACurrentMediaTime() : nil
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
    }

    private func springPull(to target: CGFloat) {
        guard target != pullTarget, let window = view.window else { return }
        pullTarget = target
        pullTicker.start(in: window) { [weak self] in
            guard let self else { return }
            let now = CACurrentMediaTime()
            let dt = min(now - (pullTick ?? now), 1.0 / 60)
            pullTick = now
            let omega = 2 * Double.pi / 0.4
            let offset = spaceCreationPull.reveal - pullTarget
            pullVelocity += (-omega * omega * offset - 2 * 0.8 * omega * pullVelocity) * dt
            let reveal = spaceCreationPull.reveal + pullVelocity * dt
            if abs(reveal - pullTarget) < 0.001, abs(pullVelocity) < 0.01 {
                spaceCreationPull.reveal = pullTarget
                (pullVelocity, pullTick) = (0, nil)
                pullTicker.stop()
            } else {
                spaceCreationPull.reveal = reveal
            }
        }
    }

    private func trackPull() {
        guard !pager.isTracking else {
            if pullAllowed == nil {
                let last = model.state.spaces.last.map { WindowLayoutPage.space($0.id) }
                pullAllowed = model.spaceCreation == nil && pager.selectedPageID == last
            }
            return
        }
        pullAllowed = nil
        let armedAt = pullArmedAt
        pullArmedAt = nil
        guard let armedAt, CACurrentMediaTime() - armedAt > 0.1 else { return }
        // As open-arch: the panel fades in as the fingers lift, where Arc's page holds for 70 ms before it cuts in.
        model.beginSpaceCreation()
    }

    private func fadeSpaceCreation(_ fade: SpaceCreationFade) {
        guard let window = view.window else { return finishSpaceCreationFade() }
        runningFade = fade
        let start = CACurrentMediaTime()
        fadeTicker.start(in: window) { [weak self] in
            guard let self, runningFade != nil else { return }
            let time = CACurrentMediaTime() - start
            runningFade?.pages = Self.ease(time / 0.2)
            runningFade?.theme = Self.ease(time / 0.25)
            if time >= 0.25 { finishSpaceCreationFade() }
        }
    }

    private func finishSpaceCreationFade() {
        fadeTicker.stop()
        let opened = runningFade?.panel == nil
        runningFade = nil
        if opened, model.spaceCreation != nil, pendingSpaceSelection == nil {
            pager.select(.spaceCreation, animated: false, notifying: false)
        }
    }

    private static func ease(_ time: CGFloat) -> CGFloat {
        let t = min(max(time, 0), 1)
        return t * t * (3 - 2 * t)
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
            _ = model.spaceCreation
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
        if new == .hidden { iconPickerSpaceID = nil }
        // One transaction each: SwiftUI flushed a separate unanimated change while the presentation was being set,
        // drew the old value and missed the new one, so ⌘S sometimes left the sidebar hidden.
        switch (old, new) {
        case (.locked, _):
            // As open-arch: undocking makes it the panel at once, over the page, and the shape follows.
            withAnimation(Self.lockAnimation) {
                sidebarIsPanel = true
                sidebarPresentation = new
            }
        case (_, .locked):
            // As open-arch: the panel stays over the page, which is see-through when empty, until the page has
            // slid out from under it.
            withAnimation(Self.lockAnimation) {
                sidebarPresentation = new
            } completion: { [weak self] in
                if self?.sidebarPresentation == .locked { self?.sidebarIsPanel = false }
            }
        default:
            withAnimation(Self.hoverAnimation) { sidebarPresentation = new }
        }
    }
}

/// The Create a Space panel fading in over the window's Space's page, or out over the page it gave way to.
struct SpaceCreationFade {
    /// The panel fading out; nil while it fades in.
    let panel: SpaceCreationState?
    let themes: (from: WindowTheme, to: WindowTheme)
    /// How far the pages and the theme have gone, each eased from 0 to 1.
    var pages: CGFloat = 0
    var theme: CGFloat = 0
}
