import SwiftUI

struct LinkPreview: View {
    let url: URL
    let allowsPeek: Bool
    let allowsFocusedTab: Bool
    @Environment(\.windowTheme) private var theme
    @Environment(\.windowColorScheme) private var scheme
    @State private var modifiers: NSEvent.ModifierFlags = []
    @State private var monitor: Any?

    var body: some View {
        label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(ink)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, 9)
            .frame(height: 24)
            .background(theme.semanticColorPalette[scheme].background.color, in: Capsule())
            .overlay { Capsule().strokeBorder(ink.opacity(0.2)) }
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

    private var ink: Color { scheme == .dark ? .white : .black }

    private var label: Text {
        var parts = URLComponents(url: url, resolvingAgainstBaseURL: true)
        parts?.user = nil
        parts?.password = nil
        let address = parts?.string ?? url.absoluteString
        let destination = Text(verbatim: address).foregroundStyle(ink)
        if modifiers == .shift && allowsPeek {
            return Text("Open \(destination) in Peek").foregroundStyle(ink.opacity(0.7))
        }
        if modifiers == [.command, .shift] && allowsFocusedTab {
            return Text("Open \(destination) in a new tab and focus it").foregroundStyle(ink.opacity(0.7))
        }
        return Text(verbatim: address.hasPrefix("https://") ? String(address.dropFirst(8)) : address)
    }

    private func updateModifiers(_ flags: NSEvent.ModifierFlags) {
        modifiers = flags.intersection([.shift, .command, .option, .control])
    }
}
