import AppKit

@MainActor
final class MainMenu {
    func install(in application: NSApplication) {
        let menu = NSMenu()
        let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Oa"

        let app = submenu(appName, in: menu)
        app.addItem(item("About \(appName)", #selector(NSApplication.orderFrontStandardAboutPanel(_:))))
        app.addItem(.separator())
        app.addItem(item("Hide \(appName)", #selector(NSApplication.hide(_:)), key: "h"))
        app.addItem(
            item(
                "Hide Others", #selector(NSApplication.hideOtherApplications(_:)), key: "h",
                modifiers: [.command, .option]))
        app.addItem(item("Show All", #selector(NSApplication.unhideAllApplications(_:))))
        app.addItem(.separator())
        app.addItem(item("Quit \(appName)", #selector(NSApplication.terminate(_:)), key: "q"))

        let file = submenu("File", in: menu)
        file.addItem(item("New Window", #selector(ApplicationDelegate.newWindow(_:)), key: "n"))
        file.addItem(item("Open Location…", #selector(BrowserWindowController.openLocation(_:)), key: "l"))
        file.addItem(.separator())
        file.addItem(item("Close Window", #selector(NSWindow.performClose(_:)), key: "w"))

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

        let history = submenu("History", in: menu)
        history.addItem(item("Back", #selector(BrowserWindowController.goBack(_:)), key: "["))
        history.addItem(item("Forward", #selector(BrowserWindowController.goForward(_:)), key: "]"))

        let window = submenu("Window", in: menu)
        window.addItem(item("Minimize", #selector(NSWindow.performMiniaturize(_:)), key: "m"))
        window.addItem(item("Zoom", #selector(NSWindow.performZoom(_:))))
        window.addItem(.separator())
        window.addItem(item("Bring All to Front", #selector(NSApplication.arrangeInFront(_:))))
        application.windowsMenu = window

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
