import SwiftUI

/// Arc's `ChangeProfileDialog`. Change Profile is always on, as Arc's: the Space's own profile is an answer too,
/// and nil is the picker's "New Profile".
struct ChangeProfileDialog: View {
    let focusedSpaceName: String
    let profiles: [ProfileState]
    let onComplete: (UUID?) -> Void
    let onDismiss: () -> Void
    @State private var selectedProfile: UUID?

    init(
        focusedSpaceName: String, profiles: [ProfileState], selectedProfile: UUID,
        onComplete: @escaping (UUID?) -> Void, onDismiss: @escaping () -> Void
    ) {
        self.focusedSpaceName = focusedSpaceName
        self.profiles = profiles
        self.onComplete = onComplete
        self.onDismiss = onDismiss
        _selectedProfile = State(initialValue: selectedProfile)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DialogIcon(systemName: "person.crop.circle.badge.questionmark")
            (Text("Change ") + Text("\(focusedSpaceName)’s").bold() + Text(" Profile"))
                .font(.system(size: 18))
                .foregroundStyle(DialogColor.title)
                .padding(.top, 17)
            Text(
                """
                Each Profile has different browser data, so you might get logged out of some websites, see \
                different Favorites up top, or need to re-install extensions.
                """
            )
            .font(.system(size: 14))
            .foregroundStyle(DialogColor.body)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 13)
            HStack(spacing: 6) {
                (Text("\(focusedSpaceName)’s").bold() + Text(" Profile"))
                    .font(.system(size: 13))
                    .foregroundStyle(DialogColor.title)
                    .lineLimit(1)
                picker
            }
            .padding(.top, 11)
            HStack(spacing: 8) {
                Spacer()
                DialogButtonView(title: "Cancel", kind: .cancel, action: onDismiss)
                DialogButtonView(title: "Change Profile", kind: .primary) { onComplete(selectedProfile) }
            }
            .padding(.top, 26)
        }
        .padding(.horizontal, 38)
        .padding(.top, 38)
        .padding(.bottom, 27)
        .frame(width: 450)
    }

    private var picker: some View {
        Menu {
            ForEach(profiles) { profile in
                Button(profile.name) { selectedProfile = profile.id }
            }
            Divider()
            Button("New Profile") { selectedProfile = nil }
        } label: {
            Label(displayName, systemImage: "chevron.down.circle.fill").labelStyle(ProfilePickerMenuLabelStyle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityIdentifier("spacePicker")
    }

    private var displayName: String {
        selectedProfile.map { id in profiles.first { $0.id == id }?.name ?? "" } ?? "New Profile"
    }
}

private struct ProfilePickerMenuLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) {
            configuration.icon
            configuration.title.lineLimit(1)
        }
        .font(.system(size: 14))
        .foregroundStyle(DialogColor.pickerText)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(DialogColor.picker, in: RoundedRectangle(cornerRadius: 5))
    }
}
