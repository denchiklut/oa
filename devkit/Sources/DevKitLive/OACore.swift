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

@MainActor @objc protocol CoreExtension: NSObjectProtocol {
    var identifier: String { get }
    var name: String { get }
    var extensionDescription: String { get }
    var version: String { get }
    var isEnabled: Bool { get }
    var hasAction: Bool { get }
    var isFromWebstore: Bool { get }
}

@MainActor @objc protocol CoreExtensionsDelegate: NSObjectProtocol {
    /// `OAExtension`s, which Swift can't check against `CoreExtension`.
    @objc(extensionsDidInitialize:) func extensionsDidInitialize(_ extensions: [NSObject])
    @objc(extensionWasInstalled:) func extensionWasInstalled(_ extension: CoreExtension)
    @objc(extensionWasUninstalledWithIdentifier:) func extensionWasUninstalled(identifier: String)
    @objc(extensionWasEnabled:) func extensionWasEnabled(_ extension: CoreExtension)
    @objc(extensionWasDisabled:) func extensionWasDisabled(_ extension: CoreExtension)
}

@MainActor @objc protocol CoreExtensions: NSObjectProtocol {
    var delegate: CoreExtensionsDelegate? { get set }
    @objc(setExtensionWithIdentifier:enabled:) func setExtension(identifier: String, enabled: Bool)
    @objc(uninstallExtensionWithIdentifier:) func uninstallExtension(identifier: String)
}

@MainActor @objc protocol CoreExtensionToolbarAction: NSObjectProtocol {
    var identifier: String { get }
    var accessibleName: String { get }
    var tooltip: String { get }
    var icon: NSImage? { get }
    var isEnabled: Bool { get }
    var pinnedPosition: Int { get }
}

@MainActor @objc protocol CoreBrowserDelegate: NSObjectProtocol {
    /// `OAExtensionToolbarAction`s, which Swift can't check against `CoreExtensionToolbarAction`.
    @objc(browser:didUpdateExtensionToolbarActions:)
    func browser(_ browser: CoreBrowser, didUpdateExtensionToolbarActions actions: [NSObject])
    @objc(browser:didOpenExtensionPopup:view:size:)
    func browser(_ browser: CoreBrowser, didOpenExtensionPopup extensionIdentifier: String, view: NSView, size: NSSize)
    @objc(browser:didResizeExtensionPopup:) func browser(_ browser: CoreBrowser, didResizeExtensionPopup size: NSSize)
    @objc(browserDidCloseExtensionPopup:) func browserDidCloseExtensionPopup(_ browser: CoreBrowser)
    @objc(browser:didOpenPage:active:) func browser(_ browser: CoreBrowser, didOpen page: CorePage, active: Bool)
}

@MainActor @objc protocol CoreBrowser: NSObjectProtocol {
    @objc(executeExtensionAction:) func executeExtensionAction(_ identifier: String)
    @objc(setExtension:pinned:) func setExtension(_ identifier: String, pinned: Bool)
    @objc(showExtensionContextMenu:) func showExtensionContextMenu(_ identifier: String)
    func focusExtensionPopup()
    func closeExtensionPopup()
}

@MainActor @objc protocol CoreProfile: NSObjectProtocol {
    var downloads: CoreDownloads { get }
    var preferences: CorePreferences { get }
    var extensions: CoreExtensions { get }
    @objc(browserInWindow:delegate:)
    func browser(inWindow windowIdentifier: String, delegate: CoreBrowserDelegate) -> CoreBrowser
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

@MainActor @objc protocol CorePageExtensionRequest: NSObjectProtocol {
    var kind: Int { get }
    var extensionIdentifier: String { get }
    var name: String { get }
    var icon: NSImage? { get }
    var permissions: [String] { get }
    @objc(respond:) func respond(_ accepted: Bool)
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
    @objc(page:didRequestExtension:)
    func page(_ page: CorePage, didRequestExtension request: CorePageExtensionRequest)
    @objc(page:didCloseExtensionRequest:)
    func page(_ page: CorePage, didCloseExtensionRequest request: CorePageExtensionRequest)
    @objc(pageDidCancelClose:) func pageDidCancelClose(_ page: CorePage)
    @objc(page:didCloseWithSessionID:) func page(_ page: CorePage, didCloseWithSessionID sessionID: Int32)
}

typealias CoreReadyCallback = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer) -> Void
typealias CoreMain =
    @convention(c) (
        Int32, UnsafeMutablePointer<UnsafePointer<CChar>?>, CoreReadyCallback, UnsafeMutableRawPointer?
    ) -> Int32
