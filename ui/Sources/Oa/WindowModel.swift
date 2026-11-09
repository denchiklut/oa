import DevKit
import Foundation
import Observation

@MainActor
@Observable
final class WindowModel {
    private(set) var tabs: [Tab] = []
    private(set) var selectedTab: Tab?
    var focusAddressField = 0
    @ObservationIgnored private let windowID: UUID
    @ObservationIgnored private let context: any BrowserContext
    @ObservationIgnored private var previouslySelected: [UUID] = []
    @ObservationIgnored private var events: [UUID: Task<Void, Never>] = [:]

    var page: (any Page)? { selectedTab?.page }

    init(windowID: UUID, context: any BrowserContext) {
        self.windowID = windowID
        self.context = context
    }

    @discardableResult
    func newTab(_ url: URL? = nil) -> Tab {
        let tab = Tab()
        tab.pendingURL = url
        tabs.append(tab)
        select(tab)
        Task { [weak self, windowID] in
            guard let page = await self?.context.makePage(id: tab.id, windowID: windowID), let self else { return }
            guard tabs.contains(where: { $0 === tab }) else { return page.drop() }
            tab.page = page
            if let url = tab.pendingURL {
                tab.pendingURL = nil
                page.load(url)
            }
            events[tab.id] = Task { [weak self] in
                for await event in page.events where event == .closed { self?.pageEnded(tab) }
            }
        }
        return tab
    }

    func select(_ tab: Tab) {
        guard tabs.contains(where: { $0 === tab }), selectedTab !== tab else { return }
        if let selectedTab {
            previouslySelected.removeAll { $0 == selectedTab.id }
            previouslySelected.append(selectedTab.id)
        }
        previouslySelected.removeAll { $0 == tab.id }
        selectedTab = tab
    }

    /// Wraps at either end. With no selection, forward selects the first tab and backward the last.
    func selectAdjacentTab(_ offset: Int) {
        guard let last = tabs.indices.last else { return }
        guard let selectedTab, let index = tabs.firstIndex(where: { $0 === selectedTab }) else {
            return select(tabs[offset > 0 ? 0 : last])
        }
        select(tabs[(index + offset + tabs.count) % tabs.count])
    }

    func selectTab(at index: Int) {
        if tabs.indices.contains(index) { select(tabs[index]) }
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
        if let page {
            page.load(url)
            page.activate()
        } else if let selectedTab {
            selectedTab.pendingURL = url
        } else {
            newTab(url)
        }
    }

    /// Closes as the user would. The window goes back to the tab it showed before, else the tab above, else below.
    func close(_ tab: Tab) {
        remove(tab)
        tab.page?.close()
        tab.page = nil
    }

    func closeAll() {
        tabs.forEach(close)
    }

    func dropAll() {
        events.values.forEach { $0.cancel() }
        events = [:]
        for tab in tabs {
            tab.page?.drop()
            tab.page = nil
        }
        tabs = []
        selectedTab = nil
        previouslySelected = []
    }

    private func remove(_ tab: Tab) {
        guard let index = tabs.firstIndex(where: { $0 === tab }) else { return }
        tabs.remove(at: index)
        previouslySelected.removeAll { $0 == tab.id }
        events.removeValue(forKey: tab.id)?.cancel()
        guard selectedTab === tab else { return }
        selectedTab = nil
        let previous = previouslySelected.last.flatMap { id in tabs.first { $0.id == id } }
        if let next = previous ?? (index > 0 ? tabs[index - 1] : tabs.first) { select(next) }
    }

    private func pageEnded(_ tab: Tab) {
        remove(tab)
        tab.page = nil
    }
}
