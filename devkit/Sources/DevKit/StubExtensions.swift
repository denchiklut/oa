import AppKit
import Foundation
import Observation
import SwiftUI

/// Extensions without an engine: a small catalog the stub page installs from, one of them installed from the start.
@MainActor
@Observable
final class StubExtensions: Extensions {
    struct Entry {
        let item: BrowserExtension
        let permissions: [String]
    }

    static let catalog: [Entry] = [
        ("tabtidy", "Tab Tidy", ["Read and change all your data on all websites"]),
        ("darknotes", "Dark Notes", []),
        ("wordcount", "Word Count", ["Read your browsing history", "Display notifications"]),
        ("linkgrab", "Link Grab", ["Read and change all your data on all websites"]),
        ("colorpick", "Color Pick", []),
        ("jsonview", "JSON View", ["Read and change your data on a number of websites"]),
    ].map { Entry(item: BrowserExtension(id: $0.0, name: $0.1, version: "1.0"), permissions: $0.2) }

    private(set) var items = [StubExtensions.catalog[0].item]
    private(set) var pinned = [StubExtensions.catalog[0].item.id]

    var nextToInstall: Entry? {
        Self.catalog.first { entry in !items.contains { $0.id == entry.item.id } }
    }

    func setEnabled(_ enabled: Bool, id: BrowserExtension.ID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].isEnabled = enabled
    }

    func uninstall(_ id: BrowserExtension.ID) {
        items.removeAll { $0.id == id }
        pinned.removeAll { $0 == id }
    }

    /// Pinned, as Arc pins a new install.
    func install(_ item: BrowserExtension) {
        guard !items.contains(where: { $0.id == item.id }) else { return }
        items = (items + [item]).sorted { $0.name < $1.name }
        pinned.append(item.id)
    }

    func setPinned(_ isPinned: Bool, id: BrowserExtension.ID) {
        pinned.removeAll { $0 == id }
        if isPinned { pinned.append(id) }
    }

    static func icon(for id: String) -> NSImage? {
        URL(string: "https://\(id).stub").flatMap(StubPage.icon(for:))
    }
}

@MainActor
@Observable
final class StubBrowser: Browser {
    var extensionActions: [ExtensionAction] {
        extensions.items.filter(\.isEnabled).map { item in
            ExtensionAction(
                id: item.id, name: item.name, tooltip: item.name, icon: StubExtensions.icon(for: item.id),
                pinnedPosition: extensions.pinned.firstIndex(of: item.id))
        }
    }
    private(set) var extensionPopup: ExtensionPopup?
    let events: AsyncStream<BrowserEvent>
    @ObservationIgnored private let continuation: AsyncStream<BrowserEvent>.Continuation
    @ObservationIgnored private let extensions: StubExtensions
    @ObservationIgnored private let downloads: StubDownloads
    @ObservationIgnored private let windowID: UUID

    init(windowID: UUID, extensions: StubExtensions, downloads: StubDownloads) {
        self.windowID = windowID
        self.extensions = extensions
        self.downloads = downloads
        (events, continuation) = AsyncStream<BrowserEvent>.makeStream()
    }

    func runExtensionAction(_ id: ExtensionAction.ID) {
        guard let item = extensions.items.first(where: { $0.id == id }) else { return }
        let popup = ExtensionPopup(extensionID: id, view: NSView(), size: CGSize(width: 320, height: 200))
        let content = StubPopupView(
            name: item.name,
            grow: { [weak popup] in popup?.size.height += 80 },
            openTab: { [weak self] in self?.openTab("/popup-link", of: id) },
            close: { [weak self] in self?.closeExtensionPopup() })
        let hosted = NSHostingView(rootView: content)
        hosted.autoresizingMask = [.width, .height]
        popup.view.addSubview(hosted)
        extensionPopup = popup
    }

    func setExtensionPinned(_ pinned: Bool, id: ExtensionAction.ID) { extensions.setPinned(pinned, id: id) }

    /// A short stand-in for Chrome's extension menu.
    func showExtensionMenu(for id: ExtensionAction.ID) {
        guard let item = extensions.items.first(where: { $0.id == id }) else { return }
        let isPinned = extensions.pinned.contains(id)
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(StubMenuItem(item.name, enabled: false) {})
        menu.addItem(.separator())
        menu.addItem(
            StubMenuItem("Remove from Oa") { [weak self] in
                guard let self else { return }
                StubPage.active(in: windowID)?.askToRemove(item)
            })
        menu.addItem(
            StubMenuItem(isPinned ? "Unpin" : "Pin") { [weak self] in self?.extensions.setPinned(!isPinned, id: id) })
        menu.addItem(.separator())
        menu.addItem(StubMenuItem("Manage Extension") { [weak self] in self?.openTab("/manage", of: id) })
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    func closeExtensionPopup() { extensionPopup = nil }

    private func openTab(_ path: String, of id: String) {
        guard let url = URL(string: "https://\(id).stub\(path)") else { return }
        let page = StubPage(id: UUID(), windowID: windowID, downloads: downloads, extensions: extensions)
        page.load(url)
        continuation.yield(.opened(page, isActive: true))
    }
}

private struct StubPopupView: View {
    let name: String
    let grow: () -> Void
    let openTab: () -> Void
    let close: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Text(name).font(.system(size: 15, weight: .semibold))
            Text("Stub popup").font(.system(size: 11)).foregroundStyle(.tertiary)
            Button("Grow", action: grow)
            Button("Open a tab", action: openTab)
            Button("Close itself", action: close)
        }
        .buttonStyle(.link)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
    }
}
