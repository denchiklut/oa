import DevKit
import SwiftUI

/// Arc's Profiles pane at Arc's measures: the profiles on the left, the chosen one's settings on the right. The
/// list shows with one profile too, Oa's own: Arc's layout for a single profile is unknown.
struct ProfilePreferencePane: View {
    let engine: any BrowserApplication
    let store: SidebarStore
    @Bindable var state: PreferencesState
    let openWindow: (UUID) -> WindowModel?
    let openHelp: (URL) -> Void

    private static let blurb: LocalizedStringKey =
        """
        Profiles help keep your data separate across Spaces — like history, logins, cookies, and extensions. You can \
        use any Profile across one or more Spaces. \
        [Learn more.](https://resources.arc.net/hc/en-us/articles/19227964556183-Profiles-Separate-Work-Personal-Browsing)
        """

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(Self.blurb)
                    .environment(
                        \.openURL,
                        OpenURLAction {
                            openHelp($0); return .handled
                        })
                HStack(alignment: .top, spacing: 10) {
                    ProfileList(profiles: profiles, spaceCount: spaceCount, selection: $state.currentProfileID)
                        .frame(width: 205)
                    if let profile { contents(of: profile).frame(width: 341) }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 64)
            .padding(.vertical, 20)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    /// By name, capitals first, as Arc lists them.
    private var profiles: [SidebarProfile] { store.state.profiles.sorted { $0.name < $1.name } }

    private var profile: SidebarProfile? { store.state.profile(state.currentProfileID) ?? profiles.first }

    private func spaceCount(_ profileID: UUID) -> Int {
        store.state.spaces.count { $0.profileID == profileID }
    }

    private func contents(of profile: SidebarProfile) -> some View {
        let preferences = engine.browserContext(id: profile.id).preferences
        return VStack(alignment: .leading, spacing: 8) {
            SearchSettingsSection(preferences: preferences, hasSpace: spaceCount(profile.id) > 0) {
                openSearchSettings(in: profile.id)
            }
            PreferencesPaneSection {
                AutoArchiveView(
                    profileID: profile.id, hasSeveralProfiles: store.state.profiles.count > 1, openHelp: openHelp
                )
                .id(profile.id)
                PreferenceRowDivider()
                DownloadLocationView(preferences: preferences)
            }
        }
    }

    /// Arc opens it as a tab of some window; Oa's own: the first window showing a Space of the profile, or a new
    /// window on one when none does, so the page edits that profile's engines. A profile with no Space has no
    /// window to open it in.
    private func openSearchSettings(in profileID: UUID) {
        guard let url = URL(string: "chrome://settings/searchEngines"),
            let window = store.windows.first(where: { $0.space?.profileID == profileID })
                ?? store.state.spaces.first(where: { $0.profileID == profileID }).flatMap({ openWindow($0.id) })
        else { return }
        window.bringToFront()
        window.newTab(url)
    }
}

private struct ProfileList: View {
    let profiles: [SidebarProfile]
    let spaceCount: (UUID) -> Int
    @Binding var selection: UUID

    var body: some View {
        VStack(spacing: 0) {
            Text("Your Profiles")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
                .padding(.leading, 16)
            Divider()
            VStack(spacing: 0) {
                ForEach(profiles) { profile in
                    if profile.id != profiles.first?.id { Divider() }
                    row(profile)
                }
            }
            .padding(10)
            Spacer(minLength: 0)
        }
        .background(PreferencesPaneSectionBackground(fill: .clear))
    }

    private func row(_ profile: SidebarProfile) -> some View {
        Button {
            selection = profile.id
        } label: {
            HStack(spacing: 8) {
                Text(profile.name).lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 0)
                Text(usage(spaceCount(profile.id))).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize()
            }
            .padding(.horizontal, 12)
            .frame(height: 31)
            .background(profile.id == selection ? PaneColor.selection : .clear, in: RoundedRectangle(cornerRadius: 6))
            .frame(height: 40)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(profile.id == selection ? .isSelected : [])
    }

    private func usage(_ spaces: Int) -> String {
        switch spaces {
        case 0: "Not used"
        case 1: "1 Space"
        default: "\(spaces) Spaces"
        }
    }
}

struct PreferencesPaneSection<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) { content }.background(PreferencesPaneSectionBackground())
    }
}

struct PreferencesPaneSectionBackground: View {
    var fill = PaneColor.section

    var body: some View {
        RoundedRectangle(cornerRadius: 6).fill(fill)
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(nsColor: .separatorColor)))
    }
}

struct PreferenceRow<Label: View, Control: View>: View {
    var height: CGFloat = 42
    @ViewBuilder let label: Label
    @ViewBuilder let control: Control

    var body: some View {
        HStack(spacing: 8) {
            label
            Spacer(minLength: 0)
            control
        }
        .padding(.horizontal, 10)
        .frame(height: height)
    }
}

extension View {
    /// Arc's popups: 136 to 155 wide by their title, centred in a column of 180 at the row's right edge.
    func preferencePopup() -> some View { labelsHidden().frame(width: 150).frame(width: 180) }
}

struct PreferenceRowDivider: View {
    var body: some View { Divider().padding(.horizontal, 10) }
}

/// Arc's colours as measured in light; the dark ones are Oa's own, Arc's dark pane wasn't captured.
enum PaneColor {
    static let section = Color.primary.opacity(0.01)
    static let selection = Color(
        nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? .controlAccentColor.withAlphaComponent(0.3)
                : NSColor(srgbRed: 0xF1 / 255, green: 0xF6 / 255, blue: 0xFE / 255, alpha: 1)
        })
}
