import SwiftUI

/// Arc's dock "+": a popover over it, 222 pt wide with 40 pt rows, and the plus turns into ✕ while it is open. Its rows
/// are Arc's in Arc's order; what Oa doesn't have yet is listed disabled.
struct SidebarPlusButton: View {
    let model: WindowModel
    let layout: WindowLayoutController
    @State private var isOpen = false

    var body: some View {
        Button {
            isOpen.toggle()
        } label: {
            // As measured on Arc: a 14 pt glyph in a 32 pt button, in the header's grey.
            Image(systemName: isOpen ? "xmark" : "plus")
                .font(.system(size: 16, weight: .medium))
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(ChromeButtonStyle())
        .popover(isPresented: $isOpen, arrowEdge: .top) {
            SidebarPlusMenu(model: model) { isOpen = false }
        }
        .onChange(of: isOpen) { layout.setHold(.popover, $1) }
    }
}

private struct SidebarPlusMenu: View {
    private struct Row: Identifiable {
        let title: String
        let symbol: String
        var shortcut = ""
        var action: (() -> Void)?

        var id: String { title }
    }

    let model: WindowModel
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
                    Divider().padding(.horizontal, 4).padding(.vertical, 8)
                }
                ForEach(rows) { row in item(row) }
            }
        }
        .padding(14)
        .frame(width: 222)
    }

    private func item(_ row: Row) -> some View {
        let enabled = row.action != nil
        return Button {
            dismiss()
            row.action?()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: row.symbol)
                    .font(.system(size: 15))
                    .frame(width: 22)
                Text(row.title)
                    .font(.system(size: 13, weight: .medium))
                Spacer(minLength: 0)
                Text(row.shortcut)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(enabled ? .primary : .tertiary)
            .padding(.horizontal, 10)
            .frame(height: 40)
            .background(
                enabled && highlighted == row.id ? Color.accentColor.opacity(0.15) : .clear,
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .onHover { if $0, enabled { highlighted = row.id } }
    }
}
