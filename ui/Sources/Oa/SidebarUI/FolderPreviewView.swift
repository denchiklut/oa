import SwiftUI

struct FolderPreviewView: View {
    let model: WindowModel
    let layout: WindowLayoutController
    let folder: SidebarFolder
    let anchor: CGRect
    @State private var query = ""
    @State private var highlightedID: UUID?

    private var results: [SidebarTab] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        // Oa searches descendants and uses sidebar order to break ties in visit time.
        return model.state.tree.tabs(under: folder.id)
            .filter {
                query.isEmpty || $0.displayTitle.localizedStandardContains(query)
                    || $0.url?.absoluteString.localizedStandardContains(query) == true
            }
            .sorted { ($0.viewedAt ?? .distantPast) > ($1.viewedAt ?? .distantPast) }
    }

    var body: some View {
        let tabs = results
        let selected = tabs.first { $0.id == highlightedID } ?? tabs.first
        let width = min(240, max(0, layout.size.width - 8))
        let listHeight = min(CGFloat(max(1, min(tabs.count, 8))) * 44, max(0, layout.size.height - 65))
        let height = listHeight + 57
        let frame = CGRect(
            x: min(anchor.maxX + 12, layout.size.width - width - 4),
            y: max(4, min(anchor.midY - height / 2, layout.size.height - height - 4)),
            width: width, height: height)
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                FolderPreviewSearchField(
                    placeholder: "Search \(folder.displayTitle)…", query: $query,
                    move: { move($0, from: selected, in: tabs) },
                    submit: { if let selected { open(selected) } },
                    dismiss: layout.dismissSidebarPreview)
            }
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 12)
            .frame(height: 48)
            Divider().frame(height: 1)
            ScrollViewReader { reader in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if tabs.isEmpty {
                            Text("No results").foregroundStyle(.secondary).frame(height: 44)
                        }
                        ForEach(tabs) { tab in
                            resultRow(tab, highlighted: tab.id == selected?.id)
                        }
                    }
                }
                .onChange(of: query) {
                    highlightedID = nil
                    if let first = tabs.first { reader.scrollTo(first.id, anchor: .top) }
                }
                .onChange(of: highlightedID) { if let highlightedID { reader.scrollTo(highlightedID) } }
            }
            .frame(height: listHeight)
            .padding(4)
        }
        .frame(width: width)
        .modifier(
            PopoverBackgroundView(cornerRadius: 12, shadowColor: .black.opacity(0.32), shadowRadius: 10, shadowY: 5)
        )
        .contentShape(Rectangle())
        .onHover { if !$0 { layout.leaveSidebarPreview(folder.id) } }
        .offset(x: frame.minX, y: frame.minY)
        .onChange(of: frame, initial: true) { layout.sidebarPreviewFrame = frame }
        .onDisappear { if layout.sidebarPreview?.id == folder.id { layout.dismissSidebarPreview() } }
    }

    private func resultRow(_ tab: SidebarTab, highlighted: Bool) -> some View {
        Button {
            open(tab)
        } label: {
            HStack(spacing: 8) {
                if tab.icon == nil && model.favicon(for: tab) == nil {
                    Image(systemName: "globe").foregroundStyle(.secondary).frame(width: 16)
                } else {
                    TabFavicon(model: model, tab: tab).frame(width: 16)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(tab.displayTitle)
                        .font(.system(size: 13, weight: .medium))
                    if let date = tab.viewedAt {
                        Text(date.formatted(.relative(presentation: .numeric)))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .frame(height: 44)
            .background {
                RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(highlighted ? 0.085 : 0))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { if $0 { highlightedID = tab.id } }
        .accessibilityAddTraits(highlighted ? .isSelected : [])
    }

    private func move(_ delta: Int, from selected: SidebarTab?, in tabs: [SidebarTab]) {
        if let index = tabs.firstIndex(where: { $0.id == selected?.id }) {
            highlightedID = tabs[max(0, min(index + delta, tabs.count - 1))].id
        }
    }

    private func open(_ tab: SidebarTab) {
        layout.dismissSidebarPreview()
        model.select(tab.id)
    }
}

/// AppKit's field editor consumes the arrow keys before SwiftUI receives them.
private struct FolderPreviewSearchField: NSViewRepresentable {
    let placeholder: String
    @Binding var query: String
    let move: (Int) -> Void
    let submit: () -> Void
    let dismiss: () -> Void

    final class Field: NSTextField {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard window != nil else { return }
            DispatchQueue.main.async { [weak self] in
                if let self, let window, window.isKeyWindow { window.makeFirstResponder(self) }
            }
        }
    }

    func makeNSView(context: Context) -> Field {
        let field = Field(string: query)
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.font = .systemFont(ofSize: 13, weight: .medium)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.delegate = context.coordinator
        return field
    }

    func updateNSView(_ field: Field, context: Context) {
        context.coordinator.search = self
        field.placeholderString = placeholder
        field.setAccessibilityLabel(placeholder)
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var search: FolderPreviewSearchField

        init(_ search: FolderPreviewSearchField) { self.search = search }

        func controlTextDidChange(_ notification: Notification) {
            if let field = notification.object as? NSTextField { search.query = field.stringValue }
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard !textView.hasMarkedText() else { return false }
            switch selector {
            case #selector(NSResponder.moveUp(_:)): search.move(-1)
            case #selector(NSResponder.moveDown(_:)): search.move(1)
            case #selector(NSResponder.insertNewline(_:)), #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)):
                search.submit()
            case #selector(NSResponder.cancelOperation(_:)): search.dismiss()
            default: return false
            }
            return true
        }
    }
}
