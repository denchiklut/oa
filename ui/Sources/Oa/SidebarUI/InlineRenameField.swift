import AppKit
import SwiftUI

/// On the responder chain while a sidebar row is renamed inline, so window activation leaves it focused.
final class SidebarRenameTextField: NSTextField {
    var onDidMoveToWindow: (() -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { onDidMoveToWindow?() }
    }
}

/// An AppKit field for inline sidebar renames, taking first responder directly from Chromium and committing on Return
/// or keypad Enter without racing focus-loss notifications.
struct InlineRenameField: NSViewRepresentable {
    let text: String
    var placeholder = "Title"
    let textColor: NSColor
    let onCommit: (String) -> Void
    let onCancel: (NSEvent?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onCommit: onCommit, onCancel: onCancel) }

    func makeNSView(context: Context) -> SidebarRenameTextField {
        let field = SidebarRenameTextField(string: text)
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 14)
        field.textColor = textColor
        field.placeholderString = placeholder
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

    func updateNSView(_ field: SidebarRenameTextField, context: Context) {
        field.textColor = textColor
        context.coordinator.onCommit = onCommit
        context.coordinator.onCancel = onCancel
    }

    static func dismantleNSView(_ field: SidebarRenameTextField, coordinator: Coordinator) {
        field.onDidMoveToWindow = nil
        field.delegate = nil
        coordinator.teardown()
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var onCommit: (String) -> Void
        var onCancel: (NSEvent?) -> Void
        weak var field: SidebarRenameTextField?
        private var finished = false
        private var clickMonitor: Any?
        private var menuObserver: NSObjectProtocol?

        init(onCommit: @escaping (String) -> Void, onCancel: @escaping (NSEvent?) -> Void) {
            self.onCommit = onCommit
            self.onCancel = onCancel
        }

        func attach() {
            guard !finished else { return }
            if clickMonitor == nil {
                clickMonitor = NSEvent.addLocalMonitorForEvents(
                    matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
                ) { [weak self] event in
                    MainActor.assumeIsolated { self?.handleClick(event) }
                    return event
                }
            }
            if menuObserver == nil {
                menuObserver = NotificationCenter.default.addObserver(
                    forName: NSMenu.didEndTrackingNotification, object: nil, queue: .main
                ) { [weak self] _ in
                    MainActor.assumeIsolated { DispatchQueue.main.async { self?.focus() } }
                }
            }
            DispatchQueue.main.async { [weak self] in self?.focus() }
        }

        func teardown() {
            if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
            clickMonitor = nil
            if let menuObserver { NotificationCenter.default.removeObserver(menuObserver) }
            menuObserver = nil
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
            if !inside { finish(committing: false, text: nil, event: event) }
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.insertNewline(_:)), #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)):
                finish(committing: true, text: control.stringValue, event: nil)
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                finish(committing: false, text: nil, event: nil)
                return true
            default:
                return false
            }
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            finish(committing: false, text: nil, event: nil)
        }

        private func finish(committing: Bool, text: String?, event: NSEvent?) {
            guard !finished else { return }
            finished = true
            teardown()
            if committing, let text {
                onCommit(text)
            } else {
                onCancel(event)
            }
        }
    }
}
