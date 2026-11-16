import DevKit
import SwiftUI

struct GeneralPreferencePane: View {
    let adBlocker: AdBlocker
    let showProfiles: () -> Void
    @AppStorage(QuitWarning.key) private var warnsBeforeQuitting = QuitWarning.isOnByDefault

    var body: some View {
        Form {
            Toggle("Warn before quitting", isOn: $warnsBeforeQuitting)
            LabeledContent {
                Button("Profile Settings…", action: showProfiles)
            } label: {
                Text("Manage your default search engine, Auto-Archive, and downloads in Profile Settings.")
            }
            Section("Oa’s Ad Blocker") {
                Toggle("Block ads and trackers", isOn: Binding(get: { adBlocker.isEnabled }, set: adBlocker.setEnabled))
                Toggle(
                    "Block Ads",
                    isOn: Binding(
                        get: { adBlocker.selectedLists.contains("EasyList") },
                        set: { adBlocker.setList("EasyList", enabled: $0) }
                    )
                ).disabled(!adBlocker.isEnabled)
                Toggle(
                    "Block Trackers",
                    isOn: Binding(
                        get: { adBlocker.selectedLists.contains("EasyPrivacy") },
                        set: { adBlocker.setList("EasyPrivacy", enabled: $0) }
                    )
                ).disabled(!adBlocker.isEnabled)
                Text("Applies to all profiles.").font(.caption).foregroundStyle(.secondary)
                if adBlocker.isDownloading {
                    Text("Downloading filters…").font(.caption).foregroundStyle(.secondary)
                } else if adBlocker.isApplying {
                    ProgressView().controlSize(.small)
                }
                if let error = adBlocker.error { Text(error).font(.caption).foregroundStyle(.secondary) }
            }
        }
        .formStyle(.grouped)
    }
}

/// Arc's key. On by default is LIKELY Arc's: it stores only changed settings, and an install was seen holding this
/// one off beside the auto-update setting, which ships on.
enum QuitWarning {
    static let key = "shouldWarnBeforeQuitting"
    static let isOnByDefault = true

    static var isOn: Bool {
        get { UserDefaults.standard.object(forKey: key) as? Bool ?? isOnByDefault }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}
