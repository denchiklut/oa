import SwiftUI

/// Arc's dock "+": its menu above it, and the plus turns into ✕ while it is open. Its rows are Arc's in Arc's order;
/// what Oa doesn't have yet is listed disabled.
struct SidebarPlusButton: View {
    let model: WindowModel
    let layout: WindowLayoutController
    @State private var isOpen = false
    @Environment(\.windowColorScheme) private var windowColorScheme

    var body: some View {
        Button {
            isOpen = true
        } label: {
            // As measured on Arc: a 14 pt glyph in a 32 pt button, in the header's grey.
            Image(systemName: isOpen ? "xmark" : "plus")
                .font(.system(size: 16, weight: .medium))
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(ChromeButtonStyle())
        // The click that closes the menu is not one that opens it.
        .allowsHitTesting(!isOpen)
        // As measured on Arc: the menu's right edge is the button's, and it has no arrow of AppKit's.
        .overlay(alignment: .topTrailing) {
            SpaceStyleEditorAnchor(isPresented: isOpen, above: true, onClose: { isOpen = false }) {
                SidebarPlusMenu(
                    model: model, palette: layout.chromeTheme.semanticColorPalette[windowColorScheme],
                    isDark: windowColorScheme == .dark
                ) { isOpen = false }
            }
            .frame(width: SidebarPlusMenu.width, height: 1)
            .offset(y: -2)
            .allowsHitTesting(false)
        }
        .onChange(of: isOpen) { layout.setHold(.popover, $1) }
    }
}

/// As measured on Arc 1.174, light and dark: 210 pt wide with 40 pt rows, in the palette the app's appearance picks
/// from the window's theme, whatever the theme's content is. The card is its `backgroundExtra`, the chosen row and
/// the dividers its `hover`, the shortcuts its `subtitle`; the rest is black or white, and grey when disabled.
private struct SidebarPlusMenu: View {
    static let width: CGFloat = 210

    private struct Row: Identifiable {
        let title: String
        let symbol: String
        var shortcut = ""
        var action: (() -> Void)?

        var id: String { title }
    }

    let model: WindowModel
    let palette: WindowTheme.SemanticColorPalette
    let isDark: Bool
    let dismiss: () -> Void
    /// As Arc's: New Tab is highlighted until the pointer picks another row.
    @State private var highlighted = "New Tab"

    var body: some View {
        let groups: [[Row]] = [
            [
                Row(title: "New Space", symbol: "plus.rectangle.on.rectangle") {
                    model.beginSpaceCreation(after: model.selectedSpaceID)
                },
                Row(title: "New Folder", symbol: "folder"),
            ],
            [
                Row(title: "New Easel", symbol: "scribble", shortcut: "⌃⇧E"),
                Row(title: "New Boost", symbol: "wand.and.sparkles"),
            ],
            [
                Row(title: "New Split", symbol: "rectangle.split.2x1", shortcut: "⌃⇧="),
                Row(title: "New Tab", symbol: "plus.square", shortcut: "⌘T") { model.openCommandBar(.newTab) },
            ],
        ]
        VStack(spacing: 0) {
            ForEach(Array(groups.enumerated()), id: \.offset) { index, rows in
                if index > 0 {
                    Rectangle().fill(palette.hover.color).frame(height: 1).padding(.horizontal, 4).padding(.vertical, 8)
                }
                ForEach(rows) { row in item(row) }
            }
        }
        .padding(8)
        .frame(width: Self.width)
        .background(palette.backgroundExtra.color)
    }

    private func item(_ row: Row) -> some View {
        let enabled = row.action != nil
        return Button {
            dismiss()
            row.action?()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: row.symbol)
                    .font(.system(size: 17, weight: .medium))
                    .frame(width: 22)
                Text(row.title)
                    .font(.system(size: 13, weight: .medium))
                Spacer(minLength: 0)
                Text(row.shortcut)
                    .font(.system(size: 13))
                    .foregroundStyle(palette.subtitle.color)
            }
            .foregroundStyle(enabled ? (isDark ? Color.white : .black) : disabledInk)
            .padding(.leading, 8)
            .padding(.trailing, 11)
            .frame(height: 40)
            .background(
                enabled && highlighted == row.id ? palette.hover.color : .clear, in: RoundedRectangle(cornerRadius: 8)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Not `disabled`, which would dim the grey again.
        .allowsHitTesting(enabled)
        .onHover { if $0, enabled { highlighted = row.id } }
    }

    private var disabledInk: Color {
        isDark ? Color(.sRGB, red: 0.475, green: 0.47, blue: 0.505) : Color(.sRGB, white: 0.67)
    }
}
