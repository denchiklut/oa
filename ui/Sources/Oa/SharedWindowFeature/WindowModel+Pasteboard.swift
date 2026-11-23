import AppKit

extension WindowModel {
    /// As Arc's `copyCurrentURLs`: the URL of the page in front as it is now, a Peek's before its tab's, without
    /// its trackers, written as Arc's `writeURL` does, a URL and the same as text, and its toast on that page.
    func copyCurrentURLs() {
        copy(address, toastOn: frontPage?.id)
    }

    /// A split's pane from its bar and a tab's Copy Link. As seen in Arc, a tab that isn't shown gets no toast.
    func copyURL(of tabID: UUID) {
        let shown = presentedTabIDs.contains(tabID)
        copy(liveURL(of: tabID), toastOn: shown ? pages[tabID]?.id : nil, toast: shown)
    }

    private func copy(_ url: URL?, toastOn pageID: UUID?, toast: Bool = true) {
        guard let result = url?.withTrackingRemoved else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([result.url as NSURL])
        NSPasteboard.general.setString(result.url.absoluteString, forType: .string)
        guard toast else { return }
        present(
            .copyTabURL(trackingRemoved: result.trackingRemoved, urls: [result.url]),
            at: pageID.map { .windowContent($0) } ?? .window)
    }
}
