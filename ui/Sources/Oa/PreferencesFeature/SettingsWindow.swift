import AppKit
import DevKit
import SwiftUI

/// Arc's Settings, with the panes Oa has so far: General and Profiles. As Arc's: toolbar tabs, one fixed size for
/// every pane, and the title is the pane's name.
@MainActor
final class SettingsWindowController: NSWindowController {
    private let tabs = NSTabViewController()
    private let engine: any BrowserApplication
    private let store: SidebarStore
    private let frontProfile: () -> UUID?
    private let state: PreferencesState

    init(
        engine: any BrowserApplication, store: SidebarStore,
        openSettings: @escaping (ChromiumSettings, UUID) -> Void, openHelp: @escaping (URL) -> Void,
        createProfile: @escaping () -> Void, frontProfile: @escaping () -> UUID?
    ) {
        self.engine = engine
        self.store = store
        self.frontProfile = frontProfile
        state = PreferencesState(engine: engine)
        super.init(window: nil)
        tabs.tabStyle = .toolbar
        add("General", symbol: "gearshape") {
            GeneralPreferencePane(adBlocker: engine.adBlocker) { [weak tabs] in tabs?.selectedTabViewItemIndex = 1 }
        }
        add("Profiles", symbol: "person") {
            ProfilePreferencePane(
                engine: engine, store: store, state: state, openSettings: openSettings, openHelp: openHelp,
                create: createProfile, delete: { [weak self] in self?.delete($0) },
                rename: { [weak self] in self?.rename($0) },
                askAboutArchive: { [weak self] in self?.askAboutArchive($0, for: $1) })
        }
        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable]
        window.toolbarStyle = .preference
        window.center()
        self.window = window
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    /// Arc's opens on its first pane and on the default profile each time; Oa's first pane is General.
    override func showWindow(_ sender: Any?) {
        if window?.isVisible != true {
            tabs.selectedTabViewItemIndex = 0
            state.currentProfileID = SidebarProfile.defaultID
            state.reload()
        }
        super.showWindow(sender)
    }

    /// As Arc: an open Settings comes back in front, key, once a create sheet ends with no question about Spaces
    /// after it, wherever the sheet was opened from. Arc makes no call for it; making one is Oa's own.
    static func bringForwardIfOpen() {
        NSApplication.shared.windows.first { $0.windowController is SettingsWindowController && $0.isVisible }?
            .makeKeyAndOrderFront(nil)
    }

    /// As Arc: the list is read again and shows the new profile.
    func profileCreated(_ id: UUID) {
        state.reload()
        state.currentProfileID = id
    }

    /// As Arc: a sheet on Settings; then the pane shows the profile of the frontmost browser window's Space.
    private func delete(_ profile: ProfileState) {
        guard let window else { return }
        DialogSheet.present(on: window) { dismiss in
            DeleteProfileDialog(profileName: profile.name) { [engine, store, state, frontProfile] in
                dismiss()
                guard store.deleteProfile(profile.id, from: engine) else { return }
                state.reload()
                state.currentProfileID = frontProfile() ?? SidebarProfile.defaultID
            } cancel: {
                dismiss()
            }
        }
    }

    /// Arc's question once profiles archive at different intervals: the profile's own value is already written.
    private func askAboutArchive(_ threshold: AutoArchiveInactiveThreshold, for profileID: UUID) {
        guard let window else { return }
        let profiles = state.profiles.map(\.id)
        DialogSheet.present(on: window) { [engine] dismiss in
            AutoArchiveProfilesDialog(
                threshold: threshold, profileName: engine.userVisibleName(of: profileID) ?? ""
            ) { all in
                if all { AutoArchiveThresholds.setForAll(threshold, profiles: profiles) }
                dismiss()
            }
        }
    }

    /// As Arc: a sheet on Settings, and the engine takes the name with no word back.
    private func rename(_ profile: ProfileState) {
        guard let window else { return }
        let others = Set(state.profiles.filter { $0.id != profile.id }.map(\.name))
        DialogSheet.present(on: window) { dismiss in
            NameChangeDialog(name: profile.name, unallowedNames: others) { [engine, state] name in
                engine.browserContext(id: profile.id).setUserVisibleName(name)
                state.reload()
                dismiss()
            } onCancel: {
                dismiss()
            }
        }
    }

    private func add(_ title: String, symbol: String, @ViewBuilder pane: () -> some View) {
        let controller = NSHostingController(rootView: pane())
        controller.preferredContentSize = NSSize(width: 684, height: 562)
        controller.title = title
        let item = NSTabViewItem(viewController: controller)
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        tabs.addTabViewItem(item)
    }
}

/// As Arc's `ProfilePreferences.State`: a profile as the pane lists it.
struct ProfileState: Identifiable, Equatable {
    let id: UUID
    let name: String
}

/// As Arc's `PreferencesFeature.State`: the profile the Profiles pane shows, and the engine's profiles in its
/// order, read when Settings opens and after a profile is made, renamed or deleted.
@MainActor
@Observable
final class PreferencesState {
    var currentProfileID = SidebarProfile.defaultID
    private(set) var profiles: [ProfileState] = []
    @ObservationIgnored private let engine: any BrowserApplication

    init(engine: any BrowserApplication) { self.engine = engine }

    var currentProfile: ProfileState? { profiles.first { $0.id == currentProfileID } ?? profiles.first }

    func reload() {
        profiles = engine.allProfiles().map { ProfileState(id: $0, name: engine.userVisibleName(of: $0) ?? "") }
    }
}
