import SwiftUI

struct EssentialShortcutsCallout: View {
    let keyBindings: KeyBindingsClient
    @State private var showsGuide = false
    @Environment(\.colorScheme) private var scheme

    // Oa's guide uses the user's current menu bindings so it also teaches customized shortcuts.
    private static let actions = ["newTab", "addressBar", "showSidebar", "pinTab", "archiveTab", "reopenLastClosedTab"]

    var body: some View {
        HStack(spacing: 8) {
            Text("Start with the basics")
            Button {
                showsGuide.toggle()
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "command.circle.fill")
                    Text("Learn the Essential Shortcuts")
                }
                .foregroundStyle(.white)
                .frame(width: 215.5, height: 24)
                .background(Color(red: 0, green: 0.478, blue: 1), in: RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showsGuide, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Essential Shortcuts").font(.headline)
                    ForEach(Self.actions.compactMap { keyBindings.state.bindings[$0] }) { binding in
                        HStack {
                            Text(binding.action.name)
                            Spacer(minLength: 16)
                            switch binding.state {
                            case .valid(let shortcut): Text(shortcut.symbols.joined())
                            case .conflict(let shortcut, _): Text("\(shortcut.symbols.joined()) (Conflict)")
                            case .unset: Text("Unassigned")
                            }
                        }
                    }
                }
                .frame(width: 260)
                .padding(16)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 36)
        .background(
            scheme == .dark ? Color(red: 0.396, green: 0.376, blue: 0.406) : .white,
            in: RoundedRectangle(cornerRadius: 6)
        )
        .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
    }
}
