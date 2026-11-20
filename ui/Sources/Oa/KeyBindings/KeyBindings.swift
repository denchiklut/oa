import AppKit

/// Arc's `arcKeyBindingPriority`, which its main menu's items carry: who gets a shortcut while a page has the
/// keyboard.
enum KeyBindingPriority {
    /// The page, and the menu what the page leaves.
    case low
    /// The page, and Arc prompts when the page consumed it. The prompt isn't built, so as `low` here.
    case promptAfterConsumedByWebView
    /// The menu, and never the page.
    case overrideWebView
}

/// Arc's `ARCKeyboardShortcut` as it reads one from an event: the key in lower case and the four modifiers.
struct KeyboardShortcut: Hashable {
    private static let modifierMask: NSEvent.ModifierFlags = [.shift, .control, .option, .command]

    let key: String
    let modifiers: UInt

    init(key: String, modifiers: NSEvent.ModifierFlags) {
        self.key = key.lowercased()
        self.modifiers = modifiers.intersection(Self.modifierMask).rawValue
    }

    /// As Arc's `NSEvent.keyEquivalent`: with Command alone the key is `characters`, which a layout that turns
    /// Latin under Command gives in Latin. Its fallback from the key code to a character is left out.
    init?(event: NSEvent) {
        guard event.type == .keyDown else { return nil }
        let modifiers = event.modifierFlags.intersection(Self.modifierMask)
        guard let key = (modifiers == .command ? event.characters : nil) ?? event.charactersIgnoringModifiers,
            !key.isEmpty
        else { return nil }
        self.init(key: key, modifiers: modifiers)
    }
}

@MainActor
enum KeyBindings {
    /// Arc's `priorityToShortcuts`, filled as the main menu is built.
    static var priorityToShortcuts: [KeyBindingPriority: Set<KeyboardShortcut>] = [:]
}
