import AppKit

@MainActor
struct FolderContextMenu {
    let model: WindowModel
    let folder: SidebarFolder
    let changeIcon: () -> Void
    let rename: () -> Void

    func make() -> NSMenu {
        let selected = model.multiSelectedItemIDs
        if selected.contains(folder.id) { return make(several: selected) }
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.items = [
            MenuActionItem("Share Folder…"),
            .separator(),
            MenuActionItem(
                "New Nested Folder…", enabled: model.state.canCreateFolder(in: folder.id)
            ) { [model, folder] in
                model.createNestedFolder(in: folder.id)
            },
            MenuActionItem("Turn “\(folder.displayTitle)” into Space"),
            MenuActionItem("Copy All Links"),
            .alternate(MenuActionItem("Copy All Links as Markdown")),
            .separator(),
            MenuActionItem("Change Icon…", changeIcon),
            MenuActionItem("Rename…", rename),
            .separator(),
            MenuActionItem("Duplicate"),
            MenuActionItem("Move to", submenu: NSMenu(), enabled: false),
            .separator(),
            MenuActionItem("Delete") { [model, folder] in FolderDeletion.confirm(folder, in: model) },
        ]
        return menu
    }

    private func make(several itemIDs: [UUID]) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        if model.sidebarContext == .global {
            menu.addItem(
                MenuActionItem("New Folder with \(itemIDs.count) Items") { [model] in
                    model.createFolder(wrapping: itemIDs)
                })
            menu.addItem(.separator())
        }
        menu.addItem(
            MenuActionItem("Delete Folders", enabled: itemIDs.allSatisfy { model.state.tree.folder($0) != nil }) {
                [model] in
                for id in model.state.topLevelItemIDs(in: itemIDs) {
                    if let folder = model.state.tree.folder(id) { FolderDeletion.confirm(folder, in: model) }
                }
            })
        return menu
    }
}
