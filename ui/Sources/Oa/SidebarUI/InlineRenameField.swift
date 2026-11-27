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
    var placeholder = "Title"
    var weight: NSFont.Weight = .regular
    var showsDoneButton = false
    let onCommit: (String) -> Void
    let onCancel: (NSEvent?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(layout: layout, onCommit: onCommit, onCancel: onCancel) }

    func makeNSView(context: Context) -> NSView {
        let field = InlineRenameTextField(string: text)
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 14, weight: weight)
        field.textColor = NSColor(context.environment.theme.foreground)
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
        guard showsDoneButton else { return field }

        let done = NSButton(title: "Done", target: context.coordinator, action: #selector(Coordinator.commit))
        done.isBordered = false
        done.refusesFirstResponder = true
        done.font = .systemFont(ofSize: 11, weight: .semibold)
        done.setContentHuggingPriority(.required, for: .horizontal)
        let stack = NSStackView(views: [field, done])
        stack.spacing = 4
        context.coordinator.doneButton = done
        return stack
    }

    func updateNSView(_ view: NSView, context: Context) {
        let coordinator = context.coordinator
        coordinator.field?.textColor = NSColor(context.environment.theme.foreground)
        coordinator.doneButton?.contentTintColor = NSColor(context.environment.theme.secondaryText)
        coordinator.onCommit = onCommit
        coordinator.onCancel = onCancel
    }

    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) {
        coordinator.field?.onDidMoveToWindow = nil
        coordinator.field?.delegate = nil
        coordinator.teardown()
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var onCommit: (String) -> Void
        var onCancel: (NSEvent?) -> Void
        weak var field: InlineRenameTextField?
        weak var doneButton: NSButton?
        private weak var styledEditor: NSTextView?
        private var originalSelection: [NSAttributedString.Key: Any]?
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
            if let styledEditor, let originalSelection { styledEditor.selectedTextAttributes = originalSelection }
            styledEditor = nil
            originalSelection = nil
            NSEvent.removeMonitor(clickMonitor)
            self.clickMonitor = nil
            if let menuObserver { NotificationCenter.default.removeObserver(menuObserver) }
            menuObserver = nil
            layout?.setHold(.rename, false)
        }

        private func focus() {
            guard !finished, let field, let window = field.window, field.currentEditor() == nil else { return }
            window.makeFirstResponder(field)
            guard let editor = field.currentEditor() as? NSTextView else { return }
            if doneButton != nil, let ink = field.textColor {
                // The Space name has a neutral selection in Arc. AppKit shares this editor across the window.
                styledEditor = editor
                originalSelection = editor.selectedTextAttributes
                editor.selectedTextAttributes = [.backgroundColor: ink.withAlphaComponent(0.15), .foregroundColor: ink]
            }
            editor.selectAll(nil)
        }

        private func handleClick(_ event: NSEvent) {
            guard !finished, let field, let window = field.window else { return }
            if event.window === window, let hit = window.contentView?.hitTest(event.locationInWindow) {
                if hit.isDescendant(of: field) { return }
                if let doneButton, hit.isDescendant(of: doneButton) { return }
            }
            finish(event: event)
        }

        @objc func commit() {
            if let field { finish(text: field.stringValue) }
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
