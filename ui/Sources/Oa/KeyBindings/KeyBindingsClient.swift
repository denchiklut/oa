import Foundation
import Observation

/// Arc's `KeyBindingsClient`: the bindable actions, their shortcuts and priorities, and the user's overrides.
@MainActor
@Observable
final class KeyBindingsClient {
    private struct ActionState {
        var state: KeyBinding.State
        var source: KeyBinding.Source
        var priority: KeyBinding.Priority
    }

    private(set) var state = KeyBindingsState()
    @ObservationIgnored private var actions: [String: KeyBindableAction] = [:]
    @ObservationIgnored private var states: [String: ActionState] = [:]
    @ObservationIgnored private var defaults: [String: KeyBinding.DefaultAttributes] = [:]
    @ObservationIgnored private var didRegisterUserOverrides = false
    @ObservationIgnored private let url: URL

    init(directory: URL) { url = directory.appendingPathComponent("StorableKeyBindings.json") }

    /// As Arc's, for a menu item at launch: its key and priority are the action's defaults.
    func registerAction(_ action: KeyBindableAction, shortcut: ARCKeyboardShortcut?, priority: KeyBinding.Priority) {
        actions[action.identifier] = action
        defaults[action.identifier] = shortcut.map { KeyBinding.DefaultAttributes(shortcut: $0, priority: priority) }
        guard states[action.identifier] == nil else { return publish() }
        states[action.identifier] = ActionState(state: .unset, source: .default, priority: priority)
        set(shortcut, for: action.identifier, source: .default)
    }

    func setShortcut(_ shortcut: ARCKeyboardShortcut?, for identifier: String) {
        set(shortcut, for: identifier, source: .userDefined)
    }

    func setPriority(_ priority: KeyBinding.Priority, for identifier: String) {
        guard var entry = states[identifier] else { return }
        entry.priority = priority
        entry.source = isDefault(entry, of: identifier) ? .default : .userDefined
        states[identifier] = entry
        publish()
    }

    func resetToDefault(_ identifier: String) {
        guard states[identifier] != nil else { return }
        set(defaults[identifier]?.shortcut, for: identifier, source: .default, publishing: false)
        states[identifier]?.priority = defaults[identifier]?.priority ?? .low
        states[identifier]?.source = .default
        publish()
    }

    func resetToDefaults() {
        for identifier in states.keys {
            states[identifier] = ActionState(
                state: defaults[identifier].map { .valid($0.shortcut) } ?? .unset, source: .default,
                priority: defaults[identifier]?.priority ?? .low)
        }
        resolveConflicts()
        publish()
    }

    /// As Arc's load: an entry counts for a registered action and a shortcut a user may set, and conflicts are
    /// worked out again, not taken from the file.
    func registerUserOverrides() {
        let stored = (try? Data(contentsOf: url)).flatMap {
            try? JSONDecoder().decode(StorableKeyBindings.self, from: $0)
        }
        for binding in stored?.userOverrides ?? [] where states[binding.id] != nil {
            if let shortcut = binding.shortcut, ARCKeyboardShortcut.shortcutsForbiddenForUsers.contains(shortcut) {
                continue
            }
            set(binding.unvalidatedShortcut, for: binding.id, source: .userDefined, publishing: false)
            states[binding.id]?.priority = binding.priority
            if let entry = states[binding.id], !isDefault(entry, of: binding.id) {
                states[binding.id]?.source = .userDefined
            }
        }
        didRegisterUserOverrides = true
        publish()
    }

    /// As Arc's `set(shortcut:for:source:publishState:)`. A forbidden shortcut is refused to a user, a binding back
    /// at its default is no override whoever set it, and every action sharing a shortcut is in conflict.
    private func set(
        _ shortcut: ARCKeyboardShortcut?, for identifier: String, source: KeyBinding.Source, publishing: Bool = true
    ) {
        guard var entry = states[identifier] else { return }
        if source == .userDefined, let shortcut, ARCKeyboardShortcut.shortcutsForbiddenForUsers.contains(shortcut) {
            return
        }
        entry.state = shortcut.map { .valid($0) } ?? .unset
        entry.source = isDefault(entry, of: identifier) ? .default : source
        states[identifier] = entry
        resolveConflicts()
        if publishing { publish() }
    }

    private func isDefault(_ entry: ActionState, of identifier: String) -> Bool {
        let attributes = defaults[identifier]
        return entry.state == attributes.map { .valid($0.shortcut) } ?? .unset
            && entry.priority == attributes?.priority ?? .low
    }

    private func resolveConflicts() {
        var holders: [ARCKeyboardShortcut: [String]] = [:]
        for (identifier, entry) in states {
            switch entry.state {
            case .valid(let shortcut), .conflict(let shortcut, _): holders[shortcut, default: []].append(identifier)
            case .unset: break
            }
        }
        for (shortcut, identifiers) in holders {
            for identifier in identifiers {
                let others = Set(identifiers.filter { $0 != identifier }.compactMap { actions[$0] })
                states[identifier]?.state =
                    others.isEmpty ? .valid(shortcut) : .conflict(shortcut: shortcut, conflictingActions: others)
            }
        }
    }

    private func publish() {
        var next = KeyBindingsState()
        for (identifier, entry) in states {
            guard let action = actions[identifier] else { continue }
            let binding = KeyBinding(
                action: action, default: defaults[identifier], state: entry.state, source: entry.source,
                priority: entry.priority)
            next.bindings[identifier] = binding
            if let shortcut = binding.shortcut {
                next.shortcutToBinding[shortcut] = binding
                next.priorityToShortcuts[entry.priority, default: []].insert(shortcut)
            }
        }
        guard next != state else { return }
        let overrides = state.userOverrides
        state = next
        // Not before the file was read, so an empty state is never written over it.
        guard didRegisterUserOverrides, next.userOverrides != overrides else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? encoder.encode(StorableKeyBindings(userOverrides: next.userOverrides)).write(to: url, options: .atomic)
    }
}
