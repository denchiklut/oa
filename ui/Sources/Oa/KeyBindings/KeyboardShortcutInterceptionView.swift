import AppKit

/// Arc's `KeyboardShortcutInterceptionView`, the window's content. A shortcut that overrides the page is refused
/// here without the subviews being asked, so AppKit takes it to the main menu and the page never gets the key.
/// Which shortcuts those are follows the bindings, and is never one a user may not set.
final class KeyboardShortcutInterceptionView: NSView {
    private let keyBindings: KeyBindingsClient

    init(keyBindings: KeyBindingsClient) {
        self.keyBindings = keyBindings
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if let shortcut = ARCKeyboardShortcut(event: event),
            keyBindings.state.priorityToShortcuts[.overrideWebView]?.contains(shortcut) == true,
            !ARCKeyboardShortcut.shortcutsForbiddenForUsers.contains(shortcut)
        {
            return false
        }
        return super.performKeyEquivalent(with: event)
    }
}
