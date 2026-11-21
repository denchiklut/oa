import AppKit

extension WindowModel {
    /// As Arc's `copyCurrentURLs`: the URL of the page in front as it is now, a Peek's before its tab's, without
    /// its trackers, written as Arc's `writeURL` does, a URL and the same as text, and its toast on that page.
    func copyCurrentURLs() {
        copy(address, toastOn: frontPage?.id)
    }

    /// A split's pane copies its own page's URL from its bar.
    func copyURL(of tabID: UUID) {
        copy(pages[tabID]?.url ?? state.tree.tab(tabID)?.url, toastOn: pages[tabID]?.id)
    }

    private func copy(_ url: URL?, toastOn pageID: UUID?) {
        guard let result = url?.withTrackingRemoved else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([result.url as NSURL])
        NSPasteboard.general.setString(result.url.absoluteString, forType: .string)
        present(
            .copyTabURL(trackingRemoved: result.trackingRemoved, urls: [result.url]),
            at: pageID.map { .windowContent($0) } ?? .window)
    }
}
