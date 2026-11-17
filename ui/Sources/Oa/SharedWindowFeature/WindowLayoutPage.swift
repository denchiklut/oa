import Foundation

/// The pages of a window's pager, as Arc's: one per Space. Arc's `spaceCreation` page waits for the Create a Space
/// panel.
enum WindowLayoutPage: Hashable {
    case space(UUID)
}
