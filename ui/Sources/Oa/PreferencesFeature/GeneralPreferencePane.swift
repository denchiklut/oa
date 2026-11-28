import DevKit
import SwiftUI

struct GeneralPreferencePane: View {
    let adBlocker: AdBlocker
    let showProfiles: () -> Void
    @AppStorage(QuitWarning.key) private var warnsBeforeQuitting = QuitWarning.isOnByDefault
    @State private var showsUpdateInfo = false
    @State private var showsPreviewSettings = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                PreferencesPaneSection {
                    PreferenceRow(height: 36) {
                        HStack(spacing: 4) {
                            Text("Automatically update my Oa")
                            Button {
                                showsUpdateInfo.toggle()
                            } label: {
                                Image(systemName: "info.circle")
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("About automatic updates")
                            .popover(isPresented: $showsUpdateInfo) {
                                Text("Automatic updates are unavailable in this build of Oa.")
                                    .padding()
                            }
                        }
                    } control: {
                        Toggle("Automatically update my Oa", isOn: .constant(false))
                            .labelsHidden()
                            .controlSize(.mini)
                            .disabled(true)
                    }
                    PreferenceRowDivider()
                    toggle("Warn before quitting", isOn: $warnsBeforeQuitting)
                }
                PreferencesPaneSection {
                    PreferenceRow {
                        Text("Previews")
                    } control: {
                        Button("Previews Settings…") { showsPreviewSettings = true }
                    }
                    .sheet(isPresented: $showsPreviewSettings) {
                        PreviewSettingsDialog(settings: .shared) { showsPreviewSettings = false }
                    }
                    PreferenceRowDivider()
                    PreferenceRow(height: 48) {
                        Text("Manage your default search engine, Auto-Archive, and downloads in Profile Settings.")
                            .frame(maxWidth: 334, alignment: .leading)
                    } control: {
                        Button("Profile Settings…", action: showProfiles)
                    }
                }
                PreferencesPaneSection {
                    PreferenceRow {
                        Text("Ad Blocker").bold()
                    } control: {
                        Button(adBlocker.isEnabled ? "Turn Off" : "Turn On") {
                            adBlocker.setEnabled(!adBlocker.isEnabled)
                        }
                    }
                    PreferenceRowDivider()
                    VStack(spacing: 0) {
                        listToggle("Block Ads", list: "EasyList")
                        PreferenceRowDivider()
                        listToggle("Block Trackers", list: "EasyPrivacy")
                    }
                    .disabled(!adBlocker.isEnabled)
                    .opacity(adBlocker.isEnabled ? 1 : 0.4)
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
    }

    private func toggle(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(title).frame(maxWidth: .infinity, alignment: .leading)
        }
        .controlSize(.mini)
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
