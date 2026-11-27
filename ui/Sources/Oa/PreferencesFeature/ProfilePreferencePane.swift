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
    let delete: (ProfileState) -> Void
    let rename: (ProfileState) -> Void
    let askAboutArchive: (AutoArchiveInactiveThreshold, UUID) -> Void

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
                        EditProfilesFooterView(
                            selectedProfile: state.currentProfile?.id,
                            inUse: state.currentProfile.map { spaceCount($0.id) > 0 } ?? true,
                            add: create, delete: { state.currentProfile.map(delete) },
                            edit: { state.currentProfile.map(rename) })
                    }
                    .frame(width: 205)
                    if let profile = state.currentProfile { contents(of: profile.id).frame(width: 341) }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 64)
            .padding(.vertical, 20)
        }
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
                    profileID: profile, profiles: state.profiles.map(\.id), openHelp: openHelp,
                    ask: { askAboutArchive($0, profile) }
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
        .background(PreferencesPaneSectionBackground(fill: PaneColor.list))
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
    let selectedProfile: UUID?
    let inUse: Bool
    let add: () -> Void
    let delete: () -> Void
    let edit: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button(action: add) { Image(systemName: "plus").padding(8).contentShape(Rectangle()) }
            Divider().padding(.vertical, 4)
            Button(action: delete) { Image(systemName: "minus").padding(8).contentShape(Rectangle()) }
                .disabled(inUse || selectedProfile == SidebarProfile.defaultID)
                // As Arc's: on a disabled button the text is never drawn and reaches only accessibility.
                .accessibilityHint(
                    selectedProfile == SidebarProfile.defaultID
                        ? "The Default Profile cannot be deleted."
                        : inUse ? "Only Profiles not assigned to any Spaces can be deleted." : "")
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
    var fill = PaneColor.section
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) { content }.background(PreferencesPaneSectionBackground(fill: fill))
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

extension NSColor {
    fileprivate convenience init(hex: UInt32) {
        self.init(
            srgbRed: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255, alpha: 1)
    }
}

enum PaneColor {
    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(
            nsColor: NSColor(name: nil) { appearance in
                NSColor(hex: appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light)
            })
    }

    static let section = Color.primary.opacity(0.01)
    static let list = Color(
        nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .black.withAlphaComponent(0.05) : .white
        })
    static let arrow = adaptive(light: 0x63A1F9, dark: 0x1682EF)
    static let blue = adaptive(light: 0x69AAFA, dark: 0x1782E0)
    static let green = adaptive(light: 0x8BD38E, dark: 0x34B953)
    static let yellow = adaptive(light: 0xFADB74, dark: 0xE1BD1B)
    static let orange = adaptive(light: 0xF6B171, dark: 0xE18331)
    static let red = adaptive(light: 0xF37D74, dark: 0xE04042)
    static let glyph = Color.primary.opacity(0.65)
    static let glyphPressed = Color.primary.opacity(0.47)
    static let glyphDisabled = Color.primary.opacity(0.3)
    static let selection = Color(
        nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? .controlAccentColor.withAlphaComponent(0.1)
                : NSColor(srgbRed: 0xF1 / 255, green: 0xF6 / 255, blue: 0xFE / 255, alpha: 1)
        })
}
