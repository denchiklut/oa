import AppKit

/// Arc's tab menu (`SidebarMenu+TabContextMenu`) for one tab: a row, pinned or not, in a folder or not, or a
/// Favorite's tile. AppKit's, as Arc's is: a SwiftUI menu can't show a submenu disabled.
@MainActor
struct TabContextMenu {
    let model: WindowModel
    let tab: SidebarTab
    let changeIcon: () -> Void
    /// A row's inline field; a Favorite's tile has the dialog instead.
    var rename: () -> Void = {}

    func make() -> NSMenu {
        let state = model.state
        let favorite = state.isFavorite(tab.id)
        let current = model.selectedTabID == tab.id
        let menu = NSMenu()
        menu.autoenablesItems = false
        let copy = MenuActionItem("Copy Link") { [model, tab] in model.copyURL(of: tab.id) }
        if current { copy.shortcut("c", [.shift, .command]) }
        menu.addItem(copy)
        if let url = model.liveURL(of: tab.id) { menu.addItem(share(url)) }
        menu.addItem(.separator())
        menu.addItem(MenuActionItem("Change Icon…", changeIcon))
        menu.addItem(
            MenuActionItem("Rename…") { [model, tab, rename] in
                guard favorite else { return rename() }
                // As Arc's: the Favorite is selected first, then asked about.
                model.select(tab.id)
                presentRenameDialog(for: tab, in: model)
            })
        // As Arc's: on while the page plays sound or is muted, never without a page.
        let audio = model.audio(of: tab.id)
        menu.addItem(
            MenuActionItem(
                audio?.isMuted == true ? "Unmute" : "Mute", enabled: audio.map { $0.isAudible || $0.isMuted } ?? false
            ) { [model, tab] in model.toggleMuted(tab.id) })
        // Arc's opens Boosts, which Oa doesn't have.
        if let scheme = model.pages[tab.id]?.url?.scheme, scheme == "http" || scheme == "https" {
            menu.addItem(MenuActionItem("Customize Page…"))
        }
        if favorite || state.isPinned(tab.id), let url = tab.url { menu.addItem(editPinnedPage(url)) }
        menu.addItem(.separator())
        if current {
            menu.addItem(
                MenuActionItem("Add Split View", enabled: model.canAddSplitViewPane) { [model] in
                    model.addSplitViewPane()
                })
        } else {
            menu.addItem(
                MenuActionItem("Open in Split View", enabled: model.canOpenInSplitView(tab.id)) { [model, tab] in
                    model.openInSplitView(tab.id)
                })
        }
        menu.addItem(move(favorite: favorite))
        menu.addItem(.separator())
        for item in removal(favorite: favorite, current: current) { menu.addItem(item) }
        return menu
    }

    private func editPinnedPage(_ url: URL) -> NSMenuItem {
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        submenu.addItem(
            MenuActionItem("Replace Pinned URL with Current", enabled: model.leftAddress(tab) != nil) {
                [model, tab] in model.replacePinnedURLWithCurrent(tab.id)
            })
        submenu.addItem(
            MenuActionItem("Edit…") { [model, tab] in
                guard let window = model.window else { return }
                DialogSheet.present(on: window) { dismiss in
                    TextInputDialog(
                        title: "Edit Pinned URL",
                        message: "This is what opens first when you click this tab or its favicon.",
                        icon: model.favicon(for: tab), text: url.absoluteString, placeholder: "Enter a URL…",
                        confirmTitle: "Save", width: 393
                    ) { text in
                        dismiss()
                        if let url = Self.typedURL(text) { model.editPinnedURL(tab.id, to: url) }
                    } onCancel: {
                        dismiss()
                    }
                }
            })
        return MenuActionItem("Edit Pinned Page", submenu: submenu)
    }

    /// Oa's own: an address typed without a scheme is taken as https.
    private static func typedURL(_ text: String) -> URL? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !text.contains(" ") else { return nil }
        let url = URL(string: text)
        return url?.scheme != nil && url?.host() != nil || url?.scheme == "about" ? url : URL(string: "https://" + text)
    }

    private func presentRenameDialog(for tab: SidebarTab, in model: WindowModel) {
        guard let window = model.window else { return }
        DialogSheet.present(on: window) { [model] dismiss in
            TextInputDialog(
                title: "Rename Tab…", text: tab.displayTitle, placeholder: "Keep it short and sweet!",
                confirmTitle: "Rename"
            ) { title in
                model.renameTab(tab.id, to: title)
                dismiss()
            } onCancel: {
                dismiss()
            }
        }
    }

    /// As Arc's: the system's sharing services for the address without its trackers, each with its own title and
    /// image, and no "More…".
    private func share(_ url: URL) -> NSMenuItem {
        let shared = url.withTrackingRemoved.url
        let submenu = NSMenu()
        for service in (NSSharingService.self as SharingServiceList.Type).sharingServices(forItems: [shared]) {
            let item = MenuActionItem(service.menuItemTitle) { service.perform(withItems: [shared]) }
            item.image = service.image
            submenu.addItem(item)
        }
        return MenuActionItem("Share", submenu: submenu)
    }

    /// Every Space, the tab's own ticked, then New Space…. Arc lists profiles for a Favorite; moving one to another
    /// profile isn't Oa's yet.
    private func move(favorite: Bool) -> NSMenuItem {
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        guard !favorite else { return MenuActionItem("Move to", submenu: submenu, enabled: false) }
        let spaceID = model.state.space(containing: tab.id)?.id
        for space in model.state.spaces {
            let item = MenuActionItem(space.name) { [model, tab] in model.moveItem(tab.id, toSpace: space.id) }
            item.state = space.id == spaceID ? .on : .off
            submenu.addItem(item)
        }
        submenu.addItem(.separator())
        submenu.addItem(
            MenuActionItem("New Space…") { [model, tab] in
                model.beginSpaceCreation(after: model.selectedSpaceID, moving: tab.id)
            })
        return MenuActionItem("Move to", submenu: submenu)
    }

    /// Arc's `CloseSidebarItemConstants`: a Favorite closes while shown and is removed, a pin is removed, which
    /// archives it, and a Today tab is archived.
    private func removal(favorite: Bool, current: Bool) -> [NSMenuItem] {
        if favorite {
            let remove = MenuActionItem("Remove Favorite") { [model, tab] in model.removeFavorite(tab.id) }
            guard current else { return [remove] }
            let close = MenuActionItem("Close Tab") { [model, tab] in model.close(tab.id) }
            close.shortcut("w", .command)
            return [close, remove]
        }
        if model.state.isPinned(tab.id) {
            return [MenuActionItem("Remove Pin") { [model, tab] in model.archivePinned(tab.id) }]
        }
        let last = model.state.space(containing: tab.id).flatMap { model.state.tabs(in: $0.id, pinned: false).last }
        return [
            MenuActionItem("Archive Tab") { [model, tab] in model.close(tab.id) },
            MenuActionItem("Archive Tabs Below", enabled: last?.id != tab.id) { [model, tab] in
                model.archiveTabs(below: tab.id)
            },
        ]
    }
}

/// Arc's list of services, which AppKit has deprecated for its own Share item, reached without the warning.
private protocol SharingServiceList {
    static func sharingServices(forItems items: [Any]) -> [NSSharingService]
}

extension NSSharingService: SharingServiceList {}

extension NSMenuItem {
    func shortcut(_ key: String, _ modifiers: NSEvent.ModifierFlags) {
        keyEquivalent = key
        keyEquivalentModifierMask = modifiers
    }
}
