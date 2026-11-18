import Foundation

/// The pages of a window's pager, as Arc's: the Library, then one per Space and, while the Create a Space panel is
/// open, its page at the slot the new Space will take.
enum WindowLayoutPage: Hashable {
    case home
    case space(UUID)
    case spaceCreation
}
