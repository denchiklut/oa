import AppKit

/// What ⌘Z and ⇧⌘Z send back to a window, as Arc registers `WindowAction`s.
enum UndoAction {
    /// Arc's `undoCloseItems`: everything one close took, by its group in the window's closed items.
    case undoCloseItems(groupID: UUID)
    case closeItems([UUID], undoPrompt: String)
    case closePeek(ownerID: UUID)
    /// Arc's `undoUpdateSpaceTheme`: the theme the Space had before, none for the default.
    case updateSpaceTheme(spaceID: UUID, theme: WindowTheme?)
}

/// Arc's names for what Edit ▸ Undo takes back.
enum UndoStrings {
    static let archiveTab = "Archive Tab"
    static let closePeek = "Close Peek"
    static let updateTheme = "Update Theme"
    static func clearTabs(_ count: Int) -> String { count == 1 ? "Clear Tab" : "Clear Tabs" }
}

/// Arc's `ArcUndoManager`, over the window's own undo manager: a step is a name and the actions that take it
/// back, which the window replays. A replayed action registers its own, inside the undo or redo that runs it, so
/// AppKit files it on the other stack.
@MainActor
final class ArcUndoManager {
    private final class UndoTarget {}

    private weak var undoManager: UndoManager?
    /// The undo manager doesn't keep a step's target alive; this does, until the step runs or is removed.
    private var targets: [String: UndoTarget] = [:]
    private let perform: (UndoAction) -> Void

    init(_ undoManager: UndoManager?, perform: @escaping (UndoAction) -> Void) {
        self.undoManager = undoManager
        self.perform = perform
    }

    func registerUndos(_ actions: [UndoAction], _ name: String, _ invalidationID: String = UUID().uuidString) {
        guard let undoManager else { return }
        let target = UndoTarget()
        targets[invalidationID] = target
        undoManager.beginUndoGrouping()
        for (index, action) in actions.enumerated() {
            undoManager.registerUndo(withTarget: target) { [weak self] _ in
                self?.perform(action)
                if index == 0 { self?.targets[invalidationID] = nil }
            }
        }
        undoManager.endUndoGrouping()
        undoManager.setActionName(name)
    }

    func removeUndos(_ invalidationID: String) {
        guard let target = targets.removeValue(forKey: invalidationID) else { return }
        undoManager?.removeAllActions(withTarget: target)
    }
}
