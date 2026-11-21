import AppKit
import SwiftUI

/// Arc's `styleEditPopover`: a transient popover round the editor, sized by it. It closes on a click outside, and on
/// Escape unless a page has the keys, as measured on Arc. ⌘Z and ⇧⌘Z inside it reach the window's undo manager.
@MainActor
final class SpaceStyleEditorPopover: NSObject, NSPopoverDelegate {
    private let popover = NSPopover()
    private let pageView: () -> NSView?
    private let onClose: () -> Void
    private weak var parentWindow: NSWindow?
    private var monitor: Any?
    private var isClosed = false

    init(
        hidesArrow: Bool, pageView: @escaping () -> NSView? = { nil }, onClose: @escaping () -> Void,
        @ViewBuilder content: () -> some View
    ) {
        self.pageView = pageView
        self.onClose = onClose
        super.init()
        let controller = NSHostingController(rootView: content())
        controller.sizingOptions = .preferredContentSize
        popover.contentViewController = controller
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        // As Arc: its arrow is hidden through AppKit's private `shouldHideAnchor`.
        if hidesArrow, popover.responds(to: NSSelectorFromString("setShouldHideAnchor:")) {
            popover.setValue(true, forKey: "shouldHideAnchor")
        }
    }

    func show(relativeTo rect: NSRect, of view: NSView, preferredEdge: NSRectEdge = .maxX) {
        parentWindow = view.window
        popover.show(relativeTo: rect, of: view, preferredEdge: preferredEdge)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) == true } ? nil : event
        }
    }

    /// Without `notifying`, for a close its owner asked for.
    func close(notifying: Bool = true) {
        if !notifying { isClosed = true }
        removeMonitor()
        popover.close()
        didClose()
    }

    nonisolated func popoverDidClose(_ notification: Notification) {
        MainActor.assumeIsolated { didClose() }
    }

    private func didClose() {
        guard !isClosed else { return }
        isClosed = true
        removeMonitor()
        // After the view update a close can come in, from a SwiftUI anchor going away.
        Task { @MainActor in self.onClose() }
    }

    private func removeMonitor() {
        monitor.map(NSEvent.removeMonitor)
        monitor = nil
    }

    private func handle(_ event: NSEvent) -> Bool {
        let inPopover = event.window != nil && event.window === popover.contentViewController?.view.window
        if event.keyCode == 53 {
            let pageHasKeys = pageView().map { page in
                (parentWindow?.firstResponder as? NSView)?.isDescendant(of: page) == true
            }
            guard inPopover || (event.window === parentWindow && pageHasKeys != true) else { return false }
            close()
            return true
        }
        guard inPopover, event.charactersIgnoringModifiers?.lowercased() == "z",
            event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting(.shift) == .command,
            let undoManager = parentWindow?.undoManager
        else { return false }
        if event.modifierFlags.contains(.shift) { undoManager.redo() } else { undoManager.undo() }
        return true
    }
}

/// Hangs the editor from the view it backs: pointing at it, or, as from Arc's sidebar, off its right edge at the
/// pointer's height with no arrow.
struct SpaceStyleEditorAnchor<Content: View>: NSViewRepresentable {
    let isPresented: Bool
    var atPointer = false
    let onClose: () -> Void
    @ViewBuilder let content: () -> Content

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        let coordinator = context.coordinator
        if isPresented, coordinator.popover == nil, view.window != nil {
            let popover = SpaceStyleEditorPopover(
                hidesArrow: atPointer,
                onClose: { [weak coordinator] in
                    coordinator?.popover = nil
                    onClose()
                }, content: content)
            coordinator.popover = popover
            popover.show(relativeTo: atPointer ? pointerStrip(in: view) : view.bounds, of: view)
        } else if !isPresented, let popover = coordinator.popover {
            coordinator.popover = nil
            popover.close(notifying: false)
        }
    }

    private func pointerStrip(in view: NSView) -> NSRect {
        let pointer = view.convert(view.window?.mouseLocationOutsideOfEventStream ?? .zero, from: nil)
        return NSRect(x: 0, y: min(max(pointer.y, 0), view.bounds.height - 1), width: view.bounds.width, height: 1)
    }

    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) {
        coordinator.popover?.close()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor
    final class Coordinator {
        var popover: SpaceStyleEditorPopover?
    }
}
