import Foundation

/// Arc's `ToastType`, with the kinds Oa shows.
enum ToastType: Equatable {
    /// A shortcut the page consumed: its binding's ID, the shortcut, and its menu item's title at that moment.
    case webContentConsumedHotkey(String?, shortcut: ARCKeyboardShortcut, title: String)
    case copyTabURL(trackingRemoved: Bool, urls: [URL])
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
