import DevKit
import SwiftUI

struct GeneralPreferencePane: View {
    let adBlocker: AdBlocker
    let showProfiles: () -> Void
    @AppStorage(QuitWarning.key) private var warnsBeforeQuitting = QuitWarning.isOnByDefault

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                PreferencesPaneSection {
                    toggle("Warn before quitting", isOn: $warnsBeforeQuitting)
                }
                PreferencesPaneSection {
                    PreferenceRow(height: 48) {
                        Text("Manage your default search engine, Auto-Archive, and downloads in Profile Settings.")
                            .frame(maxWidth: 334, alignment: .leading)
                    } control: {
                        Button("Profile Settings…", action: showProfiles)
                    }
                }
                PreferencesPaneSection {
                    PreferenceRow {
                        Text("Oa’s Ad Blocker").fontWeight(.semibold)
                    } control: {
                        Button(adBlocker.isEnabled ? "Turn Off" : "Turn On") {
                            adBlocker.setEnabled(!adBlocker.isEnabled)
                        }
                    }
                    PreferenceRowDivider()
                    listToggle("Block Ads", list: "EasyList")
                    PreferenceRowDivider()
                    listToggle("Block Trackers", list: "EasyPrivacy")
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Applies to all profiles.")
                    if adBlocker.isDownloading {
                        Text("Downloading filters…")
                    } else if adBlocker.isApplying {
                        ProgressView().controlSize(.small)
                    }
                    if let error = adBlocker.error { Text(error) }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
            }
            .toggleStyle(.switch)
            .padding(.horizontal, 64)
            .padding(.vertical, 20)
        }
    }

    private func listToggle(_ title: String, list: String) -> some View {
        toggle(
            title,
            isOn: Binding {
                adBlocker.selectedLists.contains(list)
            } set: {
                adBlocker.setList(list, enabled: $0)
            }
        )
        .disabled(!adBlocker.isEnabled)
    }

    private func toggle(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(title).frame(maxWidth: .infinity, alignment: .leading)
        }
        .controlSize(.small)
        .font(.body)
        .padding(.horizontal, 10)
        .frame(height: 36)
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
