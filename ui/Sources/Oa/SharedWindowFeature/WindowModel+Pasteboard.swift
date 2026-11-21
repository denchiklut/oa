import AppKit

extension WindowModel {
    /// As Arc's `copyCurrentURLs`: the URL of the page in front as it is now, a Peek's before its tab's, without
    /// its trackers, written as Arc's `writeURL` does, a URL and the same as text, and its toast on that page.
    func copyCurrentURLs() {
        guard let result = address?.withTrackingRemoved else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([result.url as NSURL])
        NSPasteboard.general.setString(result.url.absoluteString, forType: .string)
        present(
            .copyTabURL(trackingRemoved: result.trackingRemoved, urls: [result.url]),
            at: frontPage.map { .windowContent($0.id) } ?? .window)
    }
}
