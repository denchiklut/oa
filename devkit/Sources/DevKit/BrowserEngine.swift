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
    /// Closes as the user would: unload handlers run. Events end.
    func close()
    /// Ends the page without unload handlers. Events end.
    func drop()
}

public enum PageEvent: Sendable, Equatable {
    /// The engine closed the page without the app asking.
    case closed
}
