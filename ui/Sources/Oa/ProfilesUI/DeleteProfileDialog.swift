import SwiftUI

/// Arc's `DeleteProfileDialog`: Delete stays off until the profile's name is typed, in any case and untrimmed.
struct DeleteProfileDialog: View {
    let profileName: String
    let delete: () -> Void
    let cancel: () -> Void
    @State private var typed = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DialogIcon(systemName: "person.crop.circle.badge.minus")
            DialogText(
                title: "Delete this Profile",
                message: """
                    Deleting **\(profileName)** will permanently remove any cookies, history, preferences, and logins \
                    that belong to this Profile.
                    To continue, please type the name of this Profile:
                    """
            )
            .textSelection(.enabled)
            .padding(.top, 17)
            DialogTextField(placeholder: profileName, text: $typed, size: 13, verticalPadding: 8)
                .focused($focused)
                .padding(.top, 8)
                .onAppear { focused = true }
            HStack(spacing: 8) {
                Spacer()
                DialogButtonView(title: "Cancel", kind: .cancel, action: cancel)
                DialogButtonView(title: "Delete", kind: .destructive, isEnabled: canDeleteProfile, action: delete)
            }
            .padding(.top, 26)
        }
        .padding(.horizontal, 38)
        .padding(.top, 38)
        .padding(.bottom, 27)
        .frame(width: 450)
    }

    private var canDeleteProfile: Bool { typed.caseInsensitiveCompare(profileName) == .orderedSame }
}
