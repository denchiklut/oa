import AppKit
import DevKit
import ObjectiveC

/// Metadata Arc's nib attaches to a `MainMenu` item to expose it as a Type Travel command.
struct TypeTravelMenuInfo: Equatable {
    let id: String
    let titleOverride: String?
    let icon: String
    let triggers: [String]
    let bump: Double
    let allowWhenHidden: Bool
}

@MainActor private var typeTravelInfoKey: UInt8 = 0

extension NSMenuItem {
    @MainActor
    var arcTypeTravelInfo: TypeTravelMenuInfo? {
        get { objc_getAssociatedObject(self, &typeTravelInfoKey) as? TypeTravelMenuInfo }
        set { objc_setAssociatedObject(self, &typeTravelInfoKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }

    @MainActor
    @discardableResult
    func typeTravel(
        _ id: String, icon: String, title: String? = nil, triggers: [String] = [], bump: Double = 0,
        allowWhenHidden: Bool = false
    ) -> NSMenuItem {
        arcTypeTravelInfo = TypeTravelMenuInfo(
            id: id, titleOverride: title, icon: icon, triggers: triggers, bump: bump, allowWhenHidden: allowWhenHidden)
        return self
    }
}

/// Settings panes reachable by command, in `SettingsWindowController`'s tab order.
enum SettingsPane: Int, Equatable {
    case general = 0
    case profiles = 1
    case links = 2
    case shortcuts = 3
    case advanced = 4
}

/// One command row in the command bar, matching Arc's `ASE2.TypeTravelCandidate` (tagged menu items plus built-in
/// dynamic kinds).
struct CommandAction: Identifiable, Equatable {
    enum Kind: Equatable {
        case menuItem(id: String)
        case openPreferencePane(SettingsPane)
        case openChromiumSettings(ChromiumSettings)
        case openAirTrafficControl
        case focusSpace(UUID)
        case moveToSpace(UUID)
        case browserExtension(String)
        case addExtension
        case manageExtensions
        case renameCurrentTab
        case duplicateCurrentTab
        case resetCurrentTab
        case moveToFavorites
        case removeFromFavorites
        case muteAllTabs
        case unmuteAllTabs
        case convertToHorizontalSplitView
        case convertToVerticalSplitView
        case undoAction
        case redoAction
    }

    struct Capsule: Equatable {
        let title: String
        let icon: String?
    }

    let id: String
    let kind: Kind
    let title: String
    let capsule: Capsule?
    let icon: String
    let extensionIcon: NSImage?
    let bump: Double
    let shortcut: ARCKeyboardShortcut?
    /// Lowercased title and trigger phrases, as Arc's `TypeTravelSearchableProperty.lowercaseQuery`.
    let searchableProperties: [String]
    /// Space-separated words across `searchableProperties`, as Arc's cached token set.
    let tokens: Set<String>

    init(
        id: String, kind: Kind, title: String, capsule: Capsule? = nil, icon: String, extensionIcon: NSImage? = nil,
        triggers: [String] = [], bump: Double = 0, shortcut: ARCKeyboardShortcut? = nil
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.capsule = capsule
        self.icon = icon
        self.extensionIcon = extensionIcon
        self.bump = bump
        self.shortcut = shortcut
        let fullTitle = capsule.map { "\(title) \($0.title)" } ?? title
        var seen: Set<String> = []
        let raw = ([fullTitle] + triggers).map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        let properties = raw.filter { !$0.isEmpty && seen.insert($0).inserted }
        self.searchableProperties = properties
        self.tokens = Set(properties.flatMap { $0.components(separatedBy: " ") }.filter { !$0.isEmpty })
    }

    /// As Arc's `TypeTravelClientImpl` (1.174.3): either every query word is in the candidate's token set (unordered),
    /// or any searchable property contains the whole lowercased query as a substring.
    func matches(lowercaseQuery: String, queryTokens: [String]) -> Bool {
        if !queryTokens.isEmpty, queryTokens.allSatisfy(tokens.contains) { return true }
        return searchableProperties.contains { $0.contains(lowercaseQuery) }
    }

    static func == (lhs: CommandAction, rhs: CommandAction) -> Bool {
        lhs.id == rhs.id && lhs.kind == rhs.kind && lhs.title == rhs.title && lhs.capsule == rhs.capsule
            && lhs.icon == rhs.icon && lhs.shortcut == rhs.shortcut
    }
}

/// Builds a per-window snapshot of enabled commands (tagged `MainMenu` items plus built-in kinds), matching Arc's
/// `TypeTravelMainMenuSnapshot` and `TypeTravelClientImpl`, which omit disabled items.
@MainActor
enum CommandBarActions {
    static func snapshot(for model: WindowModel) -> [CommandAction] {
        var actions: [CommandAction] = []
        if let mainMenu = NSApp.mainMenu {
            collectMenuItems(in: mainMenu, into: &actions)
        }
        actions += builtInActions(for: model)
        return actions
    }

    static func menuItem(withTypeTravelID id: String) -> NSMenuItem? {
        guard let mainMenu = NSApp.mainMenu else { return nil }
        return findMenuItem(withTypeTravelID: id, in: mainMenu)
    }

    private static func findMenuItem(withTypeTravelID id: String, in menu: NSMenu) -> NSMenuItem? {
        for item in menu.items {
            if item.arcTypeTravelInfo?.id == id { return item }
            if let submenu = item.submenu, let found = findMenuItem(withTypeTravelID: id, in: submenu) {
                return found
            }
        }
        return nil
    }

    private static func collectMenuItems(in menu: NSMenu, into actions: inout [CommandAction]) {
        for item in menu.items {
            if let submenu = item.submenu {
                if submenu.title != "Extensions" { collectMenuItems(in: submenu, into: &actions) }
                continue
            }
            guard let info = item.arcTypeTravelInfo, let action = item.action else { continue }
            guard isEnabled(item, action: action, allowWhenHidden: info.allowWhenHidden) else { continue }
            let title = info.titleOverride ?? item.title
            actions.append(
                CommandAction(
                    id: info.id, kind: .menuItem(id: info.id), title: title, icon: info.icon, triggers: info.triggers,
                    bump: info.bump, shortcut: item.keyboardShortcut))
        }
    }

    private static func isEnabled(_ item: NSMenuItem, action: Selector, allowWhenHidden: Bool) -> Bool {
        guard let target = NSApp.target(forAction: action, to: item.target, from: item) else { return false }
        let valid: Bool
        if let validator = target as? NSMenuItemValidation {
            valid = validator.validateMenuItem(item)
        } else if let validator = target as? NSUserInterfaceValidations {
            valid = validator.validateUserInterfaceItem(item)
        } else {
            valid = item.isEnabled
        }
        if !valid { return false }
        return allowWhenHidden || !item.isHidden
    }

    private static func builtInActions(for model: WindowModel) -> [CommandAction] {
        var actions: [CommandAction] = []
        let settingsShortcut = model.keyBindings.state.shortcut(for: "viewPreferences")

        // Settings panes, as Arc's `openPreferencePane` and direct Settings shortcuts.
        actions += [
            CommandAction(
                id: "openSettings", kind: .openPreferencePane(.general), title: "Open Settings", icon: "gearshape",
                triggers: ["Settings", "Preferences", "Open Preferences"], shortcut: settingsShortcut),
            CommandAction(
                id: "openGeneralPreferences", kind: .openPreferencePane(.general), title: "Open General Preferences",
                icon: "gearshape", triggers: ["General Settings", "Preferences", "Settings"]),
            CommandAction(
                id: "openProfilePreferences", kind: .openPreferencePane(.profiles), title: "Open Profile Preferences",
                icon: "person", triggers: ["Profiles", "Profile Settings", "Preferences"]),
            CommandAction(
                id: "editKeyboardShortcuts", kind: .openPreferencePane(.shortcuts), title: "Edit Keyboard Shortcuts",
                icon: "keyboard", triggers: ["Shortcuts", "Key Bindings", "Hotkeys", "Preferences"]),
            CommandAction(
                id: "openLinkPreferences", kind: .openPreferencePane(.links), title: "Open Link Preferences",
                icon: "macwindow.on.rectangle", triggers: ["Links", "Little Oa", "Peek", "Preferences"]),
            CommandAction(
                id: "openAdvancedPreferences", kind: .openPreferencePane(.advanced),
                title: "Open Advanced Preferences", icon: "slider.horizontal.3",
                triggers: ["Advanced Settings", "Preferences"]),
            CommandAction(
                id: "openSearchSettings", kind: .openChromiumSettings(.searchEngines), title: "Open Search Settings",
                icon: "magnifyingglass", triggers: ["Search Engine", "Site Search", "Default Search"]),
            CommandAction(
                id: "openPasswordManager", kind: .openChromiumSettings(.passwords), title: "Open Password Manager",
                icon: "key", triggers: ["Passwords", "Logins", "Saved Passwords"]),
            CommandAction(
                id: "openAirTrafficControl", kind: .openAirTrafficControl, title: "Open Air Traffic Control",
                icon: "airplane", triggers: ["Link Routing", "URL Routing", "Routes"]),
        ]

        // Spaces (focus / move), in global windows only.
        if model.sidebarContext == .global, model.spaceCreation == nil {
            let hasTab = model.selectedTabID != nil
            for space in model.state.spaces where space.id != model.selectedSpaceID {
                let capsule = CommandAction.Capsule(title: space.name, icon: space.icon)
                actions.append(
                    CommandAction(
                        id: "focusSpace:\(space.id.uuidString)", kind: .focusSpace(space.id), title: "Switch to",
                        capsule: capsule, icon: "rectangle.portrait",
                        triggers: ["Focus \(space.name)", "Go to \(space.name)", "Space \(space.name)", space.name]))
                if hasTab {
                    actions.append(
                        CommandAction(
                            id: "moveToSpace:\(space.id.uuidString)", kind: .moveToSpace(space.id),
                            title: "Move Tab to", capsule: capsule, icon: "arrow.right.square",
                            triggers: ["Move to \(space.name)", "Send to \(space.name)", space.name]))
                }
            }
        }

        // Extensions, omitted in incognito windows as Arc's Extensions menu is.
        if model.sidebarContext != .incognito {
            actions.append(
                CommandAction(
                    id: "addExtension", kind: .addExtension, title: "Add Extension…", icon: "plus.circle",
                    triggers: [
                        "Install Extensions", "Extension Store", "Plugins", "Chrome Extensions", "Chrome Store",
                    ]))
            actions.append(
                CommandAction(
                    id: "manageExtensions", kind: .manageExtensions, title: "Manage Extensions…", icon: "puzzlepiece",
                    triggers: ["Manage Extensions", "Extensions", "Plugins", "Chrome Extensions"]))
            for ext in model.extensionActions where ext.isEnabled {
                actions.append(
                    CommandAction(
                        id: "extension:\(ext.id)", kind: .browserExtension(ext.id), title: ext.name,
                        icon: "puzzlepiece.extension", extensionIcon: ext.icon, triggers: ["Extension", ext.name]))
            }
        }

        // Current-tab actions.
        if let tabID = model.selectedTabID, !model.isLittle {
            actions.append(
                CommandAction(
                    id: "renameCurrentTab", kind: .renameCurrentTab, title: "Rename Current Tab",
                    icon: "character.cursor.ibeam", triggers: ["Rename Tab", "Edit Tab Name"]))
            actions.append(
                CommandAction(
                    id: "duplicateCurrentTab", kind: .duplicateCurrentTab, title: "Duplicate Current Tab",
                    icon: "plus.square.on.square", triggers: ["Duplicate Tab", "Clone Tab"]))
            if let tab = model.state.tree.tab(tabID), model.state.keepsAddress(tabID), let saved = tab.url,
                let live = model.liveURL(of: tabID), live != saved
            {
                actions.append(
                    CommandAction(
                        id: "resetCurrentTab", kind: .resetCurrentTab, title: "Reset Current Tab",
                        icon: "arrow.counterclockwise", triggers: ["Reset Tab", "Reset Tab to Original URL"]))
            }
            if model.sidebarContext == .global {
                if model.state.isFavorite(tabID) {
                    actions.append(
                        CommandAction(
                            id: "removeFromTopApps", kind: .removeFromFavorites, title: "Remove from Favorites",
                            icon: "star.slash", triggers: ["Unfavorite", "Unfavorite Tab", "Favorites"]))
                } else {
                    actions.append(
                        CommandAction(
                            id: "moveToTopApps", kind: .moveToFavorites, title: "Add to Favorites", icon: "star",
                            triggers: ["Favorite", "Favorite Tab", "Move to Favorites", "Top Apps"]))
                }
            }
        }

        // Audio across all windows.
        let livePages = model.allLivePages
        if livePages.contains(where: { $0.isAudible && !$0.isMuted }) {
            actions.append(
                CommandAction(
                    id: "muteAllTabs", kind: .muteAllTabs, title: "Mute All Tabs", icon: "speaker.slash",
                    triggers: ["Mute", "Silence Tabs", "Audio"]))
        }
        if livePages.contains(where: { $0.isMuted }) {
            actions.append(
                CommandAction(
                    id: "unmuteAllTabs", kind: .unmuteAllTabs, title: "Unmute All Tabs", icon: "speaker.wave.2",
                    triggers: ["Unmute", "Audio"]))
        }

        // Split View orientation conversion.
        if model.presentedTabIDs.count > 1, let tabID = model.selectedTabID,
            let splitID = model.state.splitViewID(containing: tabID),
            let split = model.state.splitView(splitID)
        {
            if split.layoutOrientation == .vertical {
                actions.append(
                    CommandAction(
                        id: "convertToHorizontalSplitView", kind: .convertToHorizontalSplitView,
                        title: "Convert to Horizontal Split View", icon: "rectangle.split.2x1",
                        triggers: ["Horizontal Split", "Rotate Split View", "Flip Split"]))
            } else {
                actions.append(
                    CommandAction(
                        id: "convertToVerticalSplitView", kind: .convertToVerticalSplitView,
                        title: "Convert to Vertical Split View", icon: "rectangle.split.1x2",
                        triggers: ["Vertical Split", "Rotate Split View", "Flip Split"]))
            }
        }

        // Live Undo / Redo from the window's undo manager.
        if let undo = model.window?.undoManager {
            if undo.canUndo {
                let name = undo.undoActionName
                let title = name.isEmpty ? "Undo" : "Undo \(name)"
                actions.append(
                    CommandAction(
                        id: "undoAction", kind: .undoAction, title: title, icon: "arrow.uturn.backward",
                        triggers: ["Undo"], shortcut: ARCKeyboardShortcut(key: "z", modifiers: .command)))
            }
            if undo.canRedo {
                let name = undo.redoActionName
                let title = name.isEmpty ? "Redo" : "Redo \(name)"
                actions.append(
                    CommandAction(
                        id: "redoAction", kind: .redoAction, title: title, icon: "arrow.uturn.forward",
                        triggers: ["Redo"], shortcut: ARCKeyboardShortcut(key: "z", modifiers: [.command, .shift])))
            }
        }

        return actions
    }
}
