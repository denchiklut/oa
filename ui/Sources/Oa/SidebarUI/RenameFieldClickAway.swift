import AppKit
import SwiftUI

extension View {
    /// Calls `end` for a mouse press anywhere outside this text field, which still goes on to its target.
    func endsOnClickAway(_ end: @escaping (NSEvent) -> Void) -> some View {
        modifier(RenameFieldClickAway(end: end))
    }
}

private struct RenameFieldClickAway: ViewModifier {
    let end: (NSEvent) -> Void
    @State private var monitor: Any?

    func body(content: Content) -> some View {
        content
            .onAppear {
                monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown])
                {
                    if !Self.landsInField($0) { end($0) }
                    return $0
                }
            }
            .onDisappear {
                if let monitor { NSEvent.removeMonitor(monitor) }
                monitor = nil
            }
    }

    /// SwiftUI's field is the delegate of the window's field editor while it has the focus.
    private static func landsInField(_ event: NSEvent) -> Bool {
        guard let window = event.window, let editor = window.firstResponder as? NSTextView, editor.isFieldEditor,
            let field = editor.delegate as? NSView, let hit = window.contentView?.hitTest(event.locationInWindow)
        else { return false }
        return hit.isDescendant(of: field)
    }
}
