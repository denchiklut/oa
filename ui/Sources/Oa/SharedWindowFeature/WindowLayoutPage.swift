import Foundation

/// The pages of a window's pager, as Arc's: the Library, one per Space, then the Create a Space panel's while it is
/// open.
enum WindowLayoutPage: Hashable {
    case home
    case space(UUID)
    case spaceCreation
}
