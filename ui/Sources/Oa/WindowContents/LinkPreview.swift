import SwiftUI

struct LinkPreview: View {
    let url: URL
    let allowsPeek: Bool
    @Environment(\.theme) private var theme
    @State private var shiftHeld = false
    @State private var monitor: Any?

    var body: some View {
        label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(theme.modalButtonGlyph.opacity(0.78))
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, 9)
            .frame(height: 24)
            .background(theme.modalButtonFill, in: Capsule())
            .overlay { Capsule().strokeBorder(theme.separator) }
            .padding(10)
            .allowsHitTesting(false)
            .onAppear {
                updateModifiers(NSEvent.modifierFlags)
                monitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
                    updateModifiers(event.modifierFlags)
                    return event
                }
            }
            .onDisappear {
                if let monitor { NSEvent.removeMonitor(monitor) }
                monitor = nil
            }
    }

    private var label: Text {
        var parts = URLComponents(url: url, resolvingAgainstBaseURL: true)
        parts?.user = nil
        parts?.password = nil
        let address = parts?.string ?? url.absoluteString
        if shiftHeld && allowsPeek {
            return Text("Open \(Text(verbatim: address).bold().foregroundColor(theme.modalButtonGlyph)) in Peek")
        }
        return Text(verbatim: address.hasPrefix("https://") ? String(address.dropFirst(8)) : address)
    }

    private func updateModifiers(_ flags: NSEvent.ModifierFlags) {
        shiftHeld = flags.intersection([.shift, .command, .option, .control]) == .shift
    }
}
