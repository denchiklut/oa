/// As Arc's, at the top of `windows.json`: what a new window's sidebar starts from, which is what the user last set
/// in any window.
struct SidebarViewPreferences: Codable {
    var sidebarMode = SidebarMode.anchored
}
