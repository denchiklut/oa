import DevKit
import SwiftUI

/// Arc's Profiles pane at Arc's measures: the profiles on the left, the chosen one's settings on the right, with one
/// profile too.
struct ProfilePreferencePane: View {
    let engine: any BrowserApplication
    let store: SidebarStore
    @Bindable var state: PreferencesState
    let openSettings: (ChromiumSettings, UUID) -> Void
    let openHelp: (URL) -> Void
    let create: () -> Void
    let rename: (ProfileState) -> Void

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
                    ProfileList(profiles: state.profiles, spaceCount: spaceCount, selection: $state.currentProfileID) {
                        EditProfilesFooterView(add: create, edit: { state.currentProfile.map(rename) })
                    }
                    .frame(width: 205)
                    if let profile = state.currentProfile { contents(of: profile.id).frame(width: 341) }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 64)
            .padding(.vertical, 20)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private func spaceCount(_ profileID: UUID) -> Int {
        store.state.spaces.count { $0.profileID == profileID }
    }

    private func contents(of profile: UUID) -> some View {
        let preferences = engine.browserContext(id: profile).preferences
        return VStack(alignment: .leading, spacing: 8) {
            SearchSettingsSection(preferences: preferences) { openSettings(.searchEngines, profile) }
            PreferencesPaneSection {
                AutoArchiveView(
                    profileID: profile, hasSeveralProfiles: state.profiles.count > 1, openHelp: openHelp
                )
                .id(profile)
                PreferenceRowDivider()
                DownloadLocationView(preferences: preferences)
            }
            DataActionButtonsView { openSettings($0, profile) }
        }
    }
}

/// Arc's "Your Data and Settings": each row opens one of Chromium's pages for the profile. Clear Browsing Data opens
/// the privacy page, as Arc's does.
private struct DataActionButtonsView: View {
    let open: (ChromiumSettings) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Your Data and Settings").font(.system(size: 11)).foregroundStyle(.secondary).padding(.leading, 10)
            VStack(spacing: 0) {
                button("lock.fill", PaneColor.blue, "Privacy and Security", .privacy)
                button("key.fill", PaneColor.green, "Passwords", .passwords)
                button("creditcard.and.123", PaneColor.yellow, "Credit Cards", .creditCards)
                button("bell.fill", PaneColor.orange, "Notifications", .notifications)
                button("trash.fill", PaneColor.red, "Clear Browsing Data", .privacy)
            }
            .padding(.vertical, 5)
            .background(PreferencesPaneSectionBackground())
        }
        .padding(.top, 4)
    }

    private func button(_ icon: String, _ color: Color, _ label: String, _ page: ChromiumSettings) -> some View {
        Button {
            open(page)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(color, in: RoundedRectangle(cornerRadius: 6))
                Text(label)
                Spacer(minLength: 0)
                Image(systemName: "arrow.right")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(PaneColor.arrow)
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct ProfileList<Footer: View>: View {
    let profiles: [ProfileState]
    let spaceCount: (UUID) -> Int
    @Binding var selection: UUID
    @ViewBuilder let footer: Footer

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
            Divider()
            footer
        }
        .background(PreferencesPaneSectionBackground(fill: .clear))
    }

    private func row(_ profile: ProfileState) -> some View {
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

/// Arc's strip under the profile list. Its glyphs have no hover look and lighten while pressed.
struct EditProfilesFooterView: View {
    let add: () -> Void
    let edit: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button(action: add) { Image(systemName: "plus").padding(8).contentShape(Rectangle()) }
            Divider().padding(.vertical, 4)
            Button(action: edit) {
                Image(systemName: "rectangle.and.pencil.and.ellipsis").offset(y: -2).padding(8).contentShape(
                    Rectangle())
            }
            Spacer(minLength: 0)
        }
        .buttonStyle(GlyphStyle())
        .frame(height: 32)
    }

    private struct GlyphStyle: ButtonStyle {
        @Environment(\.isEnabled) private var isEnabled

        func makeBody(configuration: Configuration) -> some View {
            configuration.label.foregroundStyle(
                !isEnabled
                    ? PaneColor.glyphDisabled : configuration.isPressed ? PaneColor.glyphPressed : PaneColor.glyph)
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
        HStack(spacing: 0) {
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

extension Color {
    fileprivate init(hex: UInt32) {
        self.init(
            .sRGB, red: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255)
    }
}

/// Arc's colours as measured in light; the dark ones are Oa's own, Arc's dark pane wasn't captured.
enum PaneColor {
    static let section = Color.primary.opacity(0.01)
    static let arrow = Color(hex: 0x63A1F9)
    static let blue = Color(hex: 0x69AAFA)
    static let green = Color(hex: 0x8BD38E)
    static let yellow = Color(hex: 0xFADB74)
    static let orange = Color(hex: 0xF6B171)
    static let red = Color(hex: 0xF37D74)
    static let glyph = Color.primary.opacity(0.65)
    static let glyphPressed = Color.primary.opacity(0.47)
    static let glyphDisabled = Color.primary.opacity(0.3)
    static let selection = Color(
        nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? .controlAccentColor.withAlphaComponent(0.3)
                : NSColor(srgbRed: 0xF1 / 255, green: 0xF6 / 255, blue: 0xFE / 255, alpha: 1)
        })
}
