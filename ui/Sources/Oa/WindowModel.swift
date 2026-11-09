import DevKit
import Foundation
import Observation

@MainActor
@Observable
final class WindowModel {
    private(set) var page: (any Page)?
    var focusAddressField = 0
    @ObservationIgnored private let windowID: UUID
    @ObservationIgnored private let context: any BrowserContext
    @ObservationIgnored private var events: Task<Void, Never>?
    @ObservationIgnored private var pendingPageID: UUID?

    init(windowID: UUID, context: any BrowserContext) {
        self.windowID = windowID
        self.context = context
    }

    func openPage(_ url: URL) {
        dropPage()
        let id = UUID()
        pendingPageID = id
        Task { [weak self] in
            guard let page = await self?.context.makePage(id: id, windowID: self?.windowID ?? UUID()),
                let self, pendingPageID == id
            else { return }
            pendingPageID = nil
            self.page = page
            page.load(url)
            page.activate()
            events = Task { [weak self] in
                for await event in page.events {
                    if event == .closed { self?.pageEnded(page) }
                }
            }
        }
    }

    /// Typed input: a URL as typed, a host, or a search. Search fallback is a product decision for slice 1.
    func navigate(to input: String) {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let url: URL
        if let typed = URL(string: text), typed.scheme != nil, typed.host() != nil || typed.scheme == "file" {
            url = typed
        } else if !text.contains(" "), text.contains("."), let host = URL(string: "https://\(text)") {
            url = host
        } else {
            var components = URLComponents(string: "https://www.google.com/search")!
            components.queryItems = [URLQueryItem(name: "q", value: text)]
            url = components.url!
        }
        if let page { page.load(url) } else { openPage(url) }
    }

    func closePage() {
        pendingPageID = nil
        page?.close()
        page = nil
        events?.cancel()
    }

    func dropPage() {
        pendingPageID = nil
        page?.drop()
        page = nil
        events?.cancel()
    }

    private func pageEnded(_ ended: any Page) {
        if page === ended { page = nil }
    }
}
