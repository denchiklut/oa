import AppKit
import Observation

/// Arc's `SpacesMainMenuProvider`: an item in the Spaces menu for each Space, titled with its name, whose binding
/// goes by the Space's place, as Arc's `spaceBindingID(for:)` does.
@MainActor
final class SpacesMainMenuProvider {
    private let menu: NSMenu
    private let anchor: NSMenuItem
    private let store: SidebarStore
    private var items: [NSMenuItem] = []
    private var names: [String]?

    init(menu: NSMenu, after anchor: NSMenuItem, store: SidebarStore) {
        self.menu = menu
        self.anchor = anchor
        self.store = store
        observeSpaces()
    }

    static func bindingID(for position: Int) -> String { "space\(position)" }

    static func position(of identifier: String) -> Int? {
        identifier.hasPrefix("space") ? Int(identifier.dropFirst(5)) : nil
    }

    private func observeSpaces() {
        let names = withObservationTracking {
            store.state.spaces.map(\.name)
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeSpaces() }
        }
        guard names != self.names else { return }
        self.names = names
        updateItems(names)
    }

    /// As in Arc's menu, ⌃1 to ⌃9 by place and none past the ninth. Oa's own: the binding of a place no Space holds
    /// any more goes with it.
    private func updateItems(_ names: [String]) {
        let client = store.keyBindings
        for position in stride(from: items.count, to: names.count, by: -1) {
            client.unregisterAction(Self.bindingID(for: position))
        }
        items.forEach(menu.removeItem)
        let start = menu.index(of: anchor) + 1
        items = names.enumerated().map { offset, name in
            let position = offset + 1
            let id = Self.bindingID(for: position)
            client.registerAction(
                KeyBindableAction(identifier: id, name: name),
                shortcut: position <= 9 ? ARCKeyboardShortcut(key: "\(position)", modifiers: .control) : nil,
                priority: .low)
            let shortcut = client.state.shortcut(for: id)
            let item = KeyBindableMenuItem(
                title: name, action: #selector(BrowserWindowController.focusSpace(_:)),
                keyEquivalent: shortcut?.menuKeyEquivalent ?? "")
            item.keyEquivalentModifierMask = shortcut?.modifiers ?? []
            item.arcKeyBindingID = id
            item.tag = position
            menu.insertItem(item, at: start + offset)
            return item
        }
    }
}
