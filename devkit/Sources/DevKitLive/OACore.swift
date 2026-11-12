import AppKit

// Swift's view of OaCore's Objective-C classes (`core/objc/OACore.h`). The framework is loaded at run time, so these
// protocols name the same selectors and instances are cast with `unsafeBitCast`. Keep both sides in step.

@MainActor @objc protocol CoreEngine: NSObjectProtocol {
    @objc(profileWithIdentifier:) func profile(identifier: String) -> CoreProfile
    @objc(attachWindow:withIdentifier:) func attach(_ window: NSWindow, identifier: String)
    @objc(closeWindowWithIdentifier:) func closeWindow(identifier: String)
    @objc(askToLeaveWindowWithIdentifier:completion:) func askToLeaveWindow(
        identifier: String, completion: @escaping (Bool) -> Void)
    func quit()
}

@MainActor @objc protocol CoreSiteSetting: NSObjectProtocol {
    var type: Int { get }
    var value: Int { get }
}

@MainActor @objc protocol CoreDownload: NSObjectProtocol {
    var identifier: String { get }
    var state: Int { get }
    var receivedBytes: Int64 { get }
    var totalBytes: Int64 { get }
    var bytesPerSecond: Int64 { get }
    var remainingSeconds: Int64 { get }
    var targetFileURL: URL? { get }
    var sourceURL: URL? { get }
    var startTime: Date { get }
    var isPaused: Bool { get }
    var page: CorePage? { get }
}

@MainActor @objc protocol CoreDownloadsDelegate: NSObjectProtocol {
    /// `OADownload`s, which Swift can't check against `CoreDownload`.
    @objc(downloadsDidInitialize:) func downloadsDidInitialize(_ downloads: [NSObject])
    @objc(downloadWasCreated:) func downloadWasCreated(_ download: CoreDownload)
    @objc(downloadWasUpdated:) func downloadWasUpdated(_ download: CoreDownload)
    @objc(downloadWasRemovedWithIdentifier:) func downloadWasRemoved(identifier: String)
}

@MainActor @objc protocol CoreDownloads: NSObjectProtocol {
    var delegate: CoreDownloadsDelegate? { get set }
    @objc(pauseDownloadWithIdentifier:) func pauseDownload(identifier: String)
    @objc(resumeDownloadWithIdentifier:) func resumeDownload(identifier: String)
    @objc(cancelDownloadWithIdentifier:) func cancelDownload(identifier: String)
    @objc(removeDownloadWithIdentifier:) func removeDownload(identifier: String)
}

@MainActor @objc protocol CorePreferencesDelegate: NSObjectProtocol {
    @objc(preferencesDidChange:) func preferencesDidChange(_ preferences: CorePreferences)
}

@MainActor @objc protocol CoreSearchEngine: NSObjectProtocol {
    var name: String { get }
    var keyword: String { get }
    var url: String { get }
    var faviconURL: URL? { get }
    var isPrepopulated: Bool { get }
}

@MainActor @objc protocol CorePreferences: NSObjectProtocol {
    var delegate: CorePreferencesDelegate? { get set }
    var downloadDirectory: URL? { get set }
    var asksWhereToSaveDownloads: Bool { get set }
    /// `OASearchEngine`s, which Swift can't check against `CoreSearchEngine`.
    var searchEngines: [NSObject]? { get }
    var defaultSearchEngine: CoreSearchEngine? { get }
    var searchSuggestEnabled: Bool { get set }
    @objc(setDefaultSearchEngineWithKeyword:) func setDefaultSearchEngine(keyword: String)
}

@MainActor @objc protocol CoreAutocompleteMatch: NSObjectProtocol {
    var type: String { get }
    var contents: String { get }
    var matchDescription: String { get }
    var destinationURL: URL? { get }
    var fillIntoEdit: String { get }
    var inlineAutocompletion: String { get }
    var relevance: Int { get }
    var allowedToBeDefault: Bool { get }
    var isDeletable: Bool { get }
    var isFromPrevious: Bool { get }
    var additionalInfo: [String: String] { get }
}

@MainActor @objc protocol CoreAutocompleteResult: NSObjectProtocol {
    /// `OAAutocompleteMatch`es, which Swift can't check against `CoreAutocompleteMatch`.
    var combinedMatches: [NSObject] { get }
    var perProviderMatches: [NSObject] { get }
}

@MainActor @objc protocol CoreAutocomplete: NSObjectProtocol {
    /// `completion` gets an `OAAutocompleteResult`, which Swift can't check against `CoreAutocompleteResult`.
    @objc(startWithText:cursorPosition:preventInlineAutocomplete:startFresh:keyword:currentURL:completion:)
    func start(
        text: String, cursorPosition: UInt, preventInlineAutocomplete: Bool, startFresh: Bool, keyword: String?,
        currentURL: URL?, completion: @escaping (NSObject, Bool) -> Void)
    func stop()
    @objc(deleteMatch:) func delete(_ match: CoreAutocompleteMatch)
}

@MainActor @objc protocol CoreProfile: NSObjectProtocol {
    var downloads: CoreDownloads { get }
    var preferences: CorePreferences { get }
    /// `OASiteSetting`s, which Swift can't check against `CoreSiteSetting`.
    @objc(changedSiteSettingsForURL:) func changedSiteSettings(for url: URL) -> [NSObject]?
    @objc(setSiteSetting:to:forURL:) func setSiteSetting(_ type: Int, to value: Int, for url: URL)
    func makeAutocomplete() -> CoreAutocomplete
    @objc(createPageInWindow:restoringSessionID:delegate:completion:)
    func createPage(
        inWindow windowIdentifier: String, restoringSessionID sessionID: Int32, delegate: CorePageDelegate?,
        completion: @escaping (CorePage?, Bool) -> Void)
}

@MainActor @objc protocol CorePage: NSObjectProtocol {
    var delegate: CorePageDelegate? { get set }
    var view: NSView? { get }
    var url: URL? { get }
    var title: String { get }
    var isLoading: Bool { get }
    var loadProgress: Double { get }
    var canGoBack: Bool { get }
    var canGoForward: Bool { get }
    var favicon: NSImage? { get }
    var securityLevel: Int { get }
    var navigationResult: Int { get }
    var isCameraOn: Bool { get }
    var isMicrophoneOn: Bool { get }
    var keepsAddress: Bool { get set }
    @objc(loadURL:) func load(_ url: URL)
    func goBack()
    func goForward()
    func reload()
    func stopLoading()
    func activate()
    @objc(moveToWindowWithIdentifier:) func move(toWindowIdentifier identifier: String)
    @objc(snapshotWithCompletion:) func snapshot(completion: @escaping (NSImage?) -> Void)
    func close()
    func drop()
}

@MainActor @objc protocol CorePageDialog: NSObjectProtocol {
    var kind: Int { get }
    var title: String { get }
    var message: String { get }
    var defaultText: String { get }
    var isReload: Bool { get }
    var offersSuppression: Bool { get }
    @objc(acceptWithText:suppress:) func accept(text: String?, suppress: Bool)
    @objc(cancelWithSuppress:) func cancel(suppress: Bool)
}

@MainActor @objc protocol CorePagePermissionRequest: NSObjectProtocol {
    var nameOrOrigin: String { get }
    var nameIsOrigin: Bool { get }
    var kinds: [NSNumber] { get }
    @objc(respond:) func respond(_ response: Int)
}

@MainActor @objc protocol CorePageDelegate: NSObjectProtocol {
    @objc(pageDidChangeState:) func pageDidChangeState(_ page: CorePage)
    @objc(page:didOpenPage:targetURL:disposition:byPage:)
    func page(_ page: CorePage, didOpen openedPage: CorePage, targetURL: URL?, disposition: Int, byPage: Bool)
    @objc(pageWantsActivation:) func pageWantsActivation(_ page: CorePage)
    @objc(page:rendererGone:) func page(_ page: CorePage, rendererGone exit: Int)
    @objc(pageRendererReady:) func pageRendererReady(_ page: CorePage)
    @objc(page:didRequestDialog:) func page(_ page: CorePage, didRequestDialog dialog: CorePageDialog)
    @objc(page:didDismissDialog:) func page(_ page: CorePage, didDismissDialog dialog: CorePageDialog)
    @objc(page:didRequestPermission:)
    func page(_ page: CorePage, didRequestPermission request: CorePagePermissionRequest)
    @objc(page:didClosePermissionRequest:)
    func page(_ page: CorePage, didClosePermissionRequest request: CorePagePermissionRequest)
    @objc(pageDidCancelClose:) func pageDidCancelClose(_ page: CorePage)
    @objc(page:didCloseWithSessionID:) func page(_ page: CorePage, didCloseWithSessionID sessionID: Int32)
}

typealias CoreReadyCallback = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer) -> Void
typealias CoreMain =
    @convention(c) (
        Int32, UnsafeMutablePointer<UnsafePointer<CChar>?>, CoreReadyCallback, UnsafeMutableRawPointer?
    ) -> Int32
