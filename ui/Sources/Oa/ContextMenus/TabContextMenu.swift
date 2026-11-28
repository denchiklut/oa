import AppKit

/// Arc's tab menu (`SidebarMenu+TabContextMenu`) for one tab: a row, pinned or not, in a folder or not, or a
/// Favorite's tile; or, as Arc's `menu(clickedItem:)`, for every selected row when the row clicked is one of them.
/// AppKit's, as Arc's is: a SwiftUI menu can't show a submenu disabled.
@MainActor
struct TabContextMenu {
    let model: WindowModel
    let tab: SidebarTab
    let changeIcon: () -> Void
    /// A row's inline field; a Favorite's tile has the dialog instead.
    var rename: () -> Void = {}

    func make() -> NSMenu {
        let selected = model.multiSelectedItemIDs
        if selected.contains(tab.id), selected.count > 1 || tab.liveURL == nil { return make(several: selected) }
        let state = model.state
        let favorite = state.isFavorite(tab.id)
        let current = model.selectedTabID == tab.id
        let menu = NSMenu()
        menu.autoenablesItems = false
        if favorite, let type = PreviewType.matching(url: tab.url, tabID: tab.id), type.isCalendar,
            let host = PreviewType.calendarDefaultsHost(for: tab.url)
        {
            menu.addItem(liveCalendarMenu(host: host, type: type))
            menu.addItem(.separator())
        }
        let copy = MenuActionItem("Copy Link") { [model, tab] in model.copyURL(of: tab.id) }
        if current { copy.shortcut("c", [.shift, .command]) }
        menu.addItem(copy)
        if let url = model.liveURL(of: tab.id) { menu.addItem(share(url)) }
        if favorite, let badge = FavoriteUnreadBadge.matching(url: tab.url) {
            menu.addItem(.separator())
            let item = MenuActionItem("Show Unread Badge") {
                PreviewSettings.shared.toggleBadging(forHost: badge.defaultsHost)
            }
            item.state = PreviewSettings.shared.isBadgingEnabled(forHost: badge.defaultsHost) ? .on : .off
            menu.addItem(item)
        }
        if let url = tab.liveURL {
            menu.addItem(
                MenuActionItem("Copy PR #") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(url.lastPathComponent, forType: .string)
                })
            menu.addItem(.separator())
            menu.addItem(MenuActionItem("Archive Item") { [model, tab] in model.archivePinned(tab.id) })
            return menu
        }
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
        // Arc's opens Boosts, which Oa doesn't have. As seen in Arc, an incognito window has none.
        if model.sidebarContext != .incognito, let scheme = model.pages[tab.id]?.url?.scheme,
            scheme == "http" || scheme == "https"
        {
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
        menu.addItem(MenuActionItem("Duplicate") { [model, tab] in model.duplicate(tab.id) })
        // As seen in Arc, an incognito window has none.
        if model.sidebarContext != .incognito { menu.addItem(move([tab.id], favorite: favorite)) }
        menu.addItem(.separator())
        for item in removal(favorite: favorite, current: current) { menu.addItem(item) }
        return menu
    }

    /// As seen in Arc for several rows: no one-item entries, Change Icon… off, New Folder with N Items under Move to,
    /// and the last group by kind. Share N Items… (Arc's sharing service) is left out, as Oa's own.
    private func make(several itemIDs: [UUID]) -> NSMenu {
        let state = model.state
        let tabIDs = itemIDs.filter { state.tree.tab($0) != nil }
        let hasFolders = tabIDs.count < itemIDs.count
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(MenuActionItem("Copy Links", enabled: !tabIDs.isEmpty) { [model] in model.copyURLs(of: tabIDs) })
        menu.addItem(.separator())
        menu.addItem(MenuActionItem("Change Icon…", enabled: false))
        let audio = tabIDs.map(model.audio(of:))
        let muted = !tabIDs.isEmpty && audio.allSatisfy { $0?.isMuted == true }
        menu.addItem(
            MenuActionItem(muted ? "Unmute" : "Mute", enabled: muted || audio.contains { $0?.isAudible == true }) {
                [model] in model.toggleMuted(tabIDs)
            })
        menu.addItem(.separator())
        menu.addItem(
            MenuActionItem("Open in Split View", enabled: !hasFolders && model.canOpenInSplitView(tabIDs)) { [model] in
                model.openInSplitView(tabIDs)
            })
        menu.addItem(
            MenuActionItem("Duplicate", enabled: !hasFolders) { [model] in
                for tabID in tabIDs { model.duplicate(tabID) }
            })
        if model.sidebarContext != .incognito {
            if !hasFolders { menu.addItem(move(tabIDs, favorite: false)) }
            if model.sidebarContext == .global {
                menu.addItem(
                    MenuActionItem("New Folder with \(itemIDs.count) Items") { [model] in
                        model.createFolder(wrapping: itemIDs)
                    })
            }
        }
        menu.addItem(.separator())
        let pinned = tabIDs.filter(state.isPinned)
        if !hasFolders, pinned.count == tabIDs.count {
            menu.addItem(MenuActionItem("Remove Pins") { [model] in model.archiveTabs(tabIDs) })
        } else if !hasFolders {
            menu.addItem(MenuActionItem("Archive Tabs") { [model] in model.archiveTabs(tabIDs) })
            // As Arc's: below and above are for one tab.
            if pinned.isEmpty {
                menu.addItem(archiveOtherTabs(keeping: tabIDs))
                menu.addItem(MenuActionItem("Archive Tabs Below", enabled: false))
                menu.addItem(.alternate(MenuActionItem("Archive Tabs Above", enabled: false)))
            }
        } else {
            menu.addItem(
                MenuActionItem("Archive Items") { [model] in
                    let roots = model.state.topLevelItemIDs(in: itemIDs)
                    let standaloneTabs = roots.filter { model.state.tree.tab($0) != nil }
                    if !standaloneTabs.isEmpty { model.archiveTabs(standaloneTabs) }
                    FolderDeletion.confirm(roots[...], in: model)
                })
        }
        return menu
    }

    /// As seen in Arc (`arc-tab-context-menu-multi-live.md` §5, `0x102f4f500`): Live Calendar submenu at the top of a
    /// Calendar Favorite's context menu.
    private func liveCalendarMenu(host: String, type: PreviewType) -> NSMenuItem {
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        let record = model.previewRecord(for: tab)
        let status: String =
            switch record?.state {
            case .loaded:
                if let date = record?.lastRefreshed {
                    "Updated \(date.formatted(.relative(presentation: .named)))"
                } else {
                    "Updated"
                }
            case .loading: "Updating…"
            case .signedOut: "Sign in to update"
            case .disconnected: "Calendar not connected"
            case .failed: "Failed to update"
            case nil: "Not updated yet"
            }
        submenu.addItem(MenuActionItem(status, enabled: false))
        submenu.addItem(MenuActionItem("Refresh") { [model, tab] in model.refreshPreview(for: tab, force: true) })
        if type.isNotionCalendar {
            submenu.addItem(notionAccountMenu(record: record))
        }
        submenu.addItem(.separator())
        let hover = MenuActionItem("Show Hover Preview") {
            PreviewSettings.shared.liveCalendarHoverEnabled.toggle()
        }
        hover.state = PreviewSettings.shared.liveCalendarHoverEnabled ? .on : .off
        submenu.addItem(hover)
        let subtitle = MenuActionItem("Show Time to Next Meeting") {
            PreviewSettings.shared.toggleSubtitle(forHost: host)
        }
        subtitle.state = PreviewSettings.shared.isSubtitleEnabled(forHost: host) ? .on : .off
        submenu.addItem(subtitle)
        if let profileID = model.previewProfileID(for: tab) {
            let intervalMenu = NSMenu()
            intervalMenu.autoenablesItems = false
            let current = PreviewSettings.shared.liveCalendarInterval(for: profileID)
            for interval in LiveCalendarInterval.allCases {
                let item = MenuActionItem(interval.title) {
                    PreviewSettings.shared.setLiveCalendarInterval(interval, for: profileID)
                }
                item.state = interval == current ? .on : .off
                intervalMenu.addItem(item)
            }
            submenu.addItem(MenuActionItem("Show Next Meeting Link", submenu: intervalMenu))
        }
        return MenuActionItem("Live Calendar", submenu: submenu)
    }

    /// Oa's own: selects which Google Calendar account in this profile backs a Notion Calendar tab.
    private func notionAccountMenu(record: PreviewRecord?) -> NSMenuItem {
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        let currentAccount = model.resolvedNotionAccount(for: tab)
        let loadedEmail: String? =
            if case .loaded(.calendar(_, _, let email, _)) = record?.state { email } else { nil }
        let disconnect = MenuActionItem("Not Connected") { [model, tab] in
            model.connectNotionCalendar(for: tab, accountNumber: nil)
        }
        disconnect.state = currentAccount == nil ? .on : .off
        submenu.addItem(disconnect)
        submenu.addItem(.separator())
        for index in 0..<3 {
            let label =
                if currentAccount == index, let loadedEmail {
                    "Google Account \(index + 1) (\(loadedEmail))"
                } else {
                    "Google Account \(index + 1) (/u/\(index))"
                }
            let item = MenuActionItem(label) { [model, tab] in
                model.connectNotionCalendar(for: tab, accountNumber: index)
            }
            item.state = currentAccount == index ? .on : .off
            submenu.addItem(item)
        }
        return MenuActionItem("Google Account", submenu: submenu)
    }

    private func editPinnedPage(_ url: URL) -> NSMenuItem {
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        submenu.addItem(
            MenuActionItem("Replace Pinned URL with Current", enabled: model.liveLeftAddress(tab) != nil) {
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

    /// Every global Space, the tab's own ticked, then New Space…, which does nothing in a Blank Window as Arc's
    /// `showSpaceCreationFlow` there; for a Favorite, as Arc's, a Profile submenu of every profile with a Space, its
    /// own ticked.
    private func move(_ tabIDs: [UUID], favorite: Bool) -> NSMenuItem {
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        guard !favorite else {
            let profiles = NSMenu()
            profiles.autoenablesItems = false
            let ownID = model.state.profile(containing: tab.id)?.id
            for profile in model.profiles where model.state.spaces.contains(where: { $0.profileID == profile.id }) {
                let item = MenuActionItem(profile.name) { [model, tab] in
                    model.moveFavorite(tab.id, toProfile: profile.id)
                }
                item.state = profile.id == ownID ? .on : .off
                profiles.addItem(item)
            }
            submenu.addItem(MenuActionItem("Profile", submenu: profiles))
            return MenuActionItem("Move to", submenu: submenu)
        }
        let spaceID = model.state.space(containing: tab.id)?.id
        for space in model.state.spaces {
            let item = MenuActionItem(space.name) { [model] in model.moveItems(tabIDs, toSpace: space.id) }
            item.state = space.id == spaceID ? .on : .off
            submenu.addItem(item)
        }
        submenu.addItem(.separator())
        submenu.addItem(
            MenuActionItem("New Space…") { [model] in
                model.beginSpaceCreation(after: model.selectedSpaceID, moving: tabIDs)
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
        let tabs = model.state.space(containing: tab.id).map { model.state.tabs(in: $0.id, pinned: false) } ?? []
        return [
            MenuActionItem("Archive Tab") { [model, tab] in model.close(tab.id) },
            archiveOtherTabs(keeping: [tab.id]),
            MenuActionItem("Archive Tabs Below", enabled: tabs.last?.id != tab.id) { [model, tab] in
                model.archiveTabs(below: tab.id)
            },
            .alternate(
                MenuActionItem("Archive Tabs Above", enabled: tabs.first?.id != tab.id) { [model, tab] in
                    model.archiveTabs(above: tab.id)
                }),
        ]
    }

    /// Arc's ⌥ alternate of Archive Tab(s), for Today tabs only.
    private func archiveOtherTabs(keeping tabIDs: [UUID]) -> NSMenuItem {
        .alternate(
            MenuActionItem("Archive Other Tabs", enabled: model.hasOtherTabs(than: tabIDs)) { [model] in
                model.archiveOtherTabs(keeping: tabIDs)
            })
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

    /// As Arc's generator: shown in place of the item before it while ⌥ is held.
    static func alternate(_ item: NSMenuItem) -> NSMenuItem {
        item.keyEquivalentModifierMask = .option
        item.isAlternate = true
        return item
    }
}
