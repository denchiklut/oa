import AppKit
import SwiftUI

/// On the responder chain while a sidebar row is renamed inline, so window activation leaves it focused.
final class InlineRenameTextField: NSTextField {
    var onDidMoveToWindow: (() -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { onDidMoveToWindow?() }
    }
}

/// AppKit's field, where SwiftUI's took the keyboard from Chromium only after a delay and raced its own focus loss on
/// Return. Oa's own: it holds a floating sidebar out while it is edited.
struct InlineRenameField: NSViewRepresentable {
    let layout: WindowLayoutController
    let text: String
    let onCommit: (String) -> Void
    let onCancel: (NSEvent?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(layout: layout, onCommit: onCommit, onCancel: onCancel) }

    func makeNSView(context: Context) -> InlineRenameTextField {
        let field = InlineRenameTextField(string: text)
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 14)
        field.textColor = NSColor(context.environment.theme.foreground)
        field.placeholderString = "Title"
        field.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        field.cell?.sendsActionOnEndEditing = false
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.delegate = context.coordinator
        context.coordinator.field = field
        field.onDidMoveToWindow = { [weak coordinator = context.coordinator] in
            coordinator?.attach()
        }
        return field
    }

    func updateNSView(_ field: InlineRenameTextField, context: Context) {
        field.textColor = NSColor(context.environment.theme.foreground)
        context.coordinator.onCommit = onCommit
        context.coordinator.onCancel = onCancel
    }

    static func dismantleNSView(_ field: InlineRenameTextField, coordinator: Coordinator) {
        field.onDidMoveToWindow = nil
        field.delegate = nil
        coordinator.teardown()
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var onCommit: (String) -> Void
        var onCancel: (NSEvent?) -> Void
        weak var field: InlineRenameTextField?
        private weak var layout: WindowLayoutController?
        private var finished = false
        private var clickMonitor: Any?
        private var menuObserver: NSObjectProtocol?

        init(
            layout: WindowLayoutController, onCommit: @escaping (String) -> Void,
            onCancel: @escaping (NSEvent?) -> Void
        ) {
            self.layout = layout
            self.onCommit = onCommit
            self.onCancel = onCancel
        }

        func attach() {
            guard !finished else { return }
            if clickMonitor == nil {
                layout?.setHold(.rename, true)
                clickMonitor = NSEvent.addLocalMonitorForEvents(
                    matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
                ) { [weak self] event in
                    MainActor.assumeIsolated { self?.handleClick(event) }
                    return event
                }
                menuObserver = NotificationCenter.default.addObserver(
                    forName: NSMenu.didEndTrackingNotification, object: nil, queue: .main
                ) { [weak self] _ in
                    MainActor.assumeIsolated { DispatchQueue.main.async { self?.focus() } }
                }
            }
            DispatchQueue.main.async { [weak self] in self?.focus() }
        }

        func teardown() {
            guard let clickMonitor else { return }
            NSEvent.removeMonitor(clickMonitor)
            self.clickMonitor = nil
            if let menuObserver { NotificationCenter.default.removeObserver(menuObserver) }
            menuObserver = nil
            layout?.setHold(.rename, false)
        }

        private func focus() {
            guard !finished, let field, let window = field.window, field.currentEditor() == nil else { return }
            window.makeFirstResponder(field)
            field.currentEditor()?.selectAll(nil)
        }

        private func handleClick(_ event: NSEvent) {
            guard !finished, let field, let window = field.window else { return }
            let inside =
                event.window === window
                && window.contentView?.hitTest(event.locationInWindow)?.isDescendant(of: field) == true
            if !inside { finish(event: event) }
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.insertNewline(_:)), #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)):
                finish(text: control.stringValue)
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                finish()
                return true
            default:
                return false
            }
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            finish()
        }

        /// Commits `text`, or cancels without one; `event` is the press that ended the rename.
        private func finish(text: String? = nil, event: NSEvent? = nil) {
            guard !finished else { return }
            finished = true
            teardown()
            if let text { onCommit(text) } else { onCancel(event) }
        }
    }
}
