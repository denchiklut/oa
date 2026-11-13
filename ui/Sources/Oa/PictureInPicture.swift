import AppKit
import DevKit

/// Arc's video picture-in-picture, one for the app as the engine shows one video at a time: the rule that asks for it
/// when a window stops presenting a playing page and ends it when one presents the page again
/// (arc-picture-in-picture-static.md §5), and the window the engine's video view goes in.
@MainActor
final class PictureInPicture {
    /// Arc's `PIPSessionState`. Oa reaches the pending, active, hidden, user-closed and failed ones so far.
    enum SessionState {
        case pendingActive, active, pendingHidden, hidden, pendingRemoved, removed
        case userRequestedClose, userRequestedMinimize, userClosed, closeFailed, requestFailed

        var isActive: Bool { self == .pendingActive || self == .active }
    }

    private struct Session {
        var state: SessionState
        var controller: PictureInPictureController?
        var videoSize: CGSize?
    }

    private let store: SidebarStore
    private let configuration = PictureInPictureConfiguration()
    private var sessions: [UUID: Session] = [:]
    private var shownPageID: UUID?
    private var changedPages: [UUID: any Page] = [:]
    private lazy var window = PictureInPictureWindow(
        onBackToTab: { [weak self] in self?.backToTab() }, onClose: { [weak self] in self?.close() })

    init(store: SidebarStore) {
        self.store = store
    }

    /// A window presents `page` or stopped presenting it. Answered once the change has settled: a page moving between
    /// windows is presented by neither for a moment.
    func presentationChanged(of page: any Page) {
        let isScheduled = !changedPages.isEmpty
        changedPages[page.id] = page
        guard !isScheduled else { return }
        Task {
            let pages = changedPages.values
            changedPages = [:]
            pages.forEach(update)
        }
    }

    func handle(_ event: PictureInPictureEvent, for pageID: UUID) {
        switch event {
        case .created(let controller):
            sessions[pageID, default: Session(state: .pendingActive)].controller = controller
        case .resolutionChanged(let size):
            sessions[pageID]?.videoSize = size
            if shownPageID == pageID { window.videoSize = size }
        case .show:
            guard let session = sessions[pageID], let controller = session.controller else { return }
            // The page was shown again while the engine was still entering, when there was nothing to exit.
            if session.state == .pendingHidden, let page = page(pageID) {
                return exit(page, pausing: false, to: .pendingHidden)
            }
            sessions[pageID]?.state = .active
            shownPageID = pageID
            window.show(controller.view, videoSize: session.videoSize)
        case .hide:
            let closedByUser = sessions[pageID]?.state == .userRequestedClose
            sessions[pageID]?.state = closedByUser ? .userClosed : .hidden
            dismiss(pageID)
        case .close:
            sessions[pageID]?.state = .removed
            dismiss(pageID)
        case .destroyed:
            sessions[pageID] = nil
            dismiss(pageID)
        }
    }

    /// As Arc's `pictureInPictureEffect`: the rule's answer against what the page has.
    private func update(_ page: any Page) {
        guard let holder = store.windows.first(where: { $0.page(id: page.id) != nil }), canAutoManage(page, in: holder)
        else { return }
        let isPresented = store.windows.contains { $0.page?.id == page.id }
        let isActive = sessions[page.id]?.state.isActive ?? false
        let shows = shouldShow(page, isPresented: isPresented, isActive: isActive)
        if shows, !isActive {
            let requested = page.mediaSession.requestPictureInPicture()
            sessions[page.id, default: Session(state: .pendingActive)].state =
                requested ? .pendingActive : .requestFailed
        } else if !shows, isActive {
            exit(page, pausing: false, to: .pendingHidden)
        }
    }

    /// Arc's `canAutoManagePictureInPicture`, in its order: the disallow list, the setting, the site's Automatic
    /// Picture-in-Picture setting. Arc leaves the page's picture-in-picture alone otherwise.
    private func canAutoManage(_ page: any Page, in window: WindowModel) -> Bool {
        if let url = page.url, configuration.disallows(url) { return false }
        if AutomaticPictureInPicture.isDisabled { return false }
        return window.siteSetting(.automaticPictureInPicture, ofPage: page.id) != .block
    }

    /// Arc's `shouldShowPictureInPicture`, in its order. Arc also refuses a muted tab; Oa has no tab muting yet.
    private func shouldShow(_ page: any Page, isPresented: Bool, isActive: Bool) -> Bool {
        if page.isCameraOn || page.isMicrophoneOn { return !isPresented }
        guard let state = page.mediaSession.state, state.status == .active else { return false }
        switch state.contentType {
        case .audioOnly: return isActive
        case .audioVideo: break
        case .videoOnly, nil: return false
        }
        if isPresented { return false }
        guard let url = page.url else { return true }
        return configuration.activatesWhenInaudible(url) || page.isAudible
    }

    /// As Arc's Back to Tab: the source tab is selected and the page plays on there.
    private func backToTab() {
        guard let pageID = shownPageID else { return }
        guard let page = page(pageID) else { return dismiss(pageID) }
        store.windows.first { $0.page(id: pageID) != nil }?.showPage(pageID)
        exit(page, pausing: false, to: .pendingHidden)
    }

    /// As Arc's Close: the video pauses, and the selection stays where it is.
    private func close() {
        guard let pageID = shownPageID else { return }
        guard let page = page(pageID) else { return dismiss(pageID) }
        exit(page, pausing: true, to: .userRequestedClose)
    }

    /// The engine's `hide` follows and takes the window down. A request the engine hasn't entered yet can't be
    /// ended; its state stays, and its `show` ends it.
    private func exit(_ page: any Page, pausing: Bool, to state: SessionState) {
        let isEntering = sessions[page.id]?.state == .pendingActive
        sessions[page.id]?.state = state
        if !page.mediaSession.exitPictureInPicture(pausing: pausing), !isEntering {
            sessions[page.id]?.state = .closeFailed
            dismiss(page.id)
        }
    }

    private func page(_ pageID: UUID) -> (any Page)? {
        store.windows.lazy.compactMap { $0.page(id: pageID) }.first
    }

    private func dismiss(_ pageID: UUID) {
        guard shownPageID == pageID else { return }
        shownPageID = nil
        window.dismiss()
    }
}

/// Arc's key, stored the same way: absent means on. Arc's switch is in Settings ▸ Advanced; Oa has none yet.
enum AutomaticPictureInPicture {
    static let key = "autoPipGloballyDisabled"

    static var isDisabled: Bool { UserDefaults.standard.bool(forKey: key) }
}

/// Arc's `WebContentBehaviorConfiguration` for picture-in-picture, in its shape and with what Arc 1.172.2 bundles.
/// Arc refreshes it from its server; Oa's is fixed. The site attributes for the window's controls come with them.
struct PictureInPictureConfiguration {
    struct SiteConfig {
        var urlRegex: String
        var customAttributes: [String]
    }

    var pipDisallowList = [
        #"^(?:https?://)?(?:www\.)?app\.slack\.(?:[-a-zA-Z0-9:.]+)"#,
        #"^(?:https?://)?(?:www\.)?meet\.google\.(?:[-a-zA-Z0-9:.]+)"#,
        #"^(?:https?://)?(?:www\.)?teams\.microsoft\.(?:[-a-zA-Z0-9:.]+)"#,
    ]
    var pipSiteConfigs = [
        SiteConfig(
            urlRegex: #"^(?:https?://)?(?:www\.)?youtube\.(?:[-a-zA-Z0-9:.]+)"#,
            customAttributes: ["activatesWhenInaudible"])
    ]

    func disallows(_ url: URL) -> Bool {
        pipDisallowList.contains { matches($0, url) }
    }

    func activatesWhenInaudible(_ url: URL) -> Bool {
        pipSiteConfigs.contains { $0.customAttributes.contains("activatesWhenInaudible") && matches($0.urlRegex, url) }
    }

    private func matches(_ regex: String, _ url: URL) -> Bool {
        url.absoluteString.range(of: regex, options: .regularExpression) != nil
    }
}
