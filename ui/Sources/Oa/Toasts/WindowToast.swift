import Foundation

/// Arc's `ToastType`, with the one kind Oa shows.
enum ToastType: Equatable {
    /// A shortcut the page consumed: its binding's ID, the shortcut, and its menu item's title at that moment.
    case webContentConsumedHotkey(String?, shortcut: ARCKeyboardShortcut, title: String)
}

/// Arc's `WindowToast`, on the page it belongs to.
struct WindowToast: Identifiable, Equatable {
    let id = UUID()
    let type: ToastType
    let pageID: UUID
}

enum ToastConstants {
    static let toastVisibilityDuration = 5.0
}
