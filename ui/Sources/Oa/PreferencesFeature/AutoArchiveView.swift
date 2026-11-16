import SwiftUI

struct AutoArchiveView: View {
    private static let help = URL(
        string: "https://resources.arc.net/hc/en-us/articles/19228855311127-Auto-Archive-Clean-as-you-go")!

    let profileID: UUID
    let hasSeveralProfiles: Bool
    let openHelp: (URL) -> Void
    @State private var threshold: AutoArchiveInactiveThreshold

    init(profileID: UUID, hasSeveralProfiles: Bool, openHelp: @escaping (URL) -> Void) {
        self.profileID = profileID
        self.hasSeveralProfiles = hasSeveralProfiles
        self.openHelp = openHelp
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
            AutoArchiveThresholds.set(threshold, for: profileID, amongSeveral: hasSeveralProfiles)
        }
    }
}
