import AppKit
import DevKit
import Foundation
import Observation

/// A window's Chromium Browser in one profile, as ADK's `ChromiumBrowser`.
@MainActor
@Observable
final class ChromiumBrowser: Browser {
    private(set) var extensionActions: [ExtensionAction] = []
    private(set) var extensionPopup: ExtensionPopup?
    let events: AsyncStream<BrowserEvent>
    @ObservationIgnored private let continuation: AsyncStream<BrowserEvent>.Continuation
    @ObservationIgnored private let delegate = BrowserDelegate()
    @ObservationIgnored private var core: CoreBrowser?

    init(profile: CoreProfile?, windowID: UUID) {
        (events, continuation) = AsyncStream<BrowserEvent>.makeStream()
        delegate.browser = self
        core = profile?.browser(inWindow: windowID.uuidString, delegate: delegate)
    }

    func runExtensionAction(_ id: ExtensionAction.ID) { core?.executeExtensionAction(id) }
    func setExtensionPinned(_ pinned: Bool, id: ExtensionAction.ID) { core?.setExtension(id, pinned: pinned) }
    func showExtensionMenu(for id: ExtensionAction.ID) { core?.showExtensionContextMenu(id) }
    func closeExtensionPopup() { core?.closeExtensionPopup() }

    fileprivate func updated(_ actions: [ExtensionAction]) {
        if actions != extensionActions { extensionActions = actions }
    }

    fileprivate func popupOpened(_ extensionID: String, view: NSView, size: CGSize) {
        extensionPopup = ExtensionPopup(extensionID: extensionID, view: view, size: size) { [weak self] in
            self?.core?.focusExtensionPopup()
        }
    }

    fileprivate func popupResized(_ size: CGSize) { extensionPopup?.size = size }
    fileprivate func popupClosed() { extensionPopup = nil }

    fileprivate func opened(_ page: CorePage, active: Bool) {
        continuation.yield(.opened(ChromiumPage(id: UUID(), page: page, delegate: PageDelegate()), isActive: active))
    }
}

@MainActor
private final class BrowserDelegate: NSObject, CoreBrowserDelegate {
    weak var browser: ChromiumBrowser?

    func browser(_ browser: CoreBrowser, didUpdateExtensionToolbarActions actions: [NSObject]) {
        self.browser?.updated(
            actions.map { object in
                let action = unsafeBitCast(object, to: CoreExtensionToolbarAction.self)
                return ExtensionAction(
                    id: action.identifier, name: action.accessibleName, tooltip: action.tooltip, icon: action.icon,
                    isEnabled: action.isEnabled, pinnedPosition: action.pinnedPosition < 0 ? nil : action.pinnedPosition
                )
            })
    }

    func browser(_ browser: CoreBrowser, didOpenExtensionPopup extensionIdentifier: String, view: NSView, size: NSSize)
    {
        self.browser?.popupOpened(extensionIdentifier, view: view, size: size)
    }

    func browser(_ browser: CoreBrowser, didResizeExtensionPopup size: NSSize) { self.browser?.popupResized(size) }
    func browserDidCloseExtensionPopup(_ browser: CoreBrowser) { self.browser?.popupClosed() }
    func browser(_ browser: CoreBrowser, didOpen page: CorePage, active: Bool) {
        self.browser?.opened(page, active: active)
    }
}
