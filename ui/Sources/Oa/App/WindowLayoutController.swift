import AppKit
import Observation
import SwiftUI

/// Arc's window layout controller, the window's content: it derives how the sidebar is shown from its mode, the
/// pointer and what the sidebar is in the middle of, and lays the sidebar and the page out for it.
@MainActor
@Observable
final class WindowLayoutController: NSViewController {
    /// What keeps a floating sidebar out with the pointer elsewhere, as Arc's does for its menus, drags and popovers.
    enum Hold { case menu, drag, popover }

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

    override func viewDidAppear() {
        super.viewDidAppear()
        guard monitor == nil, let window = view.window else { return }
        window.acceptsMouseMovedEvents = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] event in
            // A drag from the sidebar has ended by the time the pointer moves again.
            if event.type == .mouseMoved { self?.holds.remove(.drag) }
            self?.trackPointer()
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

    func setSidebarMode(_ mode: SidebarMode) {
        model.setSidebarMode(mode)
        updatePresentation()
    }

    func toggleSidebar() {
        setSidebarMode(model.sidebarMode == .anchored ? .noChrome : .anchored)
    }

    func setHold(_ hold: Hold, _ held: Bool) {
        if held { holds.insert(hold) } else { holds.remove(hold) }
        updatePresentation()
    }

    private func observeModel() {
        withObservationTracking {
            _ = (model.sidebarMode, model.library, model.selectedTabID)
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeModel() }
        }
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
                sidebarWidth: sidebarPresentation == .locked
                    ? SidebarView.width : sidebarPresentation == .floating ? SidebarView.width + 80 : 0,
                showsToolbar: PageToolbar.isShown, roomAbove: roomAbove > 10 ? roomAbove : 0))
        updatePresentation()
    }

    /// Arc's order: a docked sidebar is locked; a hidden one stays hidden under the Library, and floats while the
    /// pointer is in a hover region, while nothing is selected, and while the sidebar holds it.
    private var derivedPresentation: SidebarPresentation {
        if model.sidebarMode == .anchored { return .locked }
        if model.library != nil { return .hidden }
        let floating = sidebarPresentation == .floating
        let allowTop = !PageToolbar.isShown || model.selectedTabID != nil
        if hover.reveals(active: floating, allowTop: allowTop) || model.selectedTabID == nil { return .floating }
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
            sidebarIsPanel = false
            withAnimation(Self.lockAnimation) { sidebarPresentation = new }
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
