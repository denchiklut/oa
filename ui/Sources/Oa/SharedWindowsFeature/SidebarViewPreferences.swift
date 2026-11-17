import Foundation

/// As Arc's, at the top of `windows.json`: what a new window's sidebar starts from, which is what the user last set
/// in any window.
struct SidebarViewPreferences: Codable {
    /// The width Arc's sidebar was measured at; its reset width is another, `SidebarResizeState.resetWidth`.
    static let defaultWidth: CGFloat = 241

    var sidebarMode = SidebarMode.anchored
    var sidebarWidth = defaultWidth

    init() {}

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        sidebarMode = try values.decode(SidebarMode.self, forKey: .sidebarMode)
        sidebarWidth = try values.decodeIfPresent(CGFloat.self, forKey: .sidebarWidth) ?? Self.defaultWidth
    }
}
