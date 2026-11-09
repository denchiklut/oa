import AppKit
import DevKit
import Foundation
import Observation

@MainActor
@Observable
final class ChromiumPage: Page {
    let id: UUID
    private(set) var url: URL?
    private(set) var title = ""
    private(set) var isLoading = false
    private(set) var loadProgress = 0.0
    private(set) var canGoBack = false
    private(set) var canGoForward = false
    let events: AsyncStream<PageEvent>

    @ObservationIgnored private var page: CorePage?
    @ObservationIgnored private let delegate: PageDelegate
    @ObservationIgnored private let continuation: AsyncStream<PageEvent>.Continuation
    @ObservationIgnored private let hostingView = PageHostingView()

    var view: NSView { hostingView }

    init(id: UUID, page: CorePage, delegate: PageDelegate) {
        self.id = id
        self.page = page
        self.delegate = delegate
        (events, continuation) = AsyncStream<PageEvent>.makeStream()
        delegate.content = self
        page.delegate = delegate
        stateChanged()
    }

    func load(_ url: URL) { page?.load(url) }
    func goBack() { page?.goBack() }
    func goForward() { page?.goForward() }
    func reload() { page?.reload() }
    func stopLoading() { page?.stopLoading() }
    func activate() { page?.activate() }
    func move(toWindow windowID: UUID) { page?.move(toWindowIdentifier: windowID.uuidString) }

    func snapshot() async -> NSImage? {
        guard let page else { return nil }
        return await withCheckedContinuation { continuation in
            page.snapshot { continuation.resume(returning: $0) }
        }
    }

    func close() {
        page?.close()
        finish()
    }

    func drop() {
        page?.drop()
        finish()
    }

    fileprivate func stateChanged() {
        guard let page else { return }
        if let url = page.url, url != self.url { self.url = url }
        let title = page.title.isEmpty ? (url?.host() ?? "") : page.title
        if title != self.title { self.title = title }
        if page.isLoading != isLoading { isLoading = page.isLoading }
        let progress = page.isLoading ? page.loadProgress : 1
        if progress != loadProgress { loadProgress = progress }
        if page.canGoBack != canGoBack { canGoBack = page.canGoBack }
        if page.canGoForward != canGoForward { canGoForward = page.canGoForward }
        updateHostedView()
    }

    fileprivate func opened(_ page: CorePage, url: URL?, disposition: Int) {
        let opened = ChromiumPage(id: UUID(), page: page, delegate: PageDelegate())
        continuation.yield(.opened(opened, url: url, disposition: OpenDisposition(core: disposition)))
    }

    fileprivate func wantsActivation() {
        if page != nil { continuation.yield(.wantsActivation) }
    }

    fileprivate func closed() {
        guard page != nil else { return }
        continuation.yield(.closed)
        finish()
    }

    private func updateHostedView() {
        hostingView.show(page?.view)
    }

    private func finish() {
        page = nil
        continuation.finish()
        hostingView.show(nil)
    }
}

/// Holds the engine's view, which changes once the page's profile has loaded.
@MainActor
private final class PageHostingView: NSView {
    private var pageView: NSView?

    func show(_ view: NSView?) {
        guard pageView !== view else { return }
        if pageView?.superview === self { pageView?.removeFromSuperview() }
        pageView = view
        guard let view else { return }
        view.removeFromSuperview()
        view.translatesAutoresizingMaskIntoConstraints = true
        view.frame = bounds
        view.autoresizingMask = [.width, .height]
        addSubview(view)
    }
}

@MainActor
final class PageDelegate: NSObject, CorePageDelegate {
    weak var content: ChromiumPage?

    func pageDidChangeState(_ page: CorePage) { content?.stateChanged() }

    func page(_ page: CorePage, didOpen openedPage: CorePage, targetURL: URL?, disposition: Int) {
        content?.opened(openedPage, url: targetURL, disposition: disposition)
    }

    func pageWantsActivation(_ page: CorePage) { content?.wantsActivation() }

    func pageDidClose(_ page: CorePage) { content?.closed() }
}

extension OpenDisposition {
    /// `OAPageOpenDisposition` in `core/objc/OACore.h`.
    init(core: Int) {
        switch core {
        case 1: self = .backgroundTab
        case 2: self = .newWindow
        case 3: self = .popup
        default: self = .foregroundTab
        }
    }
}
