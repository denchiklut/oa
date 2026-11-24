import Foundation

extension ShortcutsPane {
    /// As Arc's rows, by name, then by ID where Arc's order of two same-named rows isn't stable.
    static func rowOrder(_ first: KeyBinding, _ second: KeyBinding) -> Bool {
        (first.action.name, first.id) < (second.action.name, second.id)
    }

    /// As Arc's row names, by ID: a Space's binding reads as going to it, and a row named as the one before it is an
    /// alternate.
    static func rowNames(for bindings: some Collection<KeyBinding>) -> [String: String] {
        var names: [String: String] = [:]
        var previous: String?
        for binding in bindings.sorted(by: rowOrder) {
            let name =
                SpacesMainMenuProvider.position(of: binding.id) != nil
                ? "Go to “\(binding.action.name)”" : binding.action.name
            names[binding.id] = name == previous ? "\(name) (Alternate)" : name
            previous = name
        }
        return names
    }

    /// Arc's sentences for the actions Oa has, with its words for one without.
    static func description(for identifier: String) -> String {
        let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Oa"
        let ordinals = ["first", "second", "third", "fourth", "fifth", "sixth", "seventh", "eighth"]
        if identifier.hasPrefix("item"), let position = Int(identifier.dropFirst(4)) {
            return position <= ordinals.count
                ? "Jumps to the \(ordinals[position - 1]) item in your Sidebar, starting with your Favorites at the top."
                : "Jumps to the last item at the bottom of your Sidebar."
        }
        if let position = SpacesMainMenuProvider.position(of: identifier) {
            let ordinal = NumberFormatter.localizedString(from: position as NSNumber, number: .ordinal)
            return "Jumps over to your \(ordinal) Space without needing to swipe."
        }
        return switch identifier {
        case "viewPreferences":
            "Opens \(name) preferences, where you can dial your experience down to the last check box."
        case "hideArc": "Quickly minimize all \(name) windows."
        case "hideOthers": "Quickly minimize all windows from other apps."
        case "newWindow": "Creates a new window, blank window, or incognito window."
        case "newTab": "Creates a new tab."
        case "addressBar":
            "Opens the Command Bar to search the web, navigate to recent tabs, launch an extension, and more."
        case "pinTab": "Adds or removes the current tab from the pinned section of your Sidebar."
        case "archiveTab": "Closes the tab or window that’s in focus."
        case "reopenLastClosedTab": "Reopens the most recently closed tab."
        case "reloadPage": "Refreshes the current page."
        case "forceReloadPage": "Refreshes the page and clears any local caching."
        case "printPage": "Prints the current page, or save it as a PDF."
        case "savePageAs": "Save the current page’s HTML, CSS, images, etc."
        case "stopLoading": "Stops loading the current page."
        case "resetZoom": "Zoom to actual page size."
        case "zoomIn": "Increases the magnification of the current website."
        case "zoomOut": "Decreases the magnification of the current website."
        case "viewSource": "Opens the page’s source in a new tab."
        case "showSidebar": "Shows or hides your Sidebar from the left edge of your window."
        case "toggleToolbar": "Shows or hides the toolbar at the top of your window."
        case "fullscreen": "Makes your current \(name) window fill the entire screen."
        case "copyCurrentURLMarkdown":
            """
            Copies the current URL to your clipboard without any trackers as a markdown string.
            i.e. [Page Title](www.arc.net).
            """
        case "find": "Opens a search box to find words on the current page."
        case "findAndReplace": "Finds text on a page with the option to replace it."
        case "findNext": "Jumps to the next time your search query appears on the page."
        case "findPrevious": "Jumps to the previous time your search query appears on the page."
        case "useSelectionForFind": "Opens a search box to find the words you’ve highlighted on the current page."
        case "pasteAndMatchStyle": "Pastes the selected text and matches the current text styling."
        case "addSplitView": "Adds a new page to your current Split View."
        case "removeSplitView": "Closes the Split View page that’s currently in focus."
        case "separateTabFromSplitView": "Separate Page from Split View."
        case "switchToWindowPane1": "Jumps to the first Split View page in your current window."
        case "switchToWindowPane2": "Jumps to the second Split View page in your current window."
        case "switchToWindowPane3": "Jumps to the third Split View page in your current window."
        case "switchToWindowPane4": "Jumps to the fourth Split View page in your current window."
        case "switchToNextWindowPane": "Jumps to the next Split View page in your current window."
        case "switchToPreviousWindowPane": "Jumps to the previous Split View page in your current window."
        case "goBack", "goBack_Alternate": "Goes back to the last page you visited in this tab."
        case "goForward", "goForward_Alternate": "Goes forward to page you had previously visited in this tab."
        case "focusSidebar": "Reveals the current tab in your Sidebar."
        case "viewHistory": "Opens your History in a new Today tab."
        case "viewArchive": "Opens the Archive, where all your closed tabs live."
        case "clearArchive": "Clears all tabs in the Archive."
        case "nextTab", "selectNextTab": "Jumps to the next tab in your Sidebar."
        case "previousTab", "selectPreviousTab": "Jumps to the previous tab in your Sidebar."
        case ModalItemSwitcher.cycleNextTabID:
            "Opens the tab switcher, where you can cycle through recent tabs — like Command+Tab on your computer!"
        case ModalItemSwitcher.cyclePreviousTabID:
            """
            Cycles backwards through your most recent tabs for quick access, like how Command+Tab works on your \
            computer!
            """
        case "clearExplore": "Moves all your unpinned tabs to the Archive."
        // Oa's own words: Arc's are about Little Arc, which this action also serves there.
        case "openTabIn": "Opens the Peek that’s in focus as a tab."
        case "newSpace": "Creates a new Space — for your work tabs, personal tabs, or otherwise."
        case "focusNextSpace": "Slides to the next Space in your Sidebar."
        case "focusPreviousSpace": "Slides to the previous Space in your Sidebar."
        case "minimize": "Minimizes the current window."
        case "viewDownloads": "Opens the Downloads section of your Library."
        case "viewLibrary":
            """
            Opens your Library, which is like your Camera Roll within \(name). Screenshots, Captures, Downloads, and \
            more can appear here.
            """
        default: "Missing shortcut description."
        }
    }
}
