import AppKit
import DevKit
import Foundation
import Observation

/// Chromium's extensions for a profile, kept current by OaCore's events as ADK's life cycle manager is by ArcCore's.
@MainActor
@Observable
final class ChromiumExtensions: Extensions {
    private(set) var items: [BrowserExtension] = []
    @ObservationIgnored private let core: CoreExtensions?
    @ObservationIgnored private let delegate = ExtensionsDelegate()

    @ObservationIgnored private let formatterPreference: String
    @ObservationIgnored private var isReady = false
    @ObservationIgnored private var installWhenReady = false

    init(core: CoreExtensions?, profileID: UUID) {
        formatterPreference = "hasInstalledJSONFormatter.\(profileID.uuidString)"
        self.core = core
        delegate.extensions = self
        core?.delegate = delegate
    }

    func installJSONFormatterIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: formatterPreference) else { return }
        if isReady {
            core?.installJSONFormatter()
        } else {
            installWhenReady = true
        }
    }

    private func rememberFormatter(_ id: String) {
        if id == BrowserExtension.jsonFormatterID {
            UserDefaults.standard.set(true, forKey: formatterPreference)
        }
    }

    func setEnabled(_ enabled: Bool, id: BrowserExtension.ID) { core?.setExtension(identifier: id, enabled: enabled) }
    func uninstall(_ id: BrowserExtension.ID) { core?.uninstallExtension(identifier: id) }

    fileprivate func initialized(_ extensions: [BrowserExtension]) {
        items = extensions.sorted(by: Self.byName)
        if items.contains(where: { $0.id == BrowserExtension.jsonFormatterID }) {
            rememberFormatter(BrowserExtension.jsonFormatterID)
        }
        isReady = true
        if installWhenReady {
            installWhenReady = false
            installJSONFormatterIfNeeded()
        }
    }

    fileprivate func changed(_ changed: BrowserExtension) {
        rememberFormatter(changed.id)
        var items = items.filter { $0.id != changed.id }
        items.append(changed)
        self.items = items.sorted(by: Self.byName)
    }

    fileprivate func removed(_ id: BrowserExtension.ID) {
        rememberFormatter(id)
        items.removeAll { $0.id == id }
    }

    private static func byName(_ a: BrowserExtension, _ b: BrowserExtension) -> Bool {
        a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
    }
}

@MainActor
private final class ExtensionsDelegate: NSObject, CoreExtensionsDelegate {
    weak var extensions: ChromiumExtensions?

    func extensionsDidInitialize(_ extensions: [NSObject]) {
        self.extensions?.initialized(
            extensions.map { BrowserExtension(core: unsafeBitCast($0, to: CoreExtension.self)) })
    }

    func extensionWasInstalled(_ extension: CoreExtension) { extensions?.changed(BrowserExtension(core: `extension`)) }
    func extensionWasUninstalled(identifier: String) { extensions?.removed(identifier) }
    func extensionWasEnabled(_ extension: CoreExtension) { extensions?.changed(BrowserExtension(core: `extension`)) }
    func extensionWasDisabled(_ extension: CoreExtension) { extensions?.changed(BrowserExtension(core: `extension`)) }
}

extension BrowserExtension {
    @MainActor fileprivate init(core: CoreExtension) {
        self.init(
            id: core.identifier, name: core.name, description: core.extensionDescription, version: core.version,
            isEnabled: core.isEnabled, hasAction: core.hasAction, isFromWebStore: core.isFromWebstore)
    }
}
