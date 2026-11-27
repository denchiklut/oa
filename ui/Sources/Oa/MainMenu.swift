import AppKit

@MainActor
final class MainMenu {
    static let lastTabTag = 9
    private let extensionsMenu = ExtensionsMenu()
    private var keyBindingMenuManager: KeyBindingMenuManager?
    private var spacesMainMenuProvider: SpacesMainMenuProvider?

    func install(in application: NSApplication, store: SidebarStore) {
        let menu = NSMenu()
        let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Oa"

        let app = submenu(appName, in: menu)
        app.addItem(
            item("About \(appName)", #selector(NSApplication.orderFrontStandardAboutPanel(_:)))
                .typeTravel("aboutArc", icon: "book.closed"))
        app.addItem(.separator())
        app.addItem(item("Settings…", #selector(ApplicationDelegate.showSettings(_:)), key: ",", id: "viewPreferences"))
        app.addItem(.separator())
        app.addItem(
            item(
                "Hide \(appName)", #selector(NSApplication.hide(_:)), key: "h", id: "hideArc",
                priority: .overrideWebView
            ).typeTravel("hideArc", icon: "macwindow", triggers: ["Hide \(appName)", "Hide Arc"]))
        app.addItem(
            item(
                "Hide Others", #selector(NSApplication.hideOtherApplications(_:)), key: "h",
                modifiers: [.command, .option], id: "hideOthers"
            ).typeTravel("hideOthers", icon: "macwindow", triggers: ["Hide Others", "Hide Other Windows"]))
        app.addItem(
            item("Show All", #selector(NSApplication.unhideAllApplications(_:)))
                .typeTravel("showAll", icon: "book"))
        app.addItem(.separator())
        app.addItem(
            item(
                "Quit \(appName)", #selector(ApplicationDelegate.quit(_:)), key: "q", id: "quitArc",
                priority: .overrideWebView
            ).typeTravel("quitArc", icon: "hand.wave", triggers: ["Quit App"]))

        let file = submenu("File", in: menu)
        file.addItem(
            item(
                "New Window", #selector(ApplicationDelegate.newWindow(_:)), key: "n", id: "newWindow",
                priority: .overrideWebView
            ).typeTravel(
                "newWindow", icon: "plus.rectangle", triggers: ["Create Window", "Copy Window", "Duplicate Window"]))
        file.addItem(
            item(
                "Blank Window", #selector(ApplicationDelegate.blankWindow(_:)), key: "n",
                modifiers: [.command, .control], id: "newBlankWindow"
            ).typeTravel("blankWindow", icon: "macwindow.on.rectangle", triggers: ["Create Window"]))
        file.addItem(
            item(
                "New Incognito Window", #selector(ApplicationDelegate.newIncognitoWindow(_:)), key: "n",
                modifiers: [.command, .shift], id: "newIncognitoWindow", priority: .overrideWebView
            ).typeTravel(
                "newIncognitoWindow", icon: "macwindow.on.rectangle",
                triggers: ["Create Incognito Window", "New Private Window", "Incognito"]))
        file.addItem(
            item(
                "New Little Oa Window", #selector(ApplicationDelegate.newLittleBrowserWindow(_:)), key: "n",
                modifiers: [.command, .option], id: "showLittleArc", priority: .overrideWebView
            ).typeTravel(
                "newLittleBrowserWindow", icon: "macwindow.on.rectangle",
                triggers: ["Quick Lookup", "Mini Window", "Floating Window", "Little Arc"]))
        file.addItem(
            item(
                "New Tab", #selector(BrowserWindowController.newTab(_:)), key: "t", id: "newTab",
                priority: .overrideWebView))
        file.addItem(
            item("New Profile", #selector(BrowserWindowController.newProfile(_:)))
                .typeTravel("newProfile", icon: "person.fill", triggers: ["Profile"]))
        file.addItem(
            item(
                "Open Location…", #selector(BrowserWindowController.openLocation(_:)), key: "l", id: "addressBar",
                priority: .overrideWebView))
        file.addItem(.separator())
        file.addItem(
            item(
                "Pin/Unpin Tab", #selector(BrowserWindowController.togglePin(_:)), key: "d", id: "pinTab",
                priority: .promptAfterConsumedByWebView
            ).typeTravel("pinTab", icon: "pin", triggers: ["save", "Pin Tab", "Unpin Tab"]))
        file.addItem(.separator())
        file.addItem(
            item(
                "Archive Tab", #selector(BrowserWindowController.closeTab(_:)), key: "w", id: "archiveTab",
                priority: .overrideWebView
            ).typeTravel("archiveTab", icon: "archivebox", triggers: ["Exit Tab", "Unload", "Deselect", "Close"]))
        file.addItem(
            item(
                "Close Window", #selector(NSWindow.performClose(_:)), key: "w", modifiers: [.command, .shift],
                id: "closeWindow", priority: .overrideWebView
            ).typeTravel("closeWindow", icon: "xmark.circle", triggers: ["Exit Window"]))
        file.addItem(
            item(
                "Restore Last Closed Tab", #selector(BrowserWindowController.restoreLastClosed(_:)), key: "t",
                modifiers: [.command, .shift], id: "reopenLastClosedTab", priority: .overrideWebView
            ).typeTravel("reopenClosedTab", icon: "arrow.uturn.backward", triggers: ["Reopen Closed Tab"]))
        file.addItem(.separator())
        file.addItem(
            item(
                "Capture…", #selector(BrowserWindowController.capturePage(_:)), key: "2",
                modifiers: [.command, .shift], id: "capturePage", priority: .overrideWebView
            )
            .typeTravel("capturePage", icon: "camera", triggers: ["Screenshot", "Snapshot", "Cut Out"]))
        file.addItem(
            item("Capture in Portrait Mode", #selector(BrowserWindowController.capturePrettyScreenshot(_:)))
                .typeTravel(
                    "capturePrettyScreenshot", icon: "camera.macro", triggers: ["Capture Portrait", "Screenshot"]))
        file.addItem(
            item(
                "Save Page As", #selector(BrowserWindowController.savePageAs(_:)), key: "s",
                modifiers: [.command, .shift], id: "savePageAs"
            ).typeTravel("save", icon: "square.and.arrow.down", triggers: ["Save Page", "Save File"]))
        file.addItem(
            item(
                "Print", #selector(BrowserWindowController.printPage(_:)), key: "p", id: "printPage",
                priority: .promptAfterConsumedByWebView
            ).typeTravel("printPage", icon: "printer", triggers: ["Print Page"]))

        let edit = submenu("Edit", in: menu)
        edit.addItem(item("Undo", Selector(("undo:")), key: "z"))
        edit.addItem(item("Redo", Selector(("redo:")), key: "z", modifiers: [.command, .shift]))
        edit.addItem(.separator())
        edit.addItem(item("Cut", #selector(NSText.cut(_:)), key: "x").typeTravel("cut", icon: "scissors"))
        edit.addItem(item("Copy", #selector(NSText.copy(_:)), key: "c").typeTravel("copy", icon: "doc.on.doc"))
        edit.addItem(
            item(
                "Copy URL", #selector(BrowserWindowController.copyCurrentURL(_:)), key: "c",
                modifiers: [.command, .shift], id: "copyCurrentURL", priority: .overrideWebView
            ).typeTravel("copyCurrentURL", icon: "doc.on.doc", triggers: ["Copy URL", "Copy Link"]))
        edit.addItem(
            item(
                "Copy URL as Markdown", #selector(BrowserWindowController.copyCurrentURLAsMarkdown(_:)), key: "c",
                modifiers: [.command, .shift, .option], id: "copyCurrentURLMarkdown", priority: .overrideWebView
            ).typeTravel(
                "copyCurrentURLAsMarkdown", icon: "doc.on.doc",
                triggers: ["Copy Link as Markdown", "Copy Markdown"]))
        edit.addItem(item("Paste", #selector(NSText.paste(_:)), key: "v").typeTravel("paste", icon: "list.clipboard"))
        edit.addItem(
            item(
                "Paste and Match Style", #selector(NSTextView.pasteAsPlainText(_:)), key: "v",
                modifiers: [.command, .shift], id: "pasteAndMatchStyle"
            ).typeTravel("pasteAndMatchStyle", icon: "list.clipboard", triggers: ["Paste Without Formatting"]))
        edit.addItem(
            item("Select All", #selector(NSText.selectAll(_:)), key: "a")
                .typeTravel("selectAll", icon: "square.grid.2x2.fill"))
        edit.addItem(.separator())
        let find = submenu("Find", in: edit)
        let findAction = #selector(BrowserWindowController.arcPerformFindPanelAction(_:))
        let findItems: [(String, String, NSEvent.ModifierFlags, String, NSTextFinder.Action?, String, [String])] = [
            ("Find…", "f", .command, "find", .showFindInterface, "magnifyingglass", ["Find in Page"]),
            (
                "Find and Replace", "f", [.command, .option], "findAndReplace", .showReplaceInterface,
                "magnifyingglass",
                []
            ),
            ("Find Next", "g", .command, "findNext", .nextMatch, "arrow.right", ["Next"]),
            ("Find Previous", "g", [.command, .shift], "findPrevious", .previousMatch, "arrow.left", ["Previous"]),
            (
                "Use Selection to Find", "", .command, "useSelectionForFind", .setSearchString, "magnifyingglass",
                ["Find Selection", "Find Selected"]
            ),
            // Arc's tag 0, which no handler answers.
            (
                "Jump to Selection", "j", .command, "jumpToSelection", nil, "arrow.turn.right.down",
                ["Jump to Selected", "Selection"]
            ),
        ]
        for (title, key, modifiers, id, action, icon, triggers) in findItems {
            let findItem = item(title, findAction, key: key, modifiers: modifiers, id: id)
                .typeTravel(id, icon: icon, triggers: triggers)
            findItem.tag = action?.rawValue ?? 0
            find.addItem(findItem)
        }

        let view = submenu("View", in: menu)
        let appearance = submenu("Appearance", in: view)
        let header = NSMenuItem(title: "Websites will use:", action: nil, keyEquivalent: "")
        header.isEnabled = false
        appearance.addItem(header)
        appearance.addItem(
            item("Automatic", #selector(ApplicationDelegate.setAutomaticAppearance(_:))).typeTravel(
                "automaticMode", icon: "sparkles", title: "Switch to Automatic Appearance",
                triggers: ["Switch to Automatic Appearance", "Switch Automatic Mode", "Automatic Mode"]))
        appearance.addItem(
            item("Light", #selector(ApplicationDelegate.setLightAppearance(_:))).typeTravel(
                "lightMode", icon: "sun.max", title: "Switch to Light Mode",
                triggers: ["Switch to Light Mode", "Switch Light Mode", "Light Mode"]))
        appearance.addItem(
            item("Dark", #selector(ApplicationDelegate.setDarkAppearance(_:))).typeTravel(
                "darkMode", icon: "moon.stars.fill", title: "Switch to Dark Mode",
                triggers: ["Switch to Dark Mode", "Switch Dark Mode", "Dark Mode", "Night Mode"]))
        view.addItem(.separator())
        view.addItem(
            item("Refresh the Page", #selector(BrowserWindowController.reload(_:)), key: "r", id: "reloadPage")
                .typeTravel("reloadPage", icon: "arrow.clockwise", triggers: ["Reload Page"]))
        view.addItem(
            item(
                "Force Refresh the Page", #selector(BrowserWindowController.forceReload(_:)), key: "r",
                modifiers: [.command, .shift], id: "forceReloadPage"
            ).typeTravel("forceReloadPage", icon: "arrow.clockwise", triggers: ["Force Reload", "Force Refresh"]))
        view.addItem(
            item("Stop Loading", #selector(BrowserWindowController.stopLoading(_:)), key: ".", id: "stopLoading"))
        view.addItem(.separator())
        view.addItem(
            item(
                "Show/Hide Sidebar", #selector(BrowserWindowController.toggleSidebarMode(_:)), key: "s",
                id: "showSidebar", priority: .promptAfterConsumedByWebView
            ).typeTravel(
                "toggleSidebar", icon: "sidebar.left", triggers: ["Toggle Sidebar", "Show Sidebar", "Hide Sidebar"],
                bump: 0.5))
        view.addItem(
            item("Collapse Pinned Tabs", #selector(BrowserWindowController.togglePinnedSection(_:))).typeTravel(
                "collapsePinnedSection", icon: "chevron.right",
                triggers: [
                    "Collapse Pinned Tabs", "Expand Pinned Tabs", "Hide Pinned Tabs", "Show Pinned Tabs",
                    "Pinned",
                ]))
        let reveal = item(
            "Reveal Current Tab", #selector(BrowserWindowController.focusSidebar(_:)), key: " ", modifiers: .control,
            id: "focusSidebar", priority: .promptAfterConsumedByWebView
        ).typeTravel(
            "focusSidebar", icon: "sidebar.left",
            triggers: ["Show Tab in Sidebar", "Reveal in Sidebar", "Go to Current Tab"], bump: 0.5,
            allowWhenHidden: true)
        reveal.isHidden = true
        reveal.allowsKeyEquivalentWhenHidden = true
        view.addItem(reveal)
        view.addItem(
            item(
                "Show/Hide Toolbar", #selector(ApplicationDelegate.toggleToolbar(_:)), key: "d",
                modifiers: [.command, .shift], id: "toggleToolbar", priority: .promptAfterConsumedByWebView
            ).typeTravel(
                "toggleToolbar", icon: "rectangle.topthird.inset.filled",
                triggers: ["Toggle Hide Show Toolbar", "Show Toolbar", "Hide Toolbar"]))
        view.addItem(.separator())
        view.addItem(
            item(
                "Add Split View", #selector(BrowserWindowController.addSplitView(_:)), key: "=",
                modifiers: [.control, .shift], id: "addSplitView", priority: .promptAfterConsumedByWebView
            ).typeTravel(
                "addSplitView", icon: "square.split.2x1",
                triggers: ["Add Split View", "Split View", "Create Split View Pane", "New Split View", "Split"]))
        view.addItem(
            item(
                "Close this Split Pane", #selector(BrowserWindowController.closeFocusedSplitViewPanel(_:)), key: "-",
                modifiers: [.control, .shift], id: "removeSplitView", priority: .promptAfterConsumedByWebView
            ).typeTravel("removeSplitView", icon: "xmark.square", triggers: ["Close Split View"]))
        view.addItem(
            item(
                "Separate Page from Split View", #selector(BrowserWindowController.separateTabFromSplitView(_:)),
                id: "separateTabFromSplitView"
            ).typeTravel(
                "separateTabFromSplitView", icon: "scissors",
                triggers: ["Separate from split view", "separate tab"]))
        // Hidden with their keys kept, as in Arc's menu. The numbered IDs are Oa's own: Arc builds its own.
        var panes = (1...SidebarSplitViewData.maxNumberSplit).map { position in
            let pane = item(
                "Switch to Split View \(position)", #selector(BrowserWindowController.switchToSplitViewPane(_:)),
                key: "\(position)", modifiers: [.control, .shift], id: "switchToWindowPane\(position)")
            pane.tag = position
            return pane
        }
        panes.append(
            item(
                "Switch to next Split View", #selector(BrowserWindowController.switchToNextSplitViewPane(_:)),
                key: "]", modifiers: [.control, .shift], id: "switchToNextWindowPane"))
        panes.append(
            item(
                "Switch to previous Split View", #selector(BrowserWindowController.switchToPreviousSplitViewPane(_:)),
                key: "[", modifiers: [.control, .shift], id: "switchToPreviousWindowPane"))
        for pane in panes {
            pane.isHidden = true
            pane.allowsKeyEquivalentWhenHidden = true
            view.addItem(pane)
        }

        view.addItem(.separator())
        let zoomIn = #selector(BrowserWindowController.zoomIn(_:))
        let zoomOut = #selector(BrowserWindowController.zoomOut(_:))
        // The alternates are hidden with their keys kept, as in Arc's menu, which has the ⌘= one twice.
        let zoomAlternates = [
            item("Zoom In", zoomIn, key: "="), item("Zoom Out", zoomOut, key: "-", modifiers: [.command, .shift]),
        ]
        for alternate in zoomAlternates {
            alternate.isHidden = true
            alternate.allowsKeyEquivalentWhenHidden = true
        }
        view.addItem(
            item("Zoom to Actual Size", #selector(BrowserWindowController.resetZoom(_:)), key: "0", id: "resetZoom")
                .typeTravel("actualSize", icon: "magnifyingglass", triggers: ["Reset Zoom"]))
        view.addItem(
            item("Zoom In", zoomIn, key: "+", id: "zoomIn").typeTravel("zoomIn", icon: "plus.magnifyingglass"))
        view.addItem(zoomAlternates[0])
        view.addItem(
            item("Zoom Out", zoomOut, key: "-", id: "zoomOut").typeTravel("zoomOut", icon: "minus.magnifyingglass"))
        view.addItem(zoomAlternates[1])
        view.addItem(.separator())
        let developer = submenu("Developer", in: view)
        developer.addItem(
            item(
                "View Source", #selector(BrowserWindowController.viewSource(_:)), key: "u",
                modifiers: [.command, .option], id: "viewSource", priority: .promptAfterConsumedByWebView
            ).typeTravel("viewSource", icon: "curlybraces", triggers: ["View Source"]))
        let toggleDevTools = #selector(BrowserWindowController.toggleDevTools(_:))
        developer.addItem(
            item(
                "Developer Tools", toggleDevTools, key: "i", modifiers: [.command, .option], id: "developerTools",
                priority: .promptAfterConsumedByWebView
            ).typeTravel("devTools", icon: "hammer.fill", triggers: ["Developer Tools", "Debug Tools", "Devtools"]))
        // Hidden with its key kept, as in Arc's menu.
        let f12 = item(
            "Developer Tools", toggleDevTools, key: "\u{F70F}", modifiers: [], id: "developerTools_Alternate",
            priority: .promptAfterConsumedByWebView)
        f12.isHidden = true
        f12.allowsKeyEquivalentWhenHidden = true
        developer.addItem(f12)
        developer.addItem(
            item(
                "Inspect Elements", #selector(BrowserWindowController.inspectElements(_:)), key: "c",
                modifiers: [.command, .option], id: "inspectElements", priority: .promptAfterConsumedByWebView
            ).typeTravel("inspectElements", icon: "scope", triggers: ["Inspect Element"]))
        developer.addItem(
            item(
                "JavaScript Console", #selector(BrowserWindowController.javaScriptConsole(_:)), key: "j",
                modifiers: [.command, .option], id: "javaScriptConsole"
            ).typeTravel(
                "javaScriptConsole", icon: "terminal",
                triggers: ["Toggle console", "Console", "Javascript Console", "JS console"]))
        developer.addItem(
            item(
                "Network Inspector", #selector(BrowserWindowController.networkInspector(_:)), id: "networkInspector"
            ).typeTravel("networkInspector", icon: "wifi", triggers: ["Network Inspector"]))
        developer.addItem(
            item(
                "Toggle Developer Mode", #selector(BrowserWindowController.toggleDeveloperMode(_:)), key: "d",
                modifiers: [.control], id: "toggleDeveloperMode", priority: .promptAfterConsumedByWebView
            ).typeTravel("toggleDeveloperMode", icon: "hammer.fill", triggers: ["Developer Mode"]))
        view.addItem(.separator())
        view.addItem(
            item(
                "Enter/Exit Full Screen", #selector(NSWindow.toggleFullScreen(_:)), key: "f",
                modifiers: [.command, .control], id: "fullscreen", priority: .promptAfterConsumedByWebView
            ).typeTravel(
                "togglefullscreen", icon: "arrow.up.left.and.arrow.down.right",
                triggers: ["Enter Full Screen", "Exit Full Screen", "Full Screen", "Toggle Full Screen"]))

        let archive = submenu("Archive", in: menu)
        // The alternates are hidden with their keys kept and the same titles, as in Arc's menu.
        let back = #selector(BrowserWindowController.goBack(_:))
        let forward = #selector(BrowserWindowController.goForward(_:))
        let alternates = [
            item("Go Back", back, key: "\u{F702}", id: "goBack_Alternate"),
            item("Go Forward", forward, key: "\u{F703}", id: "goForward_Alternate"),
        ]
        for alternate in alternates {
            alternate.isHidden = true
            alternate.allowsKeyEquivalentWhenHidden = true
        }
        archive.addItem(
            item("Go Back", back, key: "[", id: "goBack", priority: .overrideWebView)
                .typeTravel("back", icon: "arrow.backward", triggers: ["Go Back", "Back", "Navigate Back"]))
        archive.addItem(alternates[0])
        archive.addItem(
            item("Go Forward", forward, key: "]", id: "goForward", priority: .overrideWebView)
                .typeTravel("goForward", icon: "arrow.right", triggers: ["Go Forward", "Forward", "Navigate Forward"]))
        archive.addItem(alternates[1])
        archive.addItem(.separator())
        archive.addItem(
            item("View History", #selector(BrowserWindowController.viewHistory(_:)), key: "y", id: "viewHistory")
                .typeTravel("history", icon: "book", triggers: ["Show History", "History"]))
        archive.addItem(
            item("View Archive…", #selector(BrowserWindowController.toggleArchive(_:)), id: "viewArchive")
                .typeTravel("viewArchive", icon: "archivebox", triggers: ["Archive"]))
        archive.addItem(
            item("Clear Archive", #selector(BrowserWindowController.clearArchive(_:)), id: "clearArchive")
                .typeTravel("clearArchive", icon: "archivebox", triggers: ["Clear Archive", "Delete Archive"]))

        let tabs = submenu("Tabs", in: menu)
        let next = #selector(BrowserWindowController.selectNextTab(_:))
        let previous = #selector(BrowserWindowController.selectPreviousTab(_:))
        tabs.addItem(item("Next Tab", next, key: "}", id: "nextTab").typeTravel("nextTab", icon: "arrow.right"))
        tabs.addItem(
            item(
                "Next Tab (Alternate)", next, key: "\u{F701}", modifiers: [.command, .option],
                id: "selectNextTab", priority: .overrideWebView))
        tabs.addItem(
            item("Previous Tab", previous, key: "{", id: "previousTab").typeTravel("previousTab", icon: "arrow.left"))
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
        tabs.addItem(
            item("New Folder…", #selector(BrowserWindowController.newFolder(_:)), id: "newFolder")
                .typeTravel("newFolder", icon: "folder.badge.plus", triggers: ["Create New Folder"]))
        tabs.addItem(
            item(
                "Clear Today", #selector(BrowserWindowController.clearTabs(_:)), key: "k",
                modifiers: [.command, .shift], id: "clearExplore"
            ).typeTravel(
                "clearUnpinnedTabs", icon: "bubbles.and.sparkles",
                triggers: ["Close Unpinned Tabs", "Clear Tabs", "Clear Today", "Clear Unpinned Tabs"]))
        tabs.addItem(.separator())
        tabs.addItem(
            item(
                "Expand Peek", #selector(BrowserWindowController.expandPeek(_:)), key: "o", id: "openTabIn",
                priority: .promptAfterConsumedByWebView))
        // Arc registers this one in code, with no menu item; Oa's bindings are its menu's, so a hidden item.
        let moveMenu = item(
            "Show Little Oa “Open In” Menu", #selector(BrowserWindowController.showLittleMoveMenu(_:)), key: "o",
            modifiers: [.command, .shift], id: "showLittleArcOpenInMenu")
        moveMenu.isHidden = true
        moveMenu.allowsKeyEquivalentWhenHidden = true
        tabs.addItem(moveMenu)

        let spaces = submenu("Spaces", in: menu)
        spaces.addItem(
            item("New Space…", #selector(BrowserWindowController.newSpace(_:)), id: "newSpace")
                .typeTravel("newSpace", icon: "plus.rectangle.portrait", triggers: ["Create New Space"]))
        spaces.addItem(
            item("Rename Space…", #selector(BrowserWindowController.renameSpace(_:)))
                .typeTravel("renameSpace", icon: "character.cursor.ibeam"))
        spaces.addItem(
            item("Edit Theme…", #selector(BrowserWindowController.editTheme(_:))).typeTravel(
                "editSpaceTheme", icon: "paintbrush.pointed.fill",
                triggers: ["Theme", "Edit Theme", "Edit Space Theme"]))
        spaces.addItem(
            item("Change Profile", #selector(BrowserWindowController.changeProfile(_:)))
                .typeTravel("changeProfile", icon: "person.fill"))
        spaces.addItem(item("Delete Space", #selector(BrowserWindowController.deleteSpace(_:))))
        spaces.addItem(.separator())
        spaces.addItem(
            item(
                "Next Space", #selector(BrowserWindowController.nextSpace(_:)), key: "\u{F703}",
                modifiers: [.command, .option], id: "focusNextSpace"
            ).typeTravel("nextSpace", icon: "arrow.right.to.line", triggers: ["Focus Next Space"]))
        spaces.addItem(
            item(
                "Previous Space", #selector(BrowserWindowController.previousSpace(_:)), key: "\u{F702}",
                modifiers: [.command, .option], id: "focusPreviousSpace"
            ).typeTravel("previousSpace", icon: "arrow.left.to.line", triggers: ["Focus Previous Space"]))
        let spaceItems = NSMenuItem.separator()
        spaces.addItem(spaceItems)
        spacesMainMenuProvider = SpacesMainMenuProvider(menu: spaces, after: spaceItems, store: store)

        submenu("Extensions", in: menu).delegate = extensionsMenu

        let window = submenu("Window", in: menu)
        window.addItem(
            item(
                "Minimize", #selector(NSWindow.performMiniaturize(_:)), key: "m", id: "minimize",
                priority: .overrideWebView
            ).typeTravel("minimize", icon: "arrow.down.right.and.arrow.up.left", triggers: ["Minimize Window"]))
        window.addItem(item("Zoom", #selector(NSWindow.performZoom(_:))))
        window.addItem(.separator())
        window.addItem(
            item(
                "View Library", #selector(BrowserWindowController.toggleLibrary(_:)), key: "l",
                modifiers: [.command, .shift], id: "viewLibrary"
            ).typeTravel("openLibrary", icon: "archivebox", triggers: ["Library"]))
        window.addItem(
            item(
                "View Downloads", #selector(BrowserWindowController.toggleDownloads(_:)), key: "j",
                modifiers: [.command, .shift], id: "viewDownloads"
            ).typeTravel("openDownloads", icon: "arrow.down.circle", triggers: ["Downloads"]))
        window.addItem(.separator())
        window.addItem(item("Bring All to Front", #selector(NSApplication.arrangeInFront(_:))))
        application.windowsMenu = window

        let help = submenu("Help", in: menu)
        help.addItem(
            item("Restore Data…", #selector(ApplicationDelegate.restoreData(_:)))
                .typeTravel("restoreData", icon: "opticaldiscdrive", triggers: ["Restore", "Backup"]))
        application.helpMenu = help

        application.mainMenu = menu
        keyBindingMenuManager = KeyBindingMenuManager(menu: menu, client: store.keyBindings)
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
