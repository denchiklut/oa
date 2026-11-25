import AppKit
import DevKit
import SwiftUI

extension View {
    /// As Arc's `WindowContentViewController` places `FindInPageView`: 10 pt in from the top right of the content and
    /// its bar, 300 pt wide and narrower in a slim pane.
    func findInPage(of model: WindowModel, on page: (any Page)?, hasTopBar: Bool) -> some View {
        overlay(alignment: .topTrailing) {
            if let page, let state = model.findInPageState(of: page) {
                FindInPageView(model: model, page: page, state: state)
                    .frame(maxWidth: 300)
                    .padding([.leading, .trailing], 10)
                    // Arc sets the top to 50 while a toolbar or a pane's `ContentPanel` bar is up, which leaves a
                    // page's toast (8 pt down, 42 pt high) clear of the bar.
                    .padding(.top, hasTopBar ? 50 : 10)
            }
        }
        .onChange(of: page.map { PageAddress(id: $0.id, url: $0.url) }) { old, new in
            if let page, old?.id == new?.id { model.dismissFindInPage(on: page, activating: false) }
        }
    }
}

private struct PageAddress: Equatable {
    let id: UUID
    let url: URL?
}

/// Arc's `FindInPageView`, as measured in its dark appearance.
private struct FindInPageView: View {
    let model: WindowModel
    let page: any Page
    let state: FindInPage.State
    @Environment(\.windowColorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        HStack(spacing: 0) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14))
                .foregroundStyle(inputText.opacity(0.6))
                .frame(width: 28, height: 28)
                .padding(.trailing, 1)
            FindInPageField(
                text: state.text, focuses: state.focusesField,
                textColor: dark
                    ? NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.8)
                    : NSColor(displayP3Red: 0.055, green: 0.059, blue: 0.063, alpha: 0.9),
                onChange: { model.updateFindQuery($0, on: page) },
                onNext: { model.findNext(forward: $0, on: page) },
                onDismiss: { model.dismissFindInPage(on: page) },
                onFocus: { model.findFieldFocused(on: page) }
            )
            .frame(height: 18)
            .accessibilityIdentifier("findInPageTextField")
            if !state.text.isEmpty, let result = state.result, result.numberOfMatches >= 0 {
                if result.numberOfMatches == 0 {
                    Text("Not Found")
                        .font(.system(size: 12).smallCaps())
                        .foregroundStyle(Color(nsColor: NSColor(displayP3Red: 0.788, green: 0.2, blue: 0.2, alpha: 1)))
                        .padding(.horizontal, 4)
                        .accessibilityIdentifier("findInPageMatchesTextBlock")
                } else {
                    Text("\(max(0, result.activeMatchOrdinal))/\(result.numberOfMatches)")
                        .font(.system(size: 12).smallCaps())
                        .monospacedDigit()
                        .foregroundStyle(inputText)
                        .padding(.trailing, 4)
                        .accessibilityIdentifier("findInPageMatchesTextBlock")
                    button("arrow.up", id: "findInPagePreviousButton") { model.findNext(forward: false, on: page) }
                    button("arrow.down", id: "findInPageNextButton") { model.findNext(forward: true, on: page) }
                }
                Rectangle()
                    .fill(Color(nsColor: NSColor(displayP3Red: 0, green: 0, blue: 0, alpha: 0.1)))
                    .frame(width: 1)
                    .padding(.vertical, 7)
                    .padding(.leading, 3.5)
                    .padding(.trailing, 1.5)
            }
            button("xmark", id: "findInPageCloseButton") { model.dismissFindInPage(on: page) }
                .padding(.trailing, 3)
        }
        .padding(.leading, 2)
        .frame(height: 32)
        .background {
            let shape = RoundedRectangle(cornerRadius: 5)
            ZStack {
                // ARCUI's popover NSShadow: PopoverShadow, blur 5, 3 pt down.
                ShadowView(
                    shape: shape,
                    color: Color(
                        nsColor: NSColor(displayP3Red: 0.082, green: 0.110, blue: 0.196, alpha: dark ? 0.8 : 0.3)),
                    radius: 5, y: 3)
                shape.fill(
                    Color(
                        nsColor: dark
                            ? NSColor(displayP3Red: 0.082, green: 0.110, blue: 0.188, alpha: 1)
                            : NSColor(displayP3Red: 0.980, green: 0.984, blue: 1, alpha: 1)))
                shape.strokeBorder(
                    Color(nsColor: NSColor(displayP3Red: 0, green: 0, blue: 0, alpha: 0.1)), lineWidth: 1)
            }
        }
        .environment(\.colorScheme, scheme)
    }

    /// Arc's `PopoverInputText`.
    private var inputText: Color {
        Color(
            nsColor: scheme == .dark
                ? NSColor(displayP3Red: 0.98, green: 0.984, blue: 1, alpha: 0.9)
                : NSColor(displayP3Red: 0.055, green: 0.059, blue: 0.063, alpha: 0.8))
    }

    private func button(_ symbol: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(inputText)
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }
}

/// The bar's field, an AppKit one as Arc's: its keys as Arc's `FindInPageView` takes them.
private struct FindInPageField: NSViewRepresentable {
    let text: String
    let focuses: Bool
    let textColor: NSColor
    let onChange: (String) -> Void
    let onNext: (_ forward: Bool) -> Void
    let onDismiss: () -> Void
    let onFocus: () -> Void

    func makeNSView(context: Context) -> FindInPageTextField {
        let field = FindInPageTextField()
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        field.font = .systemFont(ofSize: 13)
        field.placeholderString = "Find in page..."
        field.delegate = context.coordinator
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateNSView(_ field: FindInPageTextField, context: Context) {
        context.coordinator.field = self
        field.textColor = textColor
        if field.stringValue != text { field.stringValue = text }
        guard focuses else { return }
        DispatchQueue.main.async {
            guard let window = field.window else { return }
            window.makeFirstResponder(field)
            onFocus()
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(field: self) }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var field: FindInPageField

        init(field: FindInPageField) { self.field = field }

        func controlTextDidChange(_ notification: Notification) {
            guard let control = notification.object as? NSTextField else { return }
            field.onChange(control.stringValue)
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.cancelOperation(_:)): field.onDismiss()
            case #selector(NSResponder.insertNewline(_:)):
                field.onNext(NSApp.currentEvent?.modifierFlags.contains(.shift) != true)
            case #selector(NSResponder.moveUp(_:)): field.onNext(false)
            case #selector(NSResponder.moveDown(_:)): field.onNext(true)
            default: return false
            }
            return true
        }
    }
}

/// On the responder chain while it is edited, with no validation of the Find items, so all of them are on, as Arc's
/// bar leaves them.
final class FindInPageTextField: NSTextField {
    @objc(arc_performFindPanelAction:) func arcPerformFindPanelAction(_ sender: Any?) {
        if (sender as? NSMenuItem)?.tag == NSTextFinder.Action.showFindInterface.rawValue {
            currentEditor()?.selectAll(nil)
        } else {
            nextResponder?.tryToPerform(#selector(arcPerformFindPanelAction(_:)), with: sender)
        }
    }
}
