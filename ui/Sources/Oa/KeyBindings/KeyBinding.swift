import Foundation

/// Arc's `KeyBindableAction`: the ID its menu item carries and the item's title when it registered.
struct KeyBindableAction: Hashable, Codable {
    let identifier: String
    var name: String
}

/// Arc's `KeyBinding`, coded as Arc stores one.
struct KeyBinding: Codable, Equatable, Identifiable {
    enum State: Codable, Equatable {
        case valid(ARCKeyboardShortcut)
        case conflict(shortcut: ARCKeyboardShortcut, conflictingActions: Set<KeyBindableAction>)
        case unset
    }

    enum Source: String, Codable {
        case userDefined
        case `default`
    }

    /// Who gets the shortcut while a page has the keyboard.
    enum Priority: String, Codable, CaseIterable {
        /// The page, and the menu what the page leaves.
        case low
        /// The page; when it consumes the key, a prompt, and the menu on a second press.
        case promptAfterConsumedByWebView
        /// The menu, and never the page.
        case overrideWebView
    }

    struct DefaultAttributes: Codable, Equatable {
        var shortcut: ARCKeyboardShortcut
        var priority: Priority
        /// Arc's Type Travel phrases, which Oa has none of; kept for the file's shape.
        var typeTravelTriggers: [String] = []
    }

    var action: KeyBindableAction
    var `default`: DefaultAttributes?
    var state: State
    var source: Source
    var priority: Priority

    var id: String { action.identifier }

    var shortcut: ARCKeyboardShortcut? {
        if case .valid(let shortcut) = state { shortcut } else { nil }
    }

    var unvalidatedShortcut: ARCKeyboardShortcut? {
        switch state {
        case .valid(let shortcut), .conflict(let shortcut, _): shortcut
        case .unset: nil
        }
    }

    var conflictingActions: Set<KeyBindableAction> {
        if case .conflict(_, let actions) = state { actions } else { [] }
    }
}

/// Arc's `KeyBindingsState`. Only a valid binding's shortcut is in the two lookups.
struct KeyBindingsState: Equatable {
    var bindings: [String: KeyBinding] = [:]
    var shortcutToBinding: [ARCKeyboardShortcut: KeyBinding] = [:]
    var priorityToShortcuts: [KeyBinding.Priority: Set<ARCKeyboardShortcut>] = [:]

    var userOverrides: [KeyBinding] {
        bindings.values.filter { $0.source == .userDefined }.sorted { $0.id < $1.id }
    }

    func shortcut(for identifier: String) -> ARCKeyboardShortcut? { bindings[identifier]?.shortcut }
}

/// Arc's `StorableKeyBindings.json`: the bindings the user changed, and nothing for one left at its default.
struct StorableKeyBindings: Codable {
    var version = 1
    var userOverrides: [KeyBinding] = []
}
