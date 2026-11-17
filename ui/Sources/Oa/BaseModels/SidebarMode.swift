/// Arc's two saved modes of a window's sidebar: docked beside the page, or hidden.
enum SidebarMode: String, Codable {
    case anchored, noChrome
}

/// How a window shows its sidebar, as Arc derives it: a hidden one floats over the page while the pointer or the
/// sidebar itself asks for it. Never saved.
enum SidebarPresentation {
    case locked, floating, hidden
}
