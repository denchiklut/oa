import Foundation

/// Arc's `SpaceCreation.State`: the Create a Space panel a window shows on its `spaceCreation` page. As Arc's, it is
/// kept in memory only.
struct SpaceCreationState: Equatable {
    enum Phase { case editing, animating }

    /// Arc's `insertionIndex`: `.after(SpaceID)`, or nil for `.absolute(-1)`.
    var insertAfter: UUID?
    var title = ""
    var profileID: UUID
    var icon: String?
    var phase = Phase.editing

    var canCreate: Bool { !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}
