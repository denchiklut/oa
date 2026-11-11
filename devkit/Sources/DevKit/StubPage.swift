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
    @ObservationIgnored private lazy var hostingView: NSView = {
        let view = StubHostingView(rootView: StubPageView(page: self))
        view.sizingOptions = []
        view.movedToWindow = { [weak self] in self?.showPendingDialog() }
        return view
    }()

    var view: NSView { hostingView }

    init(id: UUID, windowID: UUID) {
        self.id = id
        self.windowID = windowID
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

    func activate() {}

    func move(toWindow windowID: UUID) {
        guard windowID != self.windowID else { return }
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
        let opened = StubPage(id: UUID(), windowID: windowID)
        opened.load(target)
        continuation?.yield(.opened(opened, url: target, disposition: disposition))
    }

    func clickCrossOriginLink() {
        guard let url, var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
        components.host = "other." + (components.host ?? "stub")
        components.path = "/linked"
        guard let target = components.url else { return }
        guard keepsAddress else { return load(target) }
        let opened = StubPage(id: UUID(), windowID: windowID)
        opened.load(target)
        continuation?.yield(.opened(opened, url: target, disposition: .foregroundTab))
    }

    func followLink() {
        guard let url, var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
        components.path = "/followed"
        components.query = nil
        if let target = components.url { load(target) }
    }

    func crashRenderer() {
        load?.cancel()
        isLoading = false
        crash = .crashed
    }

    /// Chrome's closed-tab records, as the stub keeps them: a closed page's history; `drop()` leaves none.
    private static var records: [PageSessionID: (history: [URL], position: Int)] = [:]
    private static var lastSessionID: Int32 = 0

    func closeItself() {
        Self.lastSessionID += 1
        let sessionID = PageSessionID(rawValue: Self.lastSessionID)
        Self.records[sessionID] = (history, position)
        continuation?.yield(.closed(sessionID))
        drop()
    }

    static func restore(_ sessionID: PageSessionID, id: UUID, windowID: UUID) -> StubPage? {
        guard let record = records.removeValue(forKey: sessionID), record.history.indices.contains(record.position)
        else { return nil }
        let page = StubPage(id: id, windowID: windowID)
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
