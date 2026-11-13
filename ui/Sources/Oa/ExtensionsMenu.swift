import AppKit

/// Arc's Extensions menu (arc-extensions.md §8, §8b): the profile's extensions by name, each running its action, a
/// disabled blank item in their place when there are none, then Add Extension… and Manage Extensions….
@MainActor
final class ExtensionsMenu: NSObject, NSMenuDelegate {
    /// The items go to the front browser window whatever window is key, as an extension's popup is.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let controller = NSApp.orderedWindows.lazy.compactMap { $0.windowController as? BrowserWindowController }.first
        let extensions = controller?.model.extensions ?? []
        for item in extensions {
            let run = menu.addItem(
                withTitle: item.name, action: #selector(BrowserWindowController.runExtension(_:)), keyEquivalent: "")
            run.representedObject = item.id
        }
        if extensions.isEmpty { menu.addItem(withTitle: "", action: nil, keyEquivalent: "") }
        menu.addItem(
            withTitle: "Add Extension…", action: #selector(BrowserWindowController.addExtension(_:)),
            keyEquivalent: "")
        menu.addItem(
            withTitle: "Manage Extensions…", action: #selector(BrowserWindowController.manageExtensions(_:)),
            keyEquivalent: "")
        for item in menu.items { item.target = controller }
    }
}
