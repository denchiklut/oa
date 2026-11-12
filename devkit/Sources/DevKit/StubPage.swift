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
    private(set) var navigationResult: NavigationResult?
    var securityLevel: SecurityLevel {
        switch url?.scheme {
        case "https": .secure
        case "http": .warning
        default: .neutral
        }
    }
    private(set) var crash: PageCrash?
    private(set) var isCameraOn = false
    private(set) var isMicrophoneOn = false
    var keepsAddress = false
    /// A `beforeunload` handler that wants to stay, as a page with unsaved changes.
    var asksBeforeClosing = false
    let events: AsyncStream<PageEvent>

    private var history: [URL] = []
    private var position = -1
    @ObservationIgnored private var load: Task<Void, Never>?
    @ObservationIgnored private var continuation: AsyncStream<PageEvent>.Continuation?
    @ObservationIgnored private var dialogsShown = 0
    @ObservationIgnored private var suppressesDialogs = false
    @ObservationIgnored private var pendingDialog: PageDialog?
    @ObservationIgnored private var permissionQueue: [[PermissionKind]] = []
    @ObservationIgnored private var shownPermissionRequest: PagePermissionRequest?
    @ObservationIgnored private lazy var hostingView: NSView = {
        let view = StubHostingView(rootView: StubPageView(page: self))
        view.sizingOptions = []
        view.movedToWindow = { [weak self] in self?.showPendingDialog() }
        return view
    }()

    var view: NSView { hostingView }

    @ObservationIgnored private let downloads: StubDownloads

    init(id: UUID, windowID: UUID, downloads: StubDownloads) {
        self.id = id
        self.windowID = windowID
        self.downloads = downloads
        (events, continuation) = AsyncStream<PageEvent>.makeStream()
        Self.arrive(self)
    }

    // The engine's tab strips: a page goes to the end of its window's on creation and on each move.
    private final class Arrival {
        weak var page: StubPage?
        init(_ page: StubPage) { self.page = page }
    }
    private static var arrivals: [Arrival] = []
    private var windowID: UUID

    private static func arrive(_ page: StubPage) {
        arrivals.removeAll { $0.page == nil || $0.page === page }
        arrivals.append(Arrival(page))
    }

    static func askToLeave(windowID: UUID) async -> Bool {
        for page in arrivals.compactMap(\.page) where page.windowID == windowID {
            guard await page.askToLeave() else { return false }
        }
        return true
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
        guard url != nil else { return }
        guard asksBeforeClosing else { return startLoading() }
        ask(.beforeUnload(isReload: true), title: "Reload site?") { [weak self] accepted in
            if accepted { self?.startLoading() }
        }
    }

    func stopLoading() { finishLoading() }

    /// As Chromium's tab strip: one active page per window, and only it shows its permission request.
    func activate() {
        if let previous = Self.activePages[windowID]?.page, previous !== self { previous.closePermissionRequest() }
        Self.activePages[windowID] = Arrival(self)
        showPermissionRequest()
    }

    func move(toWindow windowID: UUID) {
        guard windowID != self.windowID else { return }
        if Self.activePages[self.windowID]?.page === self { Self.activePages[self.windowID] = nil }
        closePermissionRequest()
        self.windowID = windowID
        Self.arrive(self)
    }

    func snapshot(_ completion: @escaping @MainActor (NSImage?) -> Void) {
        let view = hostingView
        guard view.bounds.width > 0, view.bounds.height > 0,
            let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)
        else { return completion(nil) }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let image = NSImage(size: view.bounds.size)
        image.addRepresentation(bitmap)
        completion(image)
    }

    private func askToLeave() async -> Bool {
        guard asksBeforeClosing else { return true }
        return await withCheckedContinuation { continuation in
            ask(.beforeUnload(isReload: false), title: "Leave site?") {
                continuation.resume(returning: $0)
            }
        }
    }

    func close() {
        guard asksBeforeClosing else { return closeItself() }
        ask(.beforeUnload(isReload: false), title: "Leave site?") { [weak self] accepted in
            if accepted { self?.closeItself() } else { self?.continuation?.yield(.closeCancelled) }
        }
    }

    func drop() {
        load?.cancel()
        if Self.activePages[windowID]?.page === self { Self.activePages[windowID] = nil }
        continuation?.finish()
        continuation = nil
        Self.arrivals.removeAll { $0.page == nil || $0.page === self }
    }

    func open(_ disposition: OpenDisposition) {
        guard let url, var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
        StubPage.openedCount += 1
        components.path = "/opened-\(StubPage.openedCount)"
        components.query = nil
        guard let target = components.url else { return }
        let opened = StubPage(id: UUID(), windowID: windowID, downloads: downloads)
        opened.load(target)
        continuation?.yield(.opened(opened, url: target, disposition: disposition))
    }

    func clickCrossOriginLink() {
        guard let url, var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
        components.host = "other." + (components.host ?? "stub")
        components.path = "/linked"
        guard let target = components.url else { return }
        guard keepsAddress else { return load(target) }
        let opened = StubPage(id: UUID(), windowID: windowID, downloads: downloads)
        opened.load(target)
        continuation?.yield(.opened(opened, url: target, disposition: .foregroundTab))
    }

    func followLink() {
        guard let url, var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
        components.path = "/followed"
        components.query = nil
        if let target = components.url { load(target) }
    }

    func download(failing: Bool = false) {
        downloads.start(from: url, pageID: id, failing: failing)
    }

    func crashRenderer() {
        load?.cancel()
        isLoading = false
        crash = .crashed
    }

    private static var records: [PageSessionID: (history: [URL], position: Int)] = [:]
    private static var lastSessionID: Int32 = 0

    func closeItself() {
        Self.lastSessionID += 1
        let sessionID = PageSessionID(rawValue: Self.lastSessionID)
        Self.records[sessionID] = (history, position)
        continuation?.yield(.closed(sessionID))
        drop()
    }

    static func restore(_ sessionID: PageSessionID, id: UUID, windowID: UUID, downloads: StubDownloads) -> StubPage? {
        guard let record = records.removeValue(forKey: sessionID), record.history.indices.contains(record.position)
        else { return nil }
        let page = StubPage(id: id, windowID: windowID, downloads: downloads)
        page.history = record.history
        page.position = record.position
        page.show(record.history[record.position])
        return page
    }

    func alert() { ask(.alert, message: "Hello from the stub page") { _ in } }

    func confirm() { ask(.confirm, message: "Leave the stub page?") { _ in } }

    func prompt() { ask(.prompt(defaultText: "default text"), message: "What is your name?") { _ in } }

    /// As Chrome and Arc: an alert from a hidden page returns at once and its panel waits for the page to be shown.
    func alertLater() {
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            self?.ask(.alert, message: "Delayed alert") { _ in }
        }
    }

    private func ask(
        _ kind: PageDialog.Kind, title: String? = nil, message: String = "Changes you made may not be saved.",
        reply: @escaping (Bool) -> Void
    ) {
        if suppressesDialogs {
            return reply(
                kind == .alert || kind == .beforeUnload(isReload: true) || kind == .beforeUnload(isReload: false))
        }
        dialogsShown += 1
        let host = url?.host().map { "\($0) says" } ?? ""
        let dialog = PageDialog(
            kind: kind, title: title ?? host, message: message,
            offersSuppression: kind != .beforeUnload(isReload: false) && kind != .beforeUnload(isReload: true)
                && dialogsShown >= 7
        ) { [weak self] accepted, _, suppress in
            if suppress { self?.suppressesDialogs = true }
            reply(accepted)
            if case .beforeUnload = kind { Self.showNextLeaveDialog(after: true) }
        }
        if case .beforeUnload = kind {
            Self.leaveDialogs.append { [weak self] in
                guard let self else { return Self.showNextLeaveDialog(after: true) }
                pendingDialog = dialog
                if hostingView.window == nil { continuation?.yield(.wantsActivation) } else { showPendingDialog() }
            }
            return Self.showNextLeaveDialog(after: false)
        }
        guard hostingView.window != nil else {
            guard kind == .alert else { return reply(false) }
            pendingDialog = dialog
            return
        }
        continuation?.yield(.dialog(dialog))
    }

    // Chromium shows `beforeunload` dialogs app-modally: one at a time across pages, each bringing its tab forward.
    private static var leaveDialogs: [() -> Void] = []
    private static var showingLeaveDialog = false

    private static func showNextLeaveDialog(after answered: Bool) {
        if answered { showingLeaveDialog = false }
        guard !showingLeaveDialog, !leaveDialogs.isEmpty else { return }
        showingLeaveDialog = true
        leaveDialogs.removeFirst()()
    }

    private func showPendingDialog() {
        guard hostingView.window != nil, let dialog = pendingDialog else { return }
        pendingDialog = nil
        continuation?.yield(.dialog(dialog))
    }

    // As Chromium's request manager: one request shown per page at a time, the rest queued; a site's answer is kept
    // in its settings, by host and across profiles.
    private static var activePages: [UUID: Arrival] = [:]
    static var siteSettings: [String: SiteSettingValue] = [:]

    private static func setting(_ kind: PermissionKind, host: String) -> SiteSettingValue? {
        kind.siteSettingType.flatMap { siteSettings["\(host) \($0)"] }
    }

    func askPermission(_ kinds: [PermissionKind]) {
        guard let host = url?.host() else { return }
        let open = kinds.filter { Self.setting($0, host: host) == nil }
        guard !open.isEmpty else { return }
        permissionQueue.append(open)
        showPermissionRequest()
    }

    func askPermissionLater(_ kinds: [PermissionKind]) {
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            self?.askPermission(kinds)
        }
    }

    private func showPermissionRequest() {
        guard shownPermissionRequest == nil, Self.activePages[windowID]?.page === self,
            let kinds = permissionQueue.first, let host = url?.host()
        else { return }
        let request = PagePermissionRequest(nameOrOrigin: host, kinds: kinds) { [weak self] response in
            self?.permissionAnswered(response, host: host, kinds: kinds)
        }
        shownPermissionRequest = request
        continuation?.yield(.permissionRequest(request))
    }

    /// As a page's `getUserMedia`: capture starts once the host may use both.
    func toggleCapture() {
        if isCameraOn || isMicrophoneOn {
            isCameraOn = false
            isMicrophoneOn = false
            return
        }
        guard let host = url?.host() else { return }
        let allowed = { (kind: PermissionKind) in Self.setting(kind, host: host) == .allow }
        guard allowed(.camera), allowed(.microphone) else {
            return askPermission([.camera, .microphone])
        }
        isCameraOn = true
        isMicrophoneOn = true
    }

    private func permissionAnswered(_ response: PermissionResponse, host: String, kinds: [PermissionKind]) {
        if response == .allow || response == .deny {
            for type in kinds.compactMap(\.siteSettingType) {
                Self.siteSettings["\(host) \(type)"] = response == .allow ? .allow : .block
            }
        }
        permissionQueue.removeFirst()
        closePermissionRequest()
        Task { [weak self] in self?.showPermissionRequest() }
    }

    /// The request stays queued and is asked again when the page is active.
    private func closePermissionRequest() {
        guard let request = shownPermissionRequest else { return }
        shownPermissionRequest = nil
        continuation?.yield(.permissionRequestClosed(request))
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
        isCameraOn = false
        isMicrophoneOn = false
        permissionQueue = []
        closePermissionRequest()
        crash = nil
        navigationResult = nil
        isLoading = true
        loadProgress = 0.1
        load = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            self?.finishLoading()
        }
    }

    /// A host ending in `.invalid` fails to load, as a site that can't be reached does.
    private func finishLoading() {
        load?.cancel()
        load = nil
        if let url {
            let failed = url.host()?.hasSuffix(".invalid") == true
            title = StubPage.title(for: url)
            favicon = failed ? nil : StubPage.icon(for: url)
            navigationResult = failed ? .failed : .loaded
        }
        isLoading = false
        loadProgress = 1
    }

    private static var openedCount = 0

    private static func title(for url: URL) -> String {
        guard let host = url.host()?.replacingOccurrences(of: "www.", with: "") else { return url.absoluteString }
        return url.path().count > 1 ? host + url.path() : host
    }

    /// None for an address without a host, as a page with no icon has in Chromium.
    private static func icon(for url: URL) -> NSImage? {
        guard let host = url.host()?.replacingOccurrences(of: "www.", with: "") else { return nil }
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

private final class StubHostingView: NSHostingView<StubPageView> {
    var movedToWindow: () -> Void = {}

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        movedToWindow()
    }
}

private struct StubPageView: View {
    weak var page: StubPage?

    var body: some View {
        VStack(spacing: 12) {
            if let page {
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
                            Button("Follow a link on this host") { page.followLink() }
                            Button("Click a link to another host") { page.clickCrossOriginLink() }
                            Button("Ask for focus in 3 s") { page.askForFocus() }
                            Button("Crash the renderer") { page.crashRenderer() }
                            Button("Close itself") { page.closeItself() }
                        }
                        HStack(spacing: 16) {
                            Button("Alert") { page.alert() }
                            Button("Confirm") { page.confirm() }
                            Button("Prompt") { page.prompt() }
                            Button("Alert in 3 s") { page.alertLater() }
                            Toggle("Ask before closing", isOn: Bindable(page).asksBeforeClosing)
                                .toggleStyle(.checkbox)
                        }
                        HStack(spacing: 16) {
                            Button("Ask for location") { page.askPermission([.geolocation]) }
                            Button("Ask for notifications") { page.askPermission([.notifications]) }
                            Button("Ask for camera and microphone") { page.askPermission([.camera, .microphone]) }
                            Button("Ask for location and notifications") {
                                page.askPermission([.geolocation])
                                page.askPermission([.notifications])
                            }
                            Button("Ask for location in 3 s") { page.askPermissionLater([.geolocation]) }
                            Button(page.isCameraOn ? "Stop capturing" : "Capture camera and microphone") {
                                page.toggleCapture()
                            }
                        }
                        HStack(spacing: 16) {
                            Button("Download a file") { page.download() }
                            Button("Download a file that fails") { page.download(failing: true) }
                        }
                    }
                    .buttonStyle(.link)
                    .font(.system(size: 12))
                    .padding(.top, 8)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
    }
}

extension PermissionKind {
    fileprivate var siteSettingType: SiteSettingType? {
        switch self {
        case .geolocation: .geolocation
        case .notifications: .notifications
        case .camera: .camera
        case .microphone: .microphone
        case .clipboard: .clipboardReadWrite
        default: nil
        }
    }
}
