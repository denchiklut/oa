import AppKit

@MainActor
final class MainMenu {
    static let lastTabTag = 9
    private let extensionsMenu = ExtensionsMenu()

    func install(in application: NSApplication) {
        let menu = NSMenu()
        let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Oa"

        let app = submenu(appName, in: menu)
        app.addItem(item("About \(appName)", #selector(NSApplication.orderFrontStandardAboutPanel(_:))))
        app.addItem(.separator())
        app.addItem(item("Settings…", #selector(ApplicationDelegate.showSettings(_:)), key: ","))
        app.addItem(.separator())
        app.addItem(item("Hide \(appName)", #selector(NSApplication.hide(_:)), key: "h"))
        app.addItem(
            item(
                "Hide Others", #selector(NSApplication.hideOtherApplications(_:)), key: "h",
                modifiers: [.command, .option]))
        app.addItem(item("Show All", #selector(NSApplication.unhideAllApplications(_:))))
        app.addItem(.separator())
        app.addItem(item("Quit \(appName)", #selector(ApplicationDelegate.quit(_:)), key: "q"))

        let file = submenu("File", in: menu)
        file.addItem(item("New Window", #selector(ApplicationDelegate.newWindow(_:)), key: "n"))
        file.addItem(item("New Tab", #selector(BrowserWindowController.newTab(_:)), key: "t"))
        file.addItem(item("Open Location…", #selector(BrowserWindowController.openLocation(_:)), key: "l"))
        file.addItem(.separator())
        file.addItem(item("Pin Tab", #selector(BrowserWindowController.togglePin(_:)), key: "d"))
        file.addItem(.separator())
        file.addItem(item("Close Tab", #selector(BrowserWindowController.closeTab(_:)), key: "w"))
        file.addItem(
            item("Close Window", #selector(NSWindow.performClose(_:)), key: "w", modifiers: [.command, .shift]))
        file.addItem(
            item(
                "Restore Last Closed Tab", #selector(BrowserWindowController.restoreLastClosed(_:)), key: "t",
                modifiers: [.command, .shift]))

        let edit = submenu("Edit", in: menu)
        edit.addItem(item("Undo", Selector(("undo:")), key: "z"))
        edit.addItem(item("Redo", Selector(("redo:")), key: "z", modifiers: [.command, .shift]))
        edit.addItem(.separator())
        edit.addItem(item("Cut", #selector(NSText.cut(_:)), key: "x"))
        edit.addItem(item("Copy", #selector(NSText.copy(_:)), key: "c"))
        edit.addItem(item("Paste", #selector(NSText.paste(_:)), key: "v"))
        edit.addItem(item("Select All", #selector(NSText.selectAll(_:)), key: "a"))

        let view = submenu("View", in: menu)
        view.addItem(item("Reload Page", #selector(BrowserWindowController.reload(_:)), key: "r"))
        view.addItem(item("Stop Loading", #selector(BrowserWindowController.stopLoading(_:)), key: "."))

        let archive = submenu("Archive", in: menu)
        archive.addItem(item("Back", #selector(BrowserWindowController.goBack(_:)), key: "["))
        archive.addItem(item("Forward", #selector(BrowserWindowController.goForward(_:)), key: "]"))
        archive.addItem(.separator())
        archive.addItem(item("View History", #selector(BrowserWindowController.viewHistory(_:)), key: "y"))
        archive.addItem(item("View Archive…", #selector(BrowserWindowController.toggleArchive(_:))))
        archive.addItem(item("Clear Archive", #selector(BrowserWindowController.clearArchive(_:))))

        let tabs = submenu("Tabs", in: menu)
        let next = #selector(BrowserWindowController.selectNextTab(_:))
        let previous = #selector(BrowserWindowController.selectPreviousTab(_:))
        tabs.addItem(item("Next Tab", next, key: "}"))
        tabs.addItem(item("Next Tab (Alternate)", next, key: "\u{F701}", modifiers: [.command, .option]))
        tabs.addItem(item("Previous Tab", previous, key: "{"))
        tabs.addItem(item("Previous Tab (Alternate)", previous, key: "\u{F700}", modifiers: [.command, .option]))
        tabs.addItem(.separator())
        for position in 1..<MainMenu.lastTabTag {
            let go = item(
                "Go to Sidebar Item \(position)", #selector(BrowserWindowController.selectTab(_:)), key: "\(position)")
            go.tag = position
            tabs.addItem(go)
        }
        let last = item("Go to last Sidebar Item", #selector(BrowserWindowController.selectTab(_:)), key: "9")
        last.tag = MainMenu.lastTabTag
        tabs.addItem(last)
        tabs.addItem(.separator())
        tabs.addItem(item("Favorite Tab", #selector(BrowserWindowController.toggleFavorite(_:))))
        tabs.addItem(.separator())
        tabs.addItem(item("Expand Peek", #selector(BrowserWindowController.expandPeek(_:)), key: "o"))

        let spaces = submenu("Spaces", in: menu)
        spaces.addItem(item("New Space…", #selector(BrowserWindowController.newSpace(_:))))
        spaces.addItem(item("Rename Space…", #selector(BrowserWindowController.renameSpace(_:))))
        spaces.addItem(item("Delete Space", #selector(BrowserWindowController.deleteSpace(_:))))

        submenu("Extensions", in: menu).delegate = extensionsMenu

        let window = submenu("Window", in: menu)
        window.addItem(item("Minimize", #selector(NSWindow.performMiniaturize(_:)), key: "m"))
        window.addItem(item("Zoom", #selector(NSWindow.performZoom(_:))))
        window.addItem(.separator())
        window.addItem(item("View Downloads…", #selector(BrowserWindowController.toggleDownloads(_:))))
        window.addItem(.separator())
        window.addItem(item("Bring All to Front", #selector(NSApplication.arrangeInFront(_:))))
        application.windowsMenu = window

        let help = submenu("Help", in: menu)
        help.addItem(item("Restore Data…", #selector(ApplicationDelegate.restoreData(_:))))
        application.helpMenu = help

        application.mainMenu = menu
    }

    private func submenu(_ title: String, in menu: NSMenu) -> NSMenu {
        let submenu = NSMenu(title: title)
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        menu.addItem(item)
        return submenu
    }

    private func item(
        _ title: String, _ action: Selector, key: String = "", modifiers: NSEvent.ModifierFlags = .command
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = key.isEmpty ? [] : modifiers
        return item
    }
}
