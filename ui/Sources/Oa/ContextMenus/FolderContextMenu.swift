import AppKit

@MainActor
struct FolderContextMenu {
    let model: WindowModel
    let folder: SidebarFolder
    let changeIcon: () -> Void
    let rename: () -> Void

    func make() -> NSMenu {
        let selected = model.multiSelectedItemIDs
        if selected.contains(folder.id), selected.count > 1 || folder.gitHub == nil { return make(several: selected) }
        let menu = NSMenu()
        menu.autoenablesItems = false
        if let live = folder.gitHub {
            let options = NSMenu()
            options.autoenablesItems = false
            if live.error != nil {
                options.addItem(MenuActionItem("Failed to update"))
            } else if let date = live.lastFetch {
                options.addItem(MenuActionItem("Last fetch: " + date.formatted()))
            }
            options.addItem(
                MenuActionItem("Refresh") { [model, folder] in model.refreshLiveFolder(folder.id, manual: true) })
            options.addItem(.separator())
            for filter in GitHubPullRequestFilter.allCases {
                let item = MenuActionItem(filter.title) { [model, folder] in
                    model.toggleLiveFolderFilter(filter, in: folder.id)
                }
                item.state = live.enabledFilters.contains(filter) ? .on : .off
                options.addItem(item)
            }
            let repositories = model.state.liveFolderRepositories(in: folder.id)
            if !repositories.isEmpty {
                let submenu = NSMenu()
                submenu.autoenablesItems = false
                for name in repositories {
                    let item = MenuActionItem(name) { [model, folder] in
                        model.toggleLiveFolderRepository(name, in: folder.id)
                    }
                    item.state = live.includesRepository(name) ? .on : .off
                    submenu.addItem(item)
                }
                submenu.addItem(.separator())
                submenu.addItem(MenuActionItem("This list is generated based on your currently active pull requests."))
                options.addItem(.separator())
                options.addItem(MenuActionItem("Repositories", submenu: submenu))
            }
            menu.items = [
                MenuActionItem("Pull Requests", submenu: options),
                .separator(),
                MenuActionItem("Change Icon…", changeIcon),
                MenuActionItem("Rename…", rename),
                .separator(),
                MenuActionItem("Delete Live Folder") { [model, folder] in FolderDeletion.confirm(folder, in: model) },
            ]
            return menu
        }
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
