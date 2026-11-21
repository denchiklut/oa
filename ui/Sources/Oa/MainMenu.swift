import AppKit

@MainActor
final class MainMenu {
    static let lastTabTag = 9
    private let extensionsMenu = ExtensionsMenu()
    private var keyBindingMenuManager: KeyBindingMenuManager?

    func install(in application: NSApplication, keyBindings: KeyBindingsClient) {
        let menu = NSMenu()
        let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Oa"

        let app = submenu(appName, in: menu)
        app.addItem(item("About \(appName)", #selector(NSApplication.orderFrontStandardAboutPanel(_:))))
        app.addItem(.separator())
        app.addItem(item("Settings…", #selector(ApplicationDelegate.showSettings(_:)), key: ",", id: "viewPreferences"))
        app.addItem(.separator())
        app.addItem(
            item(
                "Hide \(appName)", #selector(NSApplication.hide(_:)), key: "h", id: "hideArc",
                priority: .overrideWebView))
        app.addItem(
            item(
                "Hide Others", #selector(NSApplication.hideOtherApplications(_:)), key: "h",
                modifiers: [.command, .option], id: "hideOthers"))
        app.addItem(item("Show All", #selector(NSApplication.unhideAllApplications(_:))))
        app.addItem(.separator())
        app.addItem(
            item(
                "Quit \(appName)", #selector(ApplicationDelegate.quit(_:)), key: "q", id: "quitArc",
                priority: .overrideWebView))

        let file = submenu("File", in: menu)
        file.addItem(
            item(
                "New Window", #selector(ApplicationDelegate.newWindow(_:)), key: "n", id: "newWindow",
                priority: .overrideWebView))
        file.addItem(
            item(
                "New Tab", #selector(BrowserWindowController.newTab(_:)), key: "t", id: "newTab",
                priority: .overrideWebView))
        file.addItem(item("New Profile", #selector(BrowserWindowController.newProfile(_:))))
        file.addItem(
            item(
                "Open Location…", #selector(BrowserWindowController.openLocation(_:)), key: "l", id: "addressBar",
                priority: .overrideWebView))
        file.addItem(.separator())
        file.addItem(
            item(
                "Pin/Unpin Tab", #selector(BrowserWindowController.togglePin(_:)), key: "d", id: "pinTab",
                priority: .promptAfterConsumedByWebView))
        file.addItem(.separator())
        file.addItem(
            item(
                "Archive Tab", #selector(BrowserWindowController.closeTab(_:)), key: "w", id: "archiveTab",
                priority: .overrideWebView))
        file.addItem(
            item(
                "Close Window", #selector(NSWindow.performClose(_:)), key: "w", modifiers: [.command, .shift],
                id: "closeWindow", priority: .overrideWebView))
        file.addItem(
            item(
                "Restore Last Closed Tab", #selector(BrowserWindowController.restoreLastClosed(_:)), key: "t",
                modifiers: [.command, .shift], id: "reopenLastClosedTab", priority: .overrideWebView))

        let edit = submenu("Edit", in: menu)
        edit.addItem(item("Undo", Selector(("undo:")), key: "z"))
        edit.addItem(item("Redo", Selector(("redo:")), key: "z", modifiers: [.command, .shift]))
        edit.addItem(.separator())
        edit.addItem(item("Cut", #selector(NSText.cut(_:)), key: "x"))
        edit.addItem(item("Copy", #selector(NSText.copy(_:)), key: "c"))
        edit.addItem(
            item(
                "Copy URL", #selector(BrowserWindowController.copyCurrentURL(_:)), key: "c",
                modifiers: [.command, .shift], id: "copyCurrentURL", priority: .overrideWebView))
        edit.addItem(item("Paste", #selector(NSText.paste(_:)), key: "v"))
        edit.addItem(item("Select All", #selector(NSText.selectAll(_:)), key: "a"))

        let view = submenu("View", in: menu)
        let appearance = submenu("Appearance", in: view)
        let header = NSMenuItem(title: "Websites will use:", action: nil, keyEquivalent: "")
        header.isEnabled = false
        appearance.addItem(header)
        appearance.addItem(item("Automatic", #selector(ApplicationDelegate.setAutomaticAppearance(_:))))
        appearance.addItem(item("Light", #selector(ApplicationDelegate.setLightAppearance(_:))))
        appearance.addItem(item("Dark", #selector(ApplicationDelegate.setDarkAppearance(_:))))
        view.addItem(.separator())
        view.addItem(item("Reload Page", #selector(BrowserWindowController.reload(_:)), key: "r", id: "reloadPage"))
        view.addItem(
            item("Stop Loading", #selector(BrowserWindowController.stopLoading(_:)), key: ".", id: "stopLoading"))
        view.addItem(.separator())
        view.addItem(
            item(
                "Show/Hide Sidebar", #selector(BrowserWindowController.toggleSidebarMode(_:)), key: "s",
                id: "showSidebar", priority: .promptAfterConsumedByWebView))
        view.addItem(item("Collapse Pinned Tabs", #selector(BrowserWindowController.togglePinnedSection(_:))))
        view.addItem(
            item(
                "Show/Hide Toolbar", #selector(ApplicationDelegate.toggleToolbar(_:)), key: "d",
                modifiers: [.command, .shift], id: "toggleToolbar", priority: .promptAfterConsumedByWebView))

        let archive = submenu("Archive", in: menu)
        archive.addItem(
            item(
                "Back", #selector(BrowserWindowController.goBack(_:)), key: "[", id: "goBack",
                priority: .overrideWebView))
        archive.addItem(
            item(
                "Forward", #selector(BrowserWindowController.goForward(_:)), key: "]", id: "goForward",
                priority: .overrideWebView))
        archive.addItem(.separator())
        archive.addItem(
            item("View History", #selector(BrowserWindowController.viewHistory(_:)), key: "y", id: "viewHistory"))
        archive.addItem(
            item("View Archive…", #selector(BrowserWindowController.toggleArchive(_:)), id: "viewArchive"))
        archive.addItem(
            item("Clear Archive", #selector(BrowserWindowController.clearArchive(_:)), id: "clearArchive"))

        let tabs = submenu("Tabs", in: menu)
        let next = #selector(BrowserWindowController.selectNextTab(_:))
        let previous = #selector(BrowserWindowController.selectPreviousTab(_:))
        tabs.addItem(item("Next Tab", next, key: "}", id: "nextTab"))
        tabs.addItem(
            item(
                "Next Tab (Alternate)", next, key: "\u{F701}", modifiers: [.command, .option],
                id: "selectNextTab", priority: .overrideWebView))
        tabs.addItem(item("Previous Tab", previous, key: "{", id: "previousTab"))
        tabs.addItem(
            item(
                "Previous Tab (Alternate)", previous, key: "\u{F700}", modifiers: [.command, .option],
                id: "selectPreviousTab", priority: .overrideWebView))
        // Hidden with their keys kept, as in Arc's menu.
        let switcher = [
            item(
                "Tab Switcher (forward)", #selector(BrowserWindowController.cycleToNextRecentTab(_:)), key: "\t",
                modifiers: .control, id: ModalItemSwitcher.cycleNextTabID, priority: .overrideWebView),
            item(
                "Tab Switcher (backward)", #selector(BrowserWindowController.cycleToPreviousRecentTab(_:)),
                key: "\u{19}", modifiers: [.control, .shift], id: ModalItemSwitcher.cyclePreviousTabID,
                priority: .overrideWebView),
        ]
        for item in switcher {
            item.isHidden = true
            item.allowsKeyEquivalentWhenHidden = true
            tabs.addItem(item)
        }
        tabs.addItem(.separator())
        for position in 1..<MainMenu.lastTabTag {
            let go = item(
                "Go to Sidebar Item \(position)", #selector(BrowserWindowController.selectTab(_:)), key: "\(position)",
                id: "item\(position)")
            go.tag = position
            tabs.addItem(go)
        }
        let last = item(
            "Go to last Sidebar Item", #selector(BrowserWindowController.selectTab(_:)), key: "9",
            id: "item\(MainMenu.lastTabTag)")
        last.tag = MainMenu.lastTabTag
        tabs.addItem(last)
        tabs.addItem(.separator())
        tabs.addItem(item("Favorite Tab", #selector(BrowserWindowController.toggleFavorite(_:))))
        tabs.addItem(item("Clear Today", #selector(BrowserWindowController.clearTabs(_:)), id: "clearExplore"))
        tabs.addItem(.separator())
        tabs.addItem(
            item(
                "Expand Peek", #selector(BrowserWindowController.expandPeek(_:)), key: "o", id: "openTabIn",
                priority: .promptAfterConsumedByWebView))

        let spaces = submenu("Spaces", in: menu)
        spaces.addItem(item("New Space…", #selector(BrowserWindowController.newSpace(_:)), id: "newSpace"))
        spaces.addItem(item("Rename Space…", #selector(BrowserWindowController.renameSpace(_:))))
        spaces.addItem(item("Change Profile", #selector(BrowserWindowController.changeProfile(_:))))
        spaces.addItem(item("Delete Space", #selector(BrowserWindowController.deleteSpace(_:))))

        submenu("Extensions", in: menu).delegate = extensionsMenu

        let window = submenu("Window", in: menu)
        window.addItem(
            item(
                "Minimize", #selector(NSWindow.performMiniaturize(_:)), key: "m", id: "minimize",
                priority: .overrideWebView))
        window.addItem(item("Zoom", #selector(NSWindow.performZoom(_:))))
        window.addItem(.separator())
        window.addItem(
            item("View Downloads…", #selector(BrowserWindowController.toggleDownloads(_:)), id: "viewDownloads"))
        window.addItem(.separator())
        window.addItem(item("Bring All to Front", #selector(NSApplication.arrangeInFront(_:))))
        application.windowsMenu = window

        let help = submenu("Help", in: menu)
        help.addItem(item("Restore Data…", #selector(ApplicationDelegate.restoreData(_:))))
        application.helpMenu = help

        application.mainMenu = menu
        keyBindingMenuManager = KeyBindingMenuManager(menu: menu, client: keyBindings)
    }

    private func submenu(_ title: String, in menu: NSMenu) -> NSMenu {
        let submenu = NSMenu(title: title)
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        menu.addItem(item)
        return submenu
    }

    /// The ID and the priority are the item's in Arc's menu, and make it a bindable action whose default is the
    /// key here.
    private func item(
        _ title: String, _ action: Selector, key: String = "", modifiers: NSEvent.ModifierFlags = .command,
        id: String? = nil, priority: KeyBinding.Priority = .low
    ) -> NSMenuItem {
        let item =
            id.map { id in
                let item = KeyBindableMenuItem(title: title, action: action, keyEquivalent: key)
                item.arcKeyBindingID = id
                item.arcKeyBindingPriority = priority
                return item
            } ?? NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = key.isEmpty ? [] : modifiers
        return item
    }
}
