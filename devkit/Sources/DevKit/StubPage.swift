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

    /// The placeholder view shows wherever the app puts it, so nothing moves.
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
        if let url { title = StubPage.title(for: url) }
        isLoading = false
        loadProgress = 1
    }

    private static func title(for url: URL) -> String {
        url.host()?.replacingOccurrences(of: "www.", with: "") ?? url.absoluteString
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
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
    }
}
