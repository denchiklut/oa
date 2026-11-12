import AppKit
import DevKit
import SwiftUI

/// Arc's command bar: one card for ⌘T, ⌘L, the toolbar's URL and the sidebar's New Tab row.
@MainActor
@Observable
final class CommandBar {
    /// As Arc's `CommandBarDestinationType`.
    enum Destination { case newTab, currentTab }

    let destination: Destination
    let autocomplete: any Autocomplete
    /// The page ⌘L edits, prefilled and selected as Arc does.
    let currentURL: URL?
    var text: String
    var selectedIndex = 0
    @ObservationIgnored private var startedFresh = false
    /// Return pressed before Chromium answered the text; Arc's bar acts on the answer.
    @ObservationIgnored private var pendingReturn = false
    @ObservationIgnored var open: (URL) -> Void = { _ in }

    init(destination: Destination, autocomplete: any Autocomplete, currentURL: URL?) {
        self.destination = destination
        self.autocomplete = autocomplete
        self.currentURL = currentURL
        text = currentURL?.absoluteString ?? ""
        if !text.isEmpty { start(preventsInlineAutocomplete: true) }
    }

    var rows: [AutocompleteMatch] { text.isEmpty ? [] : autocomplete.matches }

    func edit(_ text: String, preventsInlineAutocomplete: Bool) {
        guard text != self.text else { return }
        self.text = text
        selectedIndex = 0
        pendingReturn = false
        if text.isEmpty { autocomplete.stop() } else { start(preventsInlineAutocomplete: preventsInlineAutocomplete) }
    }

    func moveSelection(_ offset: Int) {
        guard !rows.isEmpty else { return }
        selectedIndex = min(max(selectedIndex + offset, 0), rows.count - 1)
    }

    func submit() {
        guard !text.isEmpty else { return }
        guard autocomplete.input?.text == text else {
            pendingReturn = true
            return
        }
        openSelected()
    }

    func answered() {
        if selectedIndex >= rows.count { selectedIndex = 0 }
        guard pendingReturn, autocomplete.input?.text == text else { return }
        pendingReturn = false
        openSelected()
    }

    private func openSelected() {
        guard rows.indices.contains(selectedIndex), let url = rows[selectedIndex].url else { return }
        open(url)
    }

    private func start(preventsInlineAutocomplete: Bool) {
        autocomplete.start(
            AutocompleteInput(
                text: text, preventsInlineAutocomplete: preventsInlineAutocomplete, startsFresh: !startedFresh,
                currentURL: destination == .currentTab ? currentURL : nil))
        startedFresh = true
    }
}

/// Measured in Arc 1.172.2: a 766 pt card centred on the whole window, its top about 31% down, five 50 pt rows
/// showing before the list scrolls.
struct CommandBarView: View {
    static let width: CGFloat = 766
    static let rowHeight: CGFloat = 50
    static let visibleRows = 5
    static let topFraction: CGFloat = 270 / 879

    let model: WindowModel
    let bar: CommandBar

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { model.closeCommandBar() }
                card
                    .frame(width: min(Self.width, geometry.size.width - 32))
                    .padding(.top, geometry.size.height * Self.topFraction)
            }
        }
        .onChange(of: bar.autocomplete.input) { _, _ in bar.answered() }
        .onChange(of: bar.autocomplete.matches) { _, _ in bar.answered() }
    }

    private var card: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(
                    systemName: icon(
                        for: bar.rows.indices.contains(bar.selectedIndex) ? bar.rows[bar.selectedIndex] : nil)
                )
                .foregroundStyle(.secondary)
                .frame(width: 18)
                CommandBarField(bar: bar, model: model, isUnderDialog: model.dialog != nil)
                    .frame(height: 23)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            if !bar.rows.isEmpty {
                Divider()
                rows
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator))
        .shadow(color: .black.opacity(0.25), radius: 24, y: 8)
    }

    private var rows: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(bar.rows.enumerated()), id: \.element.id) { index, match in
                        CommandBarRow(match: match, icon: icon(for: match), selected: index == bar.selectedIndex)
                            .id(index)
                            .onTapGesture {
                                bar.selectedIndex = index
                                bar.submit()
                            }
                    }
                }
                .padding(.horizontal, 8)
            }
            .frame(height: CGFloat(min(bar.rows.count, Self.visibleRows)) * Self.rowHeight)
            .onChange(of: bar.selectedIndex) { _, index in proxy.scrollTo(index) }
        }
    }

    private func icon(for match: AutocompleteMatch?) -> String {
        switch match?.kind {
        case .historyURL, .historyTitle: "clock"
        case .searchWhatYouTyped, .searchHistory, .searchSuggest, .searchSuggestEntity, .searchOtherEngine:
            "magnifyingglass"
        case .urlWhatYouTyped, .navSuggest, nil: "globe"
        }
    }
}

private struct CommandBarRow: View {
    let match: AutocompleteMatch
    let icon: String
    let selected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 18)
            Text(title)
                .lineLimit(1)
            if let address {
                Text("— " + address)
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .frame(height: CommandBarView.rowHeight)
        .background(selected ? Color.accentColor.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
    }

    private var title: String {
        switch match.kind {
        case .historyURL, .historyTitle, .navSuggest: match.description.isEmpty ? match.contents : match.description
        default: match.contents
        }
    }

    private var address: String? {
        switch match.kind {
        case .historyURL, .historyTitle, .navSuggest:
            guard let url = match.url, let host = url.host() else { return nil }
            let path = url.path() == "/" ? "" : url.path()
            return host + (url.port.map { ":\($0)" } ?? "") + path
        default: return nil
        }
    }
}

/// An AppKit field, which a SwiftUI one can't be: it takes focus over a web page and reports the arrow keys, Return
/// and Esc.
private struct CommandBarField: NSViewRepresentable {
    let bar: CommandBar
    let model: WindowModel
    /// As Arc: a JavaScript dialog keeps the keys while the bar is open behind it.
    let isUnderDialog: Bool

    func makeCoordinator() -> Coordinator { Coordinator(bar: bar, model: model) }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 17)
        field.placeholderString = "Search or Enter URL…"
        field.stringValue = bar.text
        field.cell?.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.delegate = context.coordinator
        context.coordinator.isUnderDialog = isUnderDialog
        if !isUnderDialog {
            DispatchQueue.main.async {
                field.window?.makeFirstResponder(field)
                field.currentEditor()?.selectAll(nil)
            }
        }
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.bar = bar
        if field.stringValue != bar.text { field.stringValue = bar.text }
        if isUnderDialog != context.coordinator.isUnderDialog {
            context.coordinator.isUnderDialog = isUnderDialog
            if !isUnderDialog { field.window?.makeFirstResponder(field) }
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var bar: CommandBar
        let model: WindowModel
        var isUnderDialog = false

        init(bar: CommandBar, model: WindowModel) {
            self.bar = bar
            self.model = model
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            bar.edit(field.stringValue, preventsInlineAutocomplete: false)
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.moveUp(_:)): bar.moveSelection(-1)
            case #selector(NSResponder.moveDown(_:)): bar.moveSelection(1)
            case #selector(NSResponder.insertNewline(_:)): bar.submit()
            case #selector(NSResponder.cancelOperation(_:)): model.closeCommandBar()
            default: return false
            }
            return true
        }
    }
}
