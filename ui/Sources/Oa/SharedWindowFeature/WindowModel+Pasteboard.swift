import AppKit

extension WindowModel {
    /// As Arc's `copyCurrentURLs`: the URL of the page in front as it is now, a Peek's before its tab's, written as
    /// Arc's `writeURL` does, a URL and the same as text, and its toast on that page.
    func copyCurrentURLs() {
        guard let url = address else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([url as NSURL])
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
        present(
            .copyTabURL(trackingRemoved: false, urls: [url]), at: frontPage.map { .windowContent($0.id) } ?? .window)
    }
}
