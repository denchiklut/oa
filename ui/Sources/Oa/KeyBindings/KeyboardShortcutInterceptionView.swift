import AppKit

/// Arc's `KeyboardShortcutInterceptionView`, the window's content. A shortcut that overrides the page is refused
/// here without the subviews being asked, so AppKit takes it to the main menu and the page never gets the key.
final class KeyboardShortcutInterceptionView: NSView {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if let shortcut = KeyboardShortcut(event: event),
            KeyBindings.priorityToShortcuts[.overrideWebView]?.contains(shortcut) == true
        {
            return false
        }
        return super.performKeyEquivalent(with: event)
    }
}
