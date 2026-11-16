import SwiftUI

struct AutoArchiveView: View {
    private static let help = URL(
        string: "https://resources.arc.net/hc/en-us/articles/19228855311127-Auto-Archive-Clean-as-you-go")!

    let profileID: UUID
    let profiles: [UUID]
    let openHelp: (URL) -> Void
    let ask: (AutoArchiveInactiveThreshold) -> Void
    @State private var threshold: AutoArchiveInactiveThreshold

    init(
        profileID: UUID, profiles: [UUID], openHelp: @escaping (URL) -> Void,
        ask: @escaping (AutoArchiveInactiveThreshold) -> Void
    ) {
        self.profileID = profileID
        self.profiles = profiles
        self.openHelp = openHelp
        self.ask = ask
        _threshold = State(initialValue: AutoArchiveThresholds.threshold(for: profileID))
    }

    var body: some View {
        PreferenceRow(height: 45) {
            HStack(spacing: 5) {
                Text("Archive tabs after")
                Button {
                    openHelp(Self.help)
                } label: {
                    Image(systemName: "info.circle")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Learn more about auto-archiving")
            }
        } control: {
            Picker("Archive tabs after", selection: $threshold) {
                ForEach(AutoArchiveInactiveThreshold.allCases) { Text($0.label).tag($0) }
            }
            .preferencePopup()
        }
        .onChange(of: threshold) { _, threshold in
            if AutoArchiveThresholds.set(threshold, for: profileID, among: profiles) { ask(threshold) }
        }
    }
}

/// Arc's prompt after an interval change, with Arc's wording under Oa's name. Escape keeps it to the one profile.
struct AutoArchiveProfilesDialog: View {
    let threshold: AutoArchiveInactiveThreshold
    let profileName: String
    let done: (_ allProfiles: Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DialogText(
                title: "Oa will now archive your tabs after \(threshold.title)",
                message: """
                    Would you like to apply this change to all of your Profiles, or only your \(profileName) Profile?
                    """)
            HStack(spacing: 8) {
                Spacer()
                DialogButtonView(title: "Only this Profile", kind: .cancel) { done(false) }
                DialogButtonView(title: "All Profiles", kind: .primary) { done(true) }
            }
            .padding(.top, 36)
            .padding(.trailing, -10)
        }
        .padding(.horizontal, 38)
        .padding(.top, 55)
        .padding(.bottom, 27)
        .frame(width: 450)
    }
}
