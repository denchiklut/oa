import Foundation

/// Arc's `ToastType`, with the kinds Oa shows.
enum ToastType: Equatable {
    /// A shortcut the page consumed: its binding's ID, the shortcut, and its menu item's title at that moment.
    case webContentConsumedHotkey(String?, shortcut: ARCKeyboardShortcut, title: String)
    case copyTabURL(trackingRemoved: Bool, urls: [URL])
    /// What was done, for the toast that says ⌘Z takes it back.
    case undo(String)
    /// The restored tab and the name of the Space it went back to.
    case tabUnarchived(UUID, location: String)
    /// Arc's `MoveItemsToastType.navigateToMovedTab`: the first tab moved to a Space the window doesn't show.
    case itemsMoved(UUID)
    case zoomChanged(String)
    case portraitCapture(String)
}

/// Arc's `WindowToast`: on a page, or on the window.
struct WindowToast: Identifiable, Equatable {
    enum Location: Equatable {
        case windowContent(UUID)
        case window
    }

    let id = UUID()
    let type: ToastType
    let location: Location
}

enum ToastConstants {
    static let toastVisibilityDuration = 5.0
}
