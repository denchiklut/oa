import AppKit

extension NSScreen {
    /// Arc's `hasFullscreenWindow`: a window of the app in full screen here, or any app's window that covers the
    /// display exactly, under the menu bar where the display has a notch. The Dock's and Notification Center's
    /// don't count.
    var hasFullscreenWindow: Bool {
        guard let id = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
            let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[CFString: Any]]
        else { return false }
        let onScreen = Set(windows.compactMap { $0[kCGWindowNumber] as? Int })
        let ownFullScreen = NSApp.windows.contains {
            $0.screen == self && $0.styleMask.contains(.fullScreen) && onScreen.contains($0.windowNumber)
        }
        var display = CGDisplayBounds(id)
        if !NSEdgeInsetsEqual(safeAreaInsets, NSEdgeInsetsZero), let menuBar = NSApp.mainMenu?.menuBarHeight {
            display.origin.y += menuBar
            display.size.height -= menuBar
        }
        return ownFullScreen
            || windows.contains { window in
                let owner = window[kCGWindowOwnerName] as? String
                guard owner != "Dock", owner != "Notification Center" else { return false }
                return (window[kCGWindowBounds] as? NSDictionary).flatMap(CGRect.init(dictionaryRepresentation:))
                    == display
            }
    }
}
