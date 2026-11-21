import Foundation

extension ShortcutsPane {
    /// Arc's sentences for the actions Oa has, with its words for one without.
    static func description(for identifier: String) -> String {
        let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Oa"
        let ordinals = ["first", "second", "third", "fourth", "fifth", "sixth", "seventh", "eighth"]
        if identifier.hasPrefix("item"), let position = Int(identifier.dropFirst(4)) {
            return position <= ordinals.count
                ? "Jumps to the \(ordinals[position - 1]) item in your Sidebar, starting with your Favorites at the top."
                : "Jumps to the last item at the bottom of your Sidebar."
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
        case "stopLoading": "Stops loading the current page."
        case "showSidebar": "Shows or hides your Sidebar from the left edge of your window."
        case "toggleToolbar": "Shows or hides the toolbar at the top of your window."
        case "addSplitView": "Adds a new page to your current Split View."
        case "removeSplitView": "Closes the Split View page that’s currently in focus."
        case "separateTabFromSplitView": "Separate Page from Split View."
        case "switchToWindowPane1": "Jumps to the first Split View page in your current window."
        case "switchToWindowPane2": "Jumps to the second Split View page in your current window."
        case "switchToWindowPane3": "Jumps to the third Split View page in your current window."
        case "switchToWindowPane4": "Jumps to the fourth Split View page in your current window."
        case "switchToNextWindowPane": "Jumps to the next Split View page in your current window."
        case "switchToPreviousWindowPane": "Jumps to the previous Split View page in your current window."
        case "goBack": "Goes back to the last page you visited in this tab."
        case "goForward": "Goes forward to page you had previously visited in this tab."
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
        case "minimize": "Minimizes the current window."
        case "viewDownloads": "Opens the Downloads section of your Library."
        default: "Missing shortcut description."
        }
    }
}
