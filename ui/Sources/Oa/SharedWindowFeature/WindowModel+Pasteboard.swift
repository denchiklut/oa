import AppKit

extension WindowModel {
    func copyCapture(_ png: Data?, for pageID: UUID) {
        let copied =
            png.map {
                NSPasteboard.general.clearContents()
                return NSPasteboard.general.setData($0, forType: .png)
            } ?? false
        present(.capture(copied ? "Capture copied" : "Couldn’t copy capture"), at: .windowContent(pageID))
    }

    /// As Arc's `copyCurrentURLs`: a Peek's page first, then several selected rows together, else the page in front
    /// as it is now, without its trackers and with its toast on that page. As Markdown, as seen in Arc:
    /// `[title](URL)` as plain text alone, the title as the page has it.
    func copyCurrentURLs(asMarkdown: Bool = false) {
        let rows = peek == nil ? multiSelectedTabIDs : []
        guard rows.isEmpty else { return copyURLs(of: rows, asMarkdown: asMarkdown, toast: true) }
        let title = asMarkdown ? frontPage?.title ?? selectedTab?.title ?? "" : nil
        copy([(title, address)], toastOn: frontPage?.id)
    }

    /// A split's pane from its bar and a tab's Copy Link. As seen in Arc, a tab that isn't shown gets no toast.
    func copyURL(of tabID: UUID) {
        let shown = presentedTabIDs.contains(tabID)
        copy([(nil, liveURL(of: tabID))], toastOn: shown ? pages[tabID]?.id : nil, toast: shown)
    }

    /// As Arc's `copyItemURLs`. As seen in Arc's Copy Links: one line each in row order, as plain text, with no
    /// toast. Oa's own, as Arc's weren't seen: ⇧⌘C's toast for several sits on the page in front, and their
    /// Markdown lines are each as one page's.
    func copyURLs(of tabIDs: [UUID], asMarkdown: Bool = false, toast: Bool = false) {
        copy(
            tabIDs.map { (asMarkdown ? liveTitle(of: $0) : nil, liveURL(of: $0)) }, toastOn: frontPage?.id,
            toast: toast)
    }

    /// As Arc's writer: one URL with no title as its `writeURL` does, a URL and the same as text; a title or
    /// several make plain text, line by line.
    private func copy(_ items: [(title: String?, url: URL?)], toastOn pageID: UUID?, toast: Bool = true) {
        let items = items.compactMap { item in item.url.map { (title: item.title, result: $0.withTrackingRemoved) } }
        guard let first = items.first else { return }
        NSPasteboard.general.clearContents()
        if items.count == 1, first.title == nil {
            NSPasteboard.general.writeObjects([first.result.url as NSURL])
            NSPasteboard.general.setString(first.result.url.absoluteString, forType: .string)
        } else {
            let lines = items.map { item in
                let url = item.result.url.absoluteString
                return item.title.map { "[\($0)](\(url))" } ?? url
            }
            NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
        }
        guard toast else { return }
        present(
            .copyTabURL(trackingRemoved: items.contains { $0.result.trackingRemoved }, urls: items.map(\.result.url)),
            at: pageID.map { .windowContent($0) } ?? .window)
    }
}
