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

@MainActor @objc protocol CoreProfile: NSObjectProtocol {
    @objc(createPageInWindow:delegate:completion:)
    func createPage(
        inWindow windowIdentifier: String, delegate: CorePageDelegate?, completion: @escaping (CorePage?) -> Void)
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

@MainActor @objc protocol CorePageDelegate: NSObjectProtocol {
    @objc(pageDidChangeState:) func pageDidChangeState(_ page: CorePage)
    @objc(page:didOpenPage:targetURL:disposition:)
    func page(_ page: CorePage, didOpen openedPage: CorePage, targetURL: URL?, disposition: Int)
    @objc(pageWantsActivation:) func pageWantsActivation(_ page: CorePage)
    @objc(page:rendererGone:) func page(_ page: CorePage, rendererGone exit: Int)
    @objc(pageRendererReady:) func pageRendererReady(_ page: CorePage)
    @objc(page:didRequestDialog:) func page(_ page: CorePage, didRequestDialog dialog: CorePageDialog)
    @objc(page:didDismissDialog:) func page(_ page: CorePage, didDismissDialog dialog: CorePageDialog)
    @objc(pageDidCancelClose:) func pageDidCancelClose(_ page: CorePage)
    @objc(pageDidClose:) func pageDidClose(_ page: CorePage)
}

typealias CoreReadyCallback = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer) -> Void
typealias CoreMain =
    @convention(c) (
        Int32, UnsafeMutablePointer<UnsafePointer<CChar>?>, CoreReadyCallback, UnsafeMutableRawPointer?
    ) -> Int32
