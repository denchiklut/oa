import AppKit
import Observation

/// A menu item with what Arc's nib gives its own as runtime attributes: the ID of its bindable action and who gets
/// its shortcut over a page.
final class KeyBindableMenuItem: NSMenuItem {
    var arcKeyBindingID = ""
    var arcKeyBindingPriority = KeyBinding.Priority.low
}

extension NSMenu {
    /// As Arc's `firstItem(with:)`, through the submenus.
    func firstItem(with shortcut: ARCKeyboardShortcut) -> NSMenuItem? {
        for item in items {
            if item.keyboardShortcut == shortcut { return item }
            if let found = item.submenu?.firstItem(with: shortcut) { return found }
        }
        return nil
    }
}

/// Arc's `KeyBindingMenuManager`: the main menu's items register as the bindable actions, their keys the defaults,
/// and each item's key then follows its binding.
@MainActor
final class KeyBindingMenuManager {
    private let menu: NSMenu
    private let client: KeyBindingsClient

    init(menu: NSMenu, client: KeyBindingsClient) {
        self.menu = menu
        self.client = client
        for item in Self.bindableItems(in: menu) {
            client.registerAction(
                KeyBindableAction(identifier: item.arcKeyBindingID, name: item.title),
                shortcut: item.keyboardShortcut, priority: item.arcKeyBindingPriority)
        }
        client.registerUserOverrides()
        applyBindings()
        observeBindings()
    }

    private static func bindableItems(in menu: NSMenu) -> [KeyBindableMenuItem] {
        menu.items.flatMap { item in
            (item as? KeyBindableMenuItem).map { [$0] } ?? [] + (item.submenu.map(bindableItems(in:)) ?? [])
        }
    }

    /// Debounced by a tenth of a second, as Arc's.
    private func observeBindings() {
        withObservationTracking {
            _ = client.state
        } onChange: { [weak self] in
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(0.1))
                self?.applyBindings()
                self?.observeBindings()
            }
        }
    }

    /// An item whose binding is unset or in conflict has no key.
    private func applyBindings() {
        for item in Self.bindableItems(in: menu) {
            guard let binding = client.state.bindings[item.arcKeyBindingID] else { continue }
            item.keyEquivalent = binding.shortcut?.menuKeyEquivalent ?? ""
            item.keyEquivalentModifierMask = binding.shortcut?.modifiers ?? []
        }
    }
}
