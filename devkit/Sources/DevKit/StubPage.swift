import AppKit
import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class StubPage: Page {
    let id: UUID
    private(set) var url: URL?
    private(set) var title = ""
    private(set) var isLoading = false
    private(set) var loadProgress = 1.0
    var canGoBack: Bool { position > 0 }
    var canGoForward: Bool { position < history.count - 1 }
    private(set) var favicon: NSImage?
    var securityLevel: SecurityLevel {
        switch url?.scheme {
        case "https": .secure
        case "http": .warning
        default: .neutral
        }
    }
    var keepsAddress = false
    let events: AsyncStream<PageEvent>

    private var history: [URL] = []
    private var position = -1
    @ObservationIgnored private var load: Task<Void, Never>?
    @ObservationIgnored private var continuation: AsyncStream<PageEvent>.Continuation?
    @ObservationIgnored private lazy var hostingView: NSView = {
        let view = NSHostingView(rootView: StubPageView(page: self))
        view.sizingOptions = []
        return view
    }()

    var view: NSView { hostingView }

    init(id: UUID) {
        self.id = id
        (events, continuation) = AsyncStream<PageEvent>.makeStream()
    }

    func load(_ url: URL) {
        if position + 1 <= history.count { history.removeSubrange((position + 1)...) }
        history.append(url)
        position = history.count - 1
        show(url)
    }

    func goBack() {
        guard canGoBack else { return }
        position -= 1
        show(history[position])
    }

    func goForward() {
        guard canGoForward else { return }
        position += 1
        show(history[position])
    }

    func reload() {
        if url != nil { startLoading() }
    }

    func stopLoading() { finishLoading() }

    func activate() {}

    func move(toWindow windowID: UUID) {}

    func snapshot() async -> NSImage? {
        let view = hostingView
        guard view.bounds.width > 0, view.bounds.height > 0,
            let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)
        else { return nil }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let image = NSImage(size: view.bounds.size)
        image.addRepresentation(bitmap)
        return image
    }

    func close() { drop() }

    func drop() {
        load?.cancel()
        continuation?.finish()
        continuation = nil
    }

    func open(_ disposition: OpenDisposition) {
        guard let url, var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
        StubPage.openedCount += 1
        components.path = "/opened-\(StubPage.openedCount)"
        components.query = nil
        guard let target = components.url else { return }
        let opened = StubPage(id: UUID())
        opened.load(target)
        continuation?.yield(.opened(opened, url: target, disposition: disposition))
    }

    func clickCrossOriginLink() {
        guard let url, var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
        components.host = "other." + (components.host ?? "stub")
        components.path = "/linked"
        guard let target = components.url else { return }
        guard keepsAddress else { return load(target) }
        let opened = StubPage(id: UUID())
        opened.load(target)
        continuation?.yield(.opened(opened, url: target, disposition: .foregroundTab))
    }

    func closeItself() {
        continuation?.yield(.closed)
        drop()
    }

    func askForFocus() {
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            self?.continuation?.yield(.wantsActivation)
        }
    }

    private func show(_ url: URL) {
        self.url = url
        startLoading()
    }

    private func startLoading() {
        load?.cancel()
        isLoading = true
        loadProgress = 0.1
        load = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            self?.finishLoading()
        }
    }

    private func finishLoading() {
        load?.cancel()
        load = nil
        if let url {
            title = StubPage.title(for: url)
            favicon = StubPage.icon(for: url)
        }
        isLoading = false
        loadProgress = 1
    }

    private static var openedCount = 0

    private static func title(for url: URL) -> String {
        guard let host = url.host()?.replacingOccurrences(of: "www.", with: "") else { return url.absoluteString }
        return url.path().count > 1 ? host + url.path() : host
    }

    private static func icon(for url: URL) -> NSImage {
        let host = url.host()?.replacingOccurrences(of: "www.", with: "") ?? "?"
        let hue = Double(host.unicodeScalars.reduce(0) { ($0 * 31 + Int($1.value)) % 360 }) / 360
        let letter = String(host.prefix(1)).uppercased()
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 10), .foregroundColor: NSColor.white,
        ]
        return NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
            NSColor(hue: hue, saturation: 0.5, brightness: 0.7, alpha: 1).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3).fill()
            let size = letter.size(withAttributes: attributes)
            letter.draw(
                at: NSPoint(x: (rect.width - size.width) / 2, y: (rect.height - size.height) / 2),
                withAttributes: attributes)
            return true
        }
    }
}

private struct StubPageView: View {
    let page: StubPage

    var body: some View {
        VStack(spacing: 12) {
            Text(page.title)
                .font(.system(size: 24, weight: .medium, design: .rounded))
            Text(page.url?.absoluteString ?? "")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            Text("Stub engine")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            if page.url != nil {
                VStack(spacing: 8) {
                    HStack(spacing: 16) {
                        Button("Open a page") { page.open(.foregroundTab) }
                        Button("Open in background") { page.open(.backgroundTab) }
                        Button("Shift-click a link") { page.open(.newWindow) }
                    }
                    HStack(spacing: 16) {
                        Button("Click a link to another host") { page.clickCrossOriginLink() }
                        Button("Ask for focus in 3 s") { page.askForFocus() }
                        Button("Close itself") { page.closeItself() }
                    }
                }
                .buttonStyle(.link)
                .font(.system(size: 12))
                .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
    }
}
