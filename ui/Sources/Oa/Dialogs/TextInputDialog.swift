import SwiftUI

/// Arc's `TextInputDialogContext`: an optional icon, a title, an optional line under it, one field with its text all
/// selected, and Cancel and the confirming button.
struct TextInputDialog: View {
    let title: String
    let message: String?
    let icon: NSImage?
    let placeholder: String
    let confirmTitle: String
    let width: CGFloat
    let onSubmit: (String) -> Void
    let onCancel: () -> Void
    @State private var text: String
    @FocusState private var focused: Bool

    init(
        title: String, message: String? = nil, icon: NSImage? = nil, text: String, placeholder: String,
        confirmTitle: String, width: CGFloat = 450, onSubmit: @escaping (String) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.title = title
        self.message = message
        self.icon = icon
        self.placeholder = placeholder
        self.confirmTitle = confirmTitle
        self.width = width
        self.onSubmit = onSubmit
        self.onCancel = onCancel
        _text = State(initialValue: text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 62, height: 62)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .padding(.bottom, 20)
            }
            if let message {
                DialogText(title: title, message: LocalizedStringKey(message))
            } else {
                Text(title).font(.system(size: 17, weight: .bold)).foregroundStyle(DialogColor.title)
            }
            DialogTextField(placeholder: placeholder, text: $text)
                .focused($focused)
                .onSubmit { onSubmit(text) }
                .padding(.top, 20)
            HStack(spacing: 8) {
                Spacer()
                DialogButtonView(title: "Cancel", kind: .cancel, action: onCancel)
                DialogButtonView(title: confirmTitle, kind: .primary) { onSubmit(text) }
            }
            .padding(.top, 24)
        }
        .padding(.horizontal, 38)
        .padding(.top, 37)
        .padding(.bottom, 27)
        .frame(width: width)
        .onAppear {
            focused = true
            DispatchQueue.main.async {
                NSApplication.shared.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
            }
        }
    }
}
