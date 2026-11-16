import SwiftUI

struct CreateProfileDialogSpaceInfo: Identifiable {
    let id: UUID
    let title: String
}

/// Arc's two-step `CreateProfileDialog`: the name, then the Spaces that move to the new profile, at least one. Its
/// one-step form belongs to Arc's Create a Space panel, which Oa doesn't have yet.
struct CreateProfileDialog: View {
    private enum Step { case createProfile, selectSpaces }

    let spaces: [CreateProfileDialogSpaceInfo]
    let complete: (String, [UUID]) -> Void
    let cancel: () -> Void
    @State private var step = Step.createProfile
    @State private var name: ProfileNameInputState
    @State private var checked: Set<UUID>
    @FocusState private var focused: Bool

    init(
        existingProfileNames: Set<String>, spaces: [CreateProfileDialogSpaceInfo], checked: Set<UUID>,
        complete: @escaping (String, [UUID]) -> Void, cancel: @escaping () -> Void
    ) {
        self.spaces = spaces
        self.complete = complete
        self.cancel = cancel
        _name = State(initialValue: ProfileNameInputState(existingProfileNames: existingProfileNames))
        _checked = State(initialValue: checked)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DialogIcon(systemName: "person.crop.circle.badge.plus").padding(.leading, 38)
            switch step {
            case .createProfile: createProfile
            case .selectSpaces: selectSpaces
            }
        }
        .padding(.top, 38)
        .padding(.bottom, 27)
        .frame(width: 450)
    }

    @ViewBuilder private var createProfile: some View {
        Group {
            DialogText(
                title: "Create a new Profile",
                message: """
                    Profiles make your Spaces truly separate — with their own history, saved passwords, extensions, \
                    and other browsing data. No more flipping between work and personal accounts!

                    What do you want to call this Profile?
                    """
            )
            .padding(.top, 17)
            ProfileNameTextBox(name: $name)
                .focused($focused)
                .padding(.top, 9)
                .onAppear { focused = true }
            HStack(spacing: 2) {
                Image(systemName: "exclamationmark.arrow.triangle.2.circlepath").font(.system(size: 11, weight: .bold))
                Text("Profiles are **not synced** between computers.").font(.system(size: 11))
            }
            .foregroundStyle(DialogColor.note)
            .padding(.top, 5)
            .padding(.leading, 2)
            HStack(spacing: 8) {
                Spacer()
                DialogButtonView(title: "Cancel", kind: .cancel, action: cancel)
                DialogButtonView(title: "Next", kind: .primary, isEnabled: name.isValid) { step = .selectSpaces }
            }
            .padding(.top, 26)
        }
        .padding(.horizontal, 38)
    }

    @ViewBuilder private var selectSpaces: some View {
        DialogText(
            title: "Which Spaces should use this Profile?",
            message: """
                These Spaces will start fresh in your brand new Profile — so you’ll have to log back in to websites, \
                re-save your passwords, add extensions, etc. You can always switch back to your previous Profile \
                though if you forgot something!
                """
        )
        .padding(.top, 17)
        .padding(.horizontal, 38)
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(spaces) { space in
                    Toggle(space.title, isOn: binding(space.id)).toggleStyle(SpaceCardStyle())
                }
            }
            .padding(.horizontal, 38)
        }
        .frame(height: 155)
        .padding(.top, 14)
        HStack(spacing: 8) {
            Spacer()
            DialogButtonView(title: "Back", kind: .cancel) { step = .createProfile }
            DialogButtonView(title: "Create Profile", kind: .primary, isEnabled: !checked.isEmpty) {
                complete(name.trimmed, spaces.map(\.id).filter(checked.contains))
            }
        }
        .padding(.top, 31)
        .padding(.horizontal, 38)
    }

    private func binding(_ id: UUID) -> Binding<Bool> {
        Binding {
            checked.contains(id)
        } set: { isOn in
            if isOn { checked.insert(id) } else { checked.remove(id) }
        }
    }
}

/// Arc's `ProfileNameTextBox`: the message sits inside the box, whose border turns blue with it.
private struct ProfileNameTextBox: View {
    @Binding var name: ProfileNameInputState

    var body: some View {
        TextField("Personal", text: $name.profileNameRawValue)
            .textFieldStyle(.plain)
            .font(.system(size: 14))
            .padding(.horizontal, 12)
            .frame(height: 49)
            .overlay(alignment: .bottomLeading) {
                if let error = name.error {
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundStyle(DialogColor.error)
                        .padding(.leading, 12)
                        .padding(.bottom, 2)
                        .transition(.opacity.animation(.linear(duration: 0.1)))
                }
            }
            .background(DialogColor.field, in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(name.error == nil ? DialogColor.fieldBorder : DialogColor.primary))
    }
}

/// Arc's Space card, 64 by 155 with its tick and title under the Space's theme. Every Space shows the window's
/// theme until Oa's Spaces have their own.
private struct SpaceCardStyle: ToggleStyle {
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            VStack(spacing: 11) {
                WindowSurface(background: WindowTheme.default.background[colorScheme])
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.primary.opacity(0.3)))
                    .frame(height: 96)
                Image(systemName: configuration.isOn ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16))
                    .foregroundStyle(configuration.isOn ? Color(red: 0, green: 0.54, blue: 0) : Color.secondary)
                configuration.label
                    .font(.system(size: 12))
                    .foregroundStyle(DialogColor.title)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(width: 64, height: 155, alignment: .top)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
