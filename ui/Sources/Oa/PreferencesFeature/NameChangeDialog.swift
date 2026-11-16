import SwiftUI

/// Arc's `NameChangeDialog` for a profile. As Arc's: the name isn't cut, a name over 256 characters or another
/// profile's keeps Save off with a message, and a reserved name gets the duplicate's message.
struct NameChangeDialog: View {
    private static let maxCharCount = 256

    let unallowedNames: Set<String>
    let onSubmit: (String) -> Void
    let onCancel: () -> Void
    @State private var mutableName: String
    @FocusState private var focused: Bool

    init(
        name: String, unallowedNames: Set<String>, onSubmit: @escaping (String) -> Void, onCancel: @escaping () -> Void
    ) {
        self.unallowedNames = unallowedNames
        self.onSubmit = onSubmit
        self.onCancel = onCancel
        _mutableName = State(initialValue: name)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DialogText(
                title: "Rename your Profile",
                message: "This won’t affect the names of any of the Spaces associated with this Profile.")
            DialogTextField(placeholder: "", text: $mutableName)
                .focused($focused)
                .padding(.top, 20)
            Text(error ?? " ")
                .font(.system(size: 12))
                .foregroundStyle(DialogColor.error)
                .padding(.top, 4)
            HStack(spacing: 8) {
                Spacer()
                DialogButtonView(title: "Cancel", kind: .cancel, action: onCancel)
                DialogButtonView(title: "Save", kind: .primary, isEnabled: canProceed) { onSubmit(trimmed) }
            }
            .padding(.top, 9)
        }
        .padding(.horizontal, 38)
        .padding(.top, 37)
        .padding(.bottom, 27)
        .frame(width: 496)
        .onAppear {
            focused = true
            DispatchQueue.main.async {
                NSApplication.shared.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
            }
        }
    }

    private var trimmed: String { mutableName.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var tooManyCharacters: Bool { trimmed.count > Self.maxCharCount }

    /// Arc skips both checks when there is no other profile.
    private var enteredNameInvalid: Bool {
        !unallowedNames.isEmpty && (ProfileName.reserved.contains(trimmed) || unallowedNames.contains(trimmed))
    }

    private var canProceed: Bool { !trimmed.isEmpty && !tooManyCharacters && !enteredNameInvalid }

    private var error: String? {
        if enteredNameInvalid { return "A Profile with that name already exists." }
        return tooManyCharacters ? "Almost there, name must be \(Self.maxCharCount) characters or less." : nil
    }
}
