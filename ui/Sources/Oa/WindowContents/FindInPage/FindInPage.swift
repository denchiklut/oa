import AppKit
import DevKit

/// Arc's `FindInPage`: the find bar of one shown page, kept as Arc keeps it on the page's `WindowContent`, so each
/// split pane and a Peek have their own and a hidden tab keeps its bar.
enum FindInPage {
    struct State: Equatable {
        /// As Arc, any change of the page's URL closes the bar, and a reload keeps it.
        let url: URL?
        var text: String
        var result: FindResult?
        /// As Arc's `FocusFindInPage`: the field takes the keyboard once the bar is shown.
        var focusesField = true
    }

    /// Arc's prefill limit in `beginFindInPage`.
    static let maxPrefillLength = 40
}

extension WindowModel {
    func findInPageState(of page: any Page) -> FindInPage.State? {
        findInPage[page.id].flatMap { $0.url == page.url ? $0 : nil }
    }

    /// As Arc's `beginFindInPage`: the user's selection on one line becomes the query when it is short enough,
    /// else an open bar keeps its text, and the query is searched again, which steps to the next match.
    func beginFindInPage() {
        guard let page = frontPage else { return }
        let selection = page.selectedText.replacing(/\r\n|\r|\n/, with: " ").trimmingCharacters(in: .whitespaces)
        let open = findInPageState(of: page)
        let text =
            !selection.isEmpty && selection.count <= FindInPage.maxPrefillLength ? selection : open?.text ?? ""
        findInPage[page.id] = FindInPage.State(url: page.url, text: text, result: open?.result)
        page.find(text, direction: .current, findMatch: true)
    }

    func updateFindQuery(_ text: String, on page: any Page) {
        guard var state = findInPageState(of: page) else { return }
        state.text = text
        findInPage[page.id] = state
        page.find(text, direction: .current, findMatch: true)
    }

    func findNext(forward: Bool, on page: (any Page)? = nil) {
        guard let page = page ?? frontPage, let state = findInPageState(of: page) else { return }
        page.find(state.text, direction: forward ? .forward : .backward, findMatch: true)
    }

    /// As Arc's Use Selection to Find: the selection as it is, with the keyboard left on the page.
    func useSelectionForFind() {
        guard let page = frontPage, !page.selectedText.isEmpty else { return }
        updateFindQuery(page.selectedText, on: page)
    }

    var canUseSelectionForFind: Bool {
        frontPage.map { findInPageState(of: $0) != nil && !$0.selectedText.isEmpty } ?? false
    }

    var isFindInPageVisible: Bool { frontPage.map { findInPageState(of: $0) != nil } ?? false }

    func findFieldFocused(on page: any Page) {
        findInPage[page.id]?.focusesField = false
    }

    /// Esc and ✕ give the keyboard back to the page, as in Arc; a navigation doesn't.
    func dismissFindInPage(on page: any Page, activating: Bool = true) {
        guard findInPage.removeValue(forKey: page.id) != nil else { return }
        page.stopFinding()
        if activating { page.activate() }
    }

    func found(_ result: FindResult, on pageID: UUID) {
        findInPage[pageID]?.result = result
    }
}
