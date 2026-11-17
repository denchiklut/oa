import DevKit
import SwiftUI

/// Arc's dialog as measured: a 260 pt panel centred on the window, 448 for long text, over a scrim that covers the
/// sidebar too; Chrome's title line, message and buttons. Enter accepts, Esc cancels and does nothing to an alert.
struct DialogView: View {
    let model: WindowModel
    let dialog: PageDialog
    @State private var text = ""
    @State private var suppress = false
    @FocusState private var fieldFocused: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        // As measured in Arc: a flat grey scrim by the window's appearance, and the panel in the system's sheet glass
        // with no shadow.
        let scrim = colorScheme == .dark ? NSColor(white: 0.094, alpha: 0.61) : NSColor(white: 0.667, alpha: 0.6)
        let shape = RoundedRectangle(cornerRadius: 26, style: .continuous)
        ZStack {
            Backdrop(onClick: {}, color: scrim)
            KeyTrap(onReturn: accept, onEscape: cancellable ? cancel : {})
            if #available(macOS 26, *) {
                panel.frame(width: wide ? 448 : 260).glassEffect(.regular, in: shape)
            } else {
                panel.frame(width: wide ? 448 : 260).background(.regularMaterial, in: shape)
            }
        }
        .onAppear {
            guard case .prompt(let defaultText) = dialog.kind else { return }
            text = defaultText
            DispatchQueue.main.async {
                fieldFocused = true
                DispatchQueue.main.async { (NSApp.keyWindow?.firstResponder as? NSTextView)?.selectAll(nil) }
            }
        }
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !dialog.title.isEmpty {
                Text(dialog.title).font(.system(size: 13, weight: .semibold))
            }
            if !dialog.message.isEmpty {
                Text(dialog.message)
                    .font(.system(size: 13))
                    .lineLimit(12)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if case .prompt = dialog.kind {
                TextField("", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .focused($fieldFocused)
                    .onSubmit(accept)
            }
            if dialog.offersSuppression {
                Toggle("Don't show this again", isOn: $suppress)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 12))
            }
            HStack(spacing: 8) {
                if cancellable {
                    Button(action: cancel) { Text("Cancel").frame(maxWidth: .infinity) }
                        .keyboardShortcut(.cancelAction)
                }
                Button(action: accept) { Text("OK").frame(maxWidth: .infinity) }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
            .controlSize(.large)
            .padding(.top, 4)
        }
        .padding(20)
    }

    private var cancellable: Bool { dialog.kind != .alert }

    private var wide: Bool { dialog.message.count > 90 || dialog.message.contains("\n") }

    private func accept() {
        model.forget(dialog)
        dialog.accept(text: text, suppress: suppress)
    }

    private func cancel() {
        model.forget(dialog)
        dialog.cancel(suppress: suppress)
    }
}

/// Takes the keyboard from the engine's view, which would otherwise swallow Enter and Esc while its renderer waits
/// on the dialog.
struct KeyTrap: NSViewRepresentable {
    let onReturn: () -> Void
    let onEscape: () -> Void

    func makeNSView(context: Context) -> TrapView { TrapView() }

    func updateNSView(_ view: TrapView, context: Context) {
        view.onReturn = onReturn
        view.onEscape = onEscape
    }

    final class TrapView: NSView {
        var onReturn: () -> Void = {}
        var onEscape: () -> Void = {}

        override var acceptsFirstResponder: Bool { true }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.makeFirstResponder(self)
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func keyDown(with event: NSEvent) {
            switch event.keyCode {
            case 36, 76: onReturn()
            case 53: onEscape()
            default: super.keyDown(with: event)
            }
        }
    }
}
