import AppKit
import Foundation
import Observation

/// The engine the app programs against. Every call happens on the main thread.
@MainActor
public protocol BrowserApplication: AnyObject {
    /// Runs the app until it quits and returns the exit code. `ready` runs once, after the engine has started and
    /// before the event loop; the app sets its delegate and opens its windows there.
    func run(ready: @escaping @MainActor () -> Void) -> Int32
    /// Finishes quitting after the app answered `applicationShouldTerminate` with `.terminateLater`.
    func terminate()
    func browserContext(id: UUID) -> any BrowserContext
    /// Binds the app's window to the pages made for its `id`, once. Call it when the window opens.
    func attachWindow(_ window: NSWindow, id: UUID)
    /// Drops the window's remaining pages. Call it when the window closes.
    func closeWindow(id: UUID)
}

/// A profile's engine side: separate cookies, storage and history.
@MainActor
public protocol BrowserContext: AnyObject {
    var id: UUID { get }
    /// A page with the app's `id` in the app's window `windowID`, in the background with nothing loaded. The app
    /// issues the first `load`. Nil when the engine can't create it.
    func makePage(id: UUID, windowID: UUID) async -> (any Page)?
}

/// One page and its history. Observable, so views that read it update as it loads.
@MainActor
public protocol Page: AnyObject, Observable {
    var id: UUID { get }
    var url: URL? { get }
    var title: String { get }
    var isLoading: Bool { get }
    var loadProgress: Double { get }
    var canGoBack: Bool { get }
    var canGoForward: Bool { get }
    /// The icon the engine's favicon driver chose for the page, nil until it has one.
    var favicon: NSImage? { get }
    var securityLevel: SecurityLevel { get }
    /// Why the renderer is gone, nil while one runs; a reload starts a new one.
    var crash: PageCrash? { get }
    /// A page that keeps its address, as a pinned tab does: a link to another host opens a new page instead of
    /// navigating this one.
    var keepsAddress: Bool { get set }
    /// Attach it only while the page is shown: a view outside a window is hidden to the engine.
    var view: NSView { get }
    var events: AsyncStream<PageEvent> { get }

    func load(_ url: URL)
    func goBack()
    func goForward()
    func reload()
    func stopLoading()
    func activate()
    /// Moves the live page into another of the app's windows. History and the engine's tab identity stay.
    func move(toWindow windowID: UUID)
    /// The page's last frame, for a window it left. Nil while it has nothing drawn.
    func snapshot() async -> NSImage?
    /// Closes as the user would: unload handlers run, and `closed` or `closeCancelled` follows.
    func close()
    /// Ends the page without unload handlers. Events end.
    func drop()
}

public enum PageEvent {
    /// The page opened another page, live in this page's window with its opener kept. The app installs it under a
    /// tab that takes its `id`, or drops it.
    case opened(any Page, url: URL?, disposition: OpenDisposition)
    /// The page asked to be shown, as `window.focus()` and a `window.open` reusing a named page do. The app selects
    /// its tab or ignores it.
    case wantsActivation
    /// The page asked for a dialog; the app shows it and answers it once.
    case dialog(PageDialog)
    /// The engine closed the dialog: a navigation, a tab switch, a close. No answer is expected.
    case dialogDismissed(PageDialog)
    /// A `beforeunload` handler kept the page after `close()`.
    case closeCancelled
    /// The page is gone, after `close()` or without the app asking.
    case closed
}

/// What a page asked with `alert`, `confirm`, `prompt` or a `beforeunload` handler.
@MainActor
public final class PageDialog {
    public enum Kind: Equatable {
        case alert
        case confirm
        case prompt(defaultText: String)
        case beforeUnload(isReload: Bool)
    }

    public let kind: Kind
    /// Chrome's line above the message: "host says", empty for `beforeUnload`.
    public let title: String
    public let message: String
    /// From the page's seventh dialog on, as Arc offers it; `suppress` answers the page's later dialogs unasked.
    public let offersSuppression: Bool
    private var reply: ((Bool, String, Bool) -> Void)?

    public init(
        kind: Kind, title: String, message: String, offersSuppression: Bool = false,
        reply: @escaping (_ accepted: Bool, _ text: String, _ suppress: Bool) -> Void
    ) {
        self.kind = kind
        self.title = title
        self.message = message
        self.offersSuppression = offersSuppression
        self.reply = reply
    }

    public func accept(text: String = "", suppress: Bool = false) {
        reply?(true, text, suppress)
        reply = nil
    }

    public func cancel(suppress: Bool = false) {
        reply?(false, "", suppress)
        reply = nil
    }
}

public enum OpenDisposition: Sendable, Equatable {
    case foregroundTab
    case backgroundTab
    case newWindow
    case popup
}

/// Why a page's renderer is gone.
public enum PageCrash: Sendable, Equatable {
    case crashed
    case killed
    case outOfMemory
}

/// Chromium's security level for the page's visible URL.
public enum SecurityLevel: Sendable, Equatable {
    case neutral
    case secure
    case warning
    case dangerous
}
