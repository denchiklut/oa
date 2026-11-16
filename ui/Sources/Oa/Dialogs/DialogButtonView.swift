import SwiftUI

/// Arc's `Dialogs.DialogButtonView` with its key hint: "ESC" on cancel, the return symbol on the primary button.
struct DialogButtonView: View {
    enum Kind { case cancel, primary, destructive }

    let title: String
    let kind: Kind
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title).font(.system(size: 13, weight: .medium))
                hint
                    .font(.system(size: 11, weight: .bold))
                    .frame(minHeight: 18)
                    .padding(.horizontal, 6)
                    .background(kind == .cancel ? DialogColor.hint : text.opacity(0.2), in: shape(5))
            }
            .padding(.horizontal, 12)
            .frame(height: 39)
            .foregroundStyle(text)
            .background(
                fill.shadow(.drop(color: .black.opacity(isEnabled ? 0.18 : 0.05), radius: 0, y: 1.5)), in: shape(8)
            )
            .overlay(shape(8).strokeBorder(kind == .cancel ? DialogColor.secondaryBorder : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .keyboardShortcut(kind == .cancel ? .cancelAction : .defaultAction)
    }

    @ViewBuilder private var hint: some View {
        if kind == .cancel {
            Text("ESC").foregroundStyle(DialogColor.hintText).accessibilityLabel("Press Escape")
        } else {
            Image(systemName: "return").accessibilityLabel("Press Enter")
        }
    }

    /// Arc's disabled buttons keep their hue: a pale fill, and on the primary one text in its own tint.
    private var fill: Color {
        switch kind {
        case .cancel: DialogColor.secondary
        case .primary: DialogColor.primary.opacity(isEnabled ? 1 : 0.1)
        case .destructive: DialogColor.destructive.opacity(isEnabled ? 1 : 0.27)
        }
    }

    private var text: Color {
        switch kind {
        case .cancel: DialogColor.secondaryText
        case .primary: isEnabled ? .white : DialogColor.primary.opacity(0.45)
        case .destructive: .white
        }
    }

    private func shape(_ radius: CGFloat) -> RoundedRectangle { RoundedRectangle(cornerRadius: radius) }
}

/// The dialogs' text as Arc sets it: a 17 pt bold title over 14 pt body text.
struct DialogText: View {
    let title: String
    let message: LocalizedStringKey

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text(title).font(.system(size: 17, weight: .bold)).foregroundStyle(DialogColor.title)
            Text(message)
                .font(.system(size: 14))
                .foregroundStyle(DialogColor.body)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// The dialogs' one-line field: 14 pt text in a rounded box.
struct DialogTextField: View {
    let placeholder: String
    @Binding var text: String
    var verticalPadding: CGFloat = 10

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(.system(size: 14))
            .padding(.horizontal, 8)
            .padding(.vertical, verticalPadding)
            .background(DialogColor.field, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(DialogColor.fieldBorder))
    }
}

/// Where Arc's dialogs show their mascot, 62 pt square. The symbols are Oa's own: the art is Arc's.
struct DialogIcon: View {
    let systemName: String

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 44, weight: .light))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(DialogColor.primary)
            .frame(width: 62, height: 62)
            .accessibilityHidden(true)
    }
}
