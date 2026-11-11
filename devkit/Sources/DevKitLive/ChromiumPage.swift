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
    private(set) var favicon: NSImage?
    private(set) var securityLevel = SecurityLevel.neutral
    private(set) var navigationResult: NavigationResult?
    private(set) var isCameraOn = false
    private(set) var isMicrophoneOn = false
    private(set) var crash: PageCrash?
    var keepsAddress = false {
        didSet { page?.keepsAddress = keepsAddress }
    }
    let events: AsyncStream<PageEvent>

    @ObservationIgnored private var page: CorePage?
    @ObservationIgnored private let delegate: PageDelegate
    @ObservationIgnored private let continuation: AsyncStream<PageEvent>.Continuation
    @ObservationIgnored private let hostingView = PageHostingView()
    @ObservationIgnored private var dialogs: [ObjectIdentifier: PageDialog] = [:]
    @ObservationIgnored private var permissionRequests: [ObjectIdentifier: PagePermissionRequest] = [:]

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

    /// Core answers on the main thread.
    func snapshot(_ completion: @escaping @MainActor (NSImage?) -> Void) {
        guard let page else { return completion(nil) }
        page.snapshot { image in MainActor.assumeIsolated { completion(image) } }
    }

    func close() { page?.close() }

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
        let favicon = page.favicon
        if favicon !== self.favicon { self.favicon = favicon }
        let level = SecurityLevel(core: page.securityLevel)
        if level != securityLevel { securityLevel = level }
        let result = NavigationResult(core: page.navigationResult)
        if result != navigationResult { navigationResult = result }
        if page.isCameraOn != isCameraOn { isCameraOn = page.isCameraOn }
        if page.isMicrophoneOn != isMicrophoneOn { isMicrophoneOn = page.isMicrophoneOn }
        updateHostedView()
    }

    fileprivate func opened(_ page: CorePage, url: URL?, disposition: Int) {
        let opened = ChromiumPage(id: UUID(), page: page, delegate: PageDelegate())
        continuation.yield(.opened(opened, url: url, disposition: OpenDisposition(core: disposition)))
    }

    fileprivate func wantsActivation() {
        if page != nil { continuation.yield(.wantsActivation) }
    }

    fileprivate func rendererGone(_ exit: Int) {
        if let crash = PageCrash(rendererExit: exit), crash != self.crash { self.crash = crash }
    }

    fileprivate func rendererReady() {
        if crash != nil { crash = nil }
    }

    fileprivate func dialogRequested(_ core: CorePageDialog) {
        let dialog = PageDialog(
            kind: .init(core: core), title: core.title, message: core.message,
            offersSuppression: core.offersSuppression
        ) { [weak self] accepted, text, suppress in
            self?.dialogs.removeValue(forKey: ObjectIdentifier(core))
            accepted ? core.accept(text: text, suppress: suppress) : core.cancel(suppress: suppress)
        }
        dialogs[ObjectIdentifier(core)] = dialog
        continuation.yield(.dialog(dialog))
    }

    fileprivate func dialogDismissed(_ core: CorePageDialog) {
        if let dialog = dialogs.removeValue(forKey: ObjectIdentifier(core)) {
            continuation.yield(.dialogDismissed(dialog))
        }
    }

    fileprivate func permissionRequested(_ core: CorePagePermissionRequest) {
        let request = PagePermissionRequest(
            nameOrOrigin: core.nameOrOrigin, nameIsOrigin: core.nameIsOrigin,
            kinds: core.kinds.compactMap { PermissionKind(core: $0.intValue) }
        ) { core.respond($0.core) }
        permissionRequests[ObjectIdentifier(core)] = request
        continuation.yield(.permissionRequest(request))
    }

    fileprivate func permissionRequestClosed(_ core: CorePagePermissionRequest) {
        if let request = permissionRequests.removeValue(forKey: ObjectIdentifier(core)) {
            continuation.yield(.permissionRequestClosed(request))
        }
    }

    fileprivate func closeCancelled() {
        if page != nil { continuation.yield(.closeCancelled) }
    }

    fileprivate func closed(_ sessionID: PageSessionID?) {
        guard page != nil else { return }
        continuation.yield(.closed(sessionID))
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

    func page(_ page: CorePage, rendererGone exit: Int) { content?.rendererGone(exit) }

    func pageRendererReady(_ page: CorePage) { content?.rendererReady() }

    func page(_ page: CorePage, didRequestDialog dialog: CorePageDialog) { content?.dialogRequested(dialog) }

    func page(_ page: CorePage, didDismissDialog dialog: CorePageDialog) { content?.dialogDismissed(dialog) }

    func page(_ page: CorePage, didRequestPermission request: CorePagePermissionRequest) {
        content?.permissionRequested(request)
    }

    func page(_ page: CorePage, didClosePermissionRequest request: CorePagePermissionRequest) {
        content?.permissionRequestClosed(request)
    }

    func pageDidCancelClose(_ page: CorePage) { content?.closeCancelled() }

    func page(_ page: CorePage, didCloseWithSessionID sessionID: Int32) {
        content?.closed(sessionID < 0 ? nil : PageSessionID(rawValue: sessionID))
    }
}

extension SecurityLevel {
    /// `OAPageSecurityLevel` in `core/objc/OACore.h`.
    init(core: Int) {
        switch core {
        case 1: self = .secure
        case 2: self = .warning
        case 3: self = .dangerous
        default: self = .neutral
        }
    }
}

extension NavigationResult {
    /// `OAPageNavigationResult` in `core/objc/OACore.h`.
    init?(core: Int) {
        switch core {
        case 1: self = .loaded
        case 2: self = .failed
        default: return nil
        }
    }
}

extension PageCrash {
    /// `OAPageRendererExit` in `core/objc/OACore.h`. Nil for the exits Arc shows no crashed page for: normal, still
    /// running, launch failed. Evicted for memory reads as out of memory, Oa's own choice.
    init?(rendererExit: Int) {
        switch rendererExit {
        case 1, 3: self = .crashed
        case 2: self = .killed
        case 6, 7: self = .outOfMemory
        default: return nil
        }
    }
}

extension PageDialog.Kind {
    /// `OAPageDialogKind` in `core/objc/OACore.h`.
    @MainActor init(core: CorePageDialog) {
        switch core.kind {
        case 1: self = .confirm
        case 2: self = .prompt(defaultText: core.defaultText)
        case 3: self = .beforeUnload(isReload: core.isReload)
        default: self = .alert
        }
    }
}

extension PermissionKind {
    /// `oa::PermissionKind` in `core/public/page.h`.
    init?(core: Int) {
        let kinds: [PermissionKind] = [
            .ambientLogin, .ar, .cameraPanTiltZoom, .camera, .capturedSurfaceControl, .clipboard,
            .topLevelStorageAccess, .quota, .fileSystemAccess, .geolocation, .handTracking, .identityProvider,
            .idleDetection, .localFonts, .localNetwork, .loopbackNetwork, .microphone, .midiSysex, .multipleDownloads,
            .notifications, .keyboardLock, .pointerLock, .protocolHandler, .sensors, .storageAccess, .vr,
            .webAppInstallation, .windowManagement,
        ]
        guard kinds.indices.contains(core) else { return nil }
        self = kinds[core]
    }
}

extension PermissionResponse {
    /// `OAPagePermissionResponse` in `core/objc/OACore.h`.
    var core: Int {
        switch self {
        case .allow: 0
        case .allowThisTime: 1
        case .deny: 2
        case .dismiss: 3
        }
    }
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
