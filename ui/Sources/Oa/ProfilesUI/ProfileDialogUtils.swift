import AppKit
import SwiftUI

@MainActor
enum ProfileDialogUtils {
    /// Arc's create sheet on the window that asked, with `spaceIDs` ticked. The profile is made, with its Favorites,
    /// before the confirm about its Spaces, so cancelling there leaves it unused.
    static func createProfile(checking spaceIDs: [UUID] = [], in model: WindowModel) {
        guard let window = model.window else { return }
        let spaces = model.state.spaces.map { CreateProfileDialogSpaceInfo(id: $0.id, title: $0.name) }
        DialogSheet.present(on: window) { dismiss in
            CreateProfileDialog(
                existingProfileNames: Set(model.profiles.map(\.name)), spaces: spaces, checked: Set(spaceIDs)
            ) { [weak model] name, spaceIDs in
                dismiss()
                Task {
                    guard let model, let profileID = await model.createProfile(named: name) else { return }
                    confirmSwitch(spaceIDs, to: profileID, in: model)
                }
            } cancel: {
                dismiss()
            }
        }
    }

    /// Arc's confirm before a Space changes profile, on the window that started it. Every way to change it asks.
    static func confirmSwitch(_ spaceIDs: [UUID], to profileID: UUID, in model: WindowModel) {
        let spaces = spaceIDs.compactMap { model.state.space($0)?.name }
        guard let window = model.window, !spaces.isEmpty else { return }
        DialogSheet.present(on: window) { dismiss in
            SwitchProfileDialog(profile: model.profileName(profileID), spaces: spaces) { [weak model] proceed in
                dismiss()
                if proceed { model?.setProfile(profileID, forSpaces: spaceIDs) }
            }
        }
    }
}

private struct SwitchProfileDialog: View {
    let profile: String
    let spaces: [String]
    let done: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DialogIcon(systemName: "person.crop.circle.badge.questionmark")
            (Text("Switch to your ") + Text(profile).fontWeight(.heavy) + Text(" Profile?"))
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(DialogColor.title)
                .padding(.top, 17)
            Text(message)
                .font(.system(size: 14))
                .foregroundStyle(DialogColor.body)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 16)
                .padding(.trailing, 5)
            HStack(spacing: 8) {
                Spacer()
                DialogButtonView(title: "Cancel", kind: .cancel) { done(false) }
                DialogButtonView(title: "Switch it up", kind: .primary) { done(true) }
            }
            .padding(.top, 43)
            .padding(.trailing, -10)
        }
        .padding(.horizontal, 38)
        .padding(.top, 38)
        .padding(.bottom, 27)
        .frame(width: 455)
    }

    /// The wording for several Spaces is Oa's own: Arc's was seen with one.
    private var message: AttributedString {
        var names = AttributedString(spaces.formatted(.list(type: .and)))
        names.font = .system(size: 14, weight: .bold)
        return "Each Profile has different browser data, so your " + names
            + AttributedString(
                """
                 \(spaces.count == 1 ? "Space" : "Spaces") might look a little different!

                For example, you might get logged out of some websites, see different Favorites up top, or need to \
                re-install an extension.

                This action cannot be undone.
                """)
    }
}
