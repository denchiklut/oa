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
    /// What the user typed; the field may show more.
    private(set) var text: String
    var selectedIndex = 0
    private var edited = false
    /// Chromium's rule: no completion after a deletion, with the caret before the end, or while an input method
    /// composes, until the next typing.
    private var suppressesInline = false
    /// The field's caret in what was typed, in UTF-16 code units.
    private var caret: Int
    @ObservationIgnored private var startedFresh = false
    /// Return pressed before Chromium answered the text; Arc's bar acts on the answer.
    @ObservationIgnored private var pendingReturn = false
    @ObservationIgnored var open: (URL) -> Void = { _ in }

    init(destination: Destination, autocomplete: any Autocomplete, currentURL: URL?) {
        self.destination = destination
        self.autocomplete = autocomplete
        self.currentURL = currentURL
        let text = currentURL?.absoluteString ?? ""
        self.text = text
        caret = text.utf16.count
        if !text.isEmpty { start(preventsInlineAutocomplete: true) }
    }

    var rows: [AutocompleteMatch] { text.isEmpty ? [] : autocomplete.matches }

    struct FieldText: Equatable {
        var string: String
        var selection: NSRange
    }

    /// As Arc's field: ⌘L's URL all selected until the first edit or arrow; the typed text with the default match's
    /// inline completion selected after it; on another row, a search's text with the untyped rest selected, else its
    /// URL.
    var field: FieldText {
        let typed = (text as NSString).length
        if !edited, destination == .currentTab, selectedIndex == 0 {
            return FieldText(string: text, selection: NSRange(0..<typed))
        }
        if selectedIndex > 0, rows.indices.contains(selectedIndex) {
            let row = rows[selectedIndex]
            switch row.kind {
            case .searchWhatYouTyped, .searchHistory, .searchSuggest, .searchSuggestEntity, .searchOtherEngine:
                let length = (row.contents as NSString).length
                let rest = row.contents.lowercased().hasPrefix(text.lowercased()) ? typed..<length : length..<length
                return FieldText(string: row.contents, selection: NSRange(rest))
            default:
                let length = (row.fillIntoEdit as NSString).length
                return FieldText(string: row.fillIntoEdit, selection: NSRange(location: length, length: 0))
            }
        }
        if !suppressesInline, autocomplete.input?.text == text, let first = rows.first, first.allowedToBeDefault,
            !first.inlineAutocompletion.isEmpty
        {
            let completion = (first.inlineAutocompletion as NSString).length
            return FieldText(
                string: text + first.inlineAutocompletion, selection: NSRange(location: typed, length: completion))
        }
        return FieldText(string: text, selection: NSRange(location: min(caret, typed), length: 0))
    }

    /// `caret` is the field's, in UTF-16 code units.
    func edit(_ text: String, caret: Int, deleting: Bool, composing: Bool = false) {
        edited = true
        selectedIndex = 0
        self.caret = caret
        suppressesInline = deleting || composing || caret < (text as NSString).length
        guard text != self.text else { return }
        self.text = text
        pendingReturn = false
        if text.isEmpty { autocomplete.stop() } else { start(preventsInlineAutocomplete: suppressesInline) }
    }

    /// The caret moved without an edit. What the field showed beyond the typed text, a completion or a row's
    /// text, is typed from now on, as in Chromium.
    func moveCaret(to caret: Int, in string: String) {
        guard string == text else { return edit(string, caret: caret, deleting: false) }
        edited = true
        self.caret = caret
        if caret < (text as NSString).length { suppressesInline = true }
    }

    /// As Arc's ⇧⌦: a past search goes, while a page from history stays.
    func deleteSelectedRow() {
        guard rows.indices.contains(selectedIndex) else { return }
        let row = rows[selectedIndex]
        if row.kind == .searchHistory, row.isDeletable { autocomplete.delete(row) }
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
                text: text, cursorPosition: min(caret, text.utf16.count),
                preventsInlineAutocomplete: preventsInlineAutocomplete, startsFresh: !startedFresh,
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

/// An AppKit field, which a SwiftUI one can't be: it takes focus over a web page, selects an inline completion and
/// reports the caret, the arrow keys, Return, Esc and ⇧⌦.
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
        field.cell?.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.delegate = context.coordinator
        let coordinator = context.coordinator
        coordinator.field = field
        coordinator.isUnderDialog = isUnderDialog
        coordinator.show(bar.field, in: field)
        NotificationCenter.default.addObserver(
            coordinator, selector: #selector(Coordinator.selectionChanged(_:)),
            name: NSTextView.didChangeSelectionNotification, object: nil)
        if !isUnderDialog { DispatchQueue.main.async { coordinator.focus() } }
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        let coordinator = context.coordinator
        coordinator.bar = bar
        if isUnderDialog != coordinator.isUnderDialog {
            coordinator.isUnderDialog = isUnderDialog
            if !isUnderDialog { coordinator.focus() }
        }
        let editor = field.currentEditor() as? NSTextView
        // An input method's marked text is the field's until it is committed.
        guard editor?.hasMarkedText() != true else { return }
        let shown = bar.field
        guard shown != coordinator.shown else { return }
        coordinator.show(shown, in: field)
    }

    static func dismantleNSView(_ field: NSTextField, coordinator: Coordinator) {
        NotificationCenter.default.removeObserver(coordinator)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var bar: CommandBar
        let model: WindowModel
        weak var field: NSTextField?
        /// What the field shows, with the user's selection in it.
        private(set) var shown = CommandBar.FieldText(string: "", selection: NSRange())
        var isUnderDialog = false
        /// The field is being written here, so its selection changes aren't the user's.
        private var isShowing = false

        init(bar: CommandBar, model: WindowModel) {
            self.bar = bar
            self.model = model
        }

        func show(_ text: CommandBar.FieldText, in field: NSTextField) {
            isShowing = true
            defer { isShowing = false }
            shown = text
            if field.stringValue != text.string { field.stringValue = text.string }
            (field.currentEditor() as? NSTextView)?.setSelectedRange(text.selection)
        }

        func focus() {
            guard let field else { return }
            isShowing = true
            defer { isShowing = false }
            field.window?.makeFirstResponder(field)
            (field.currentEditor() as? NSTextView)?.setSelectedRange(shown.selection)
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            let editor = field.currentEditor() as? NSTextView
            let string = field.stringValue
            let length = (string as NSString).length
            let selection = editor?.selectedRange() ?? NSRange(location: length, length: 0)
            // Chromium's rule for a deletion: the text got shorter and the caret didn't move forward.
            let deleting =
                length < (shown.string as NSString).length && selection.location <= shown.selection.location
            shown = CommandBar.FieldText(string: string, selection: selection)
            bar.edit(
                string, caret: selection.location, deleting: deleting, composing: editor?.hasMarkedText() == true)
        }

        @objc func selectionChanged(_ notification: Notification) {
            guard !isShowing, let field, let editor = notification.object as? NSTextView,
                editor === field.currentEditor(), !editor.hasMarkedText(), field.stringValue == shown.string
            else { return }
            let selection = editor.selectedRange()
            guard selection != shown.selection else { return }
            shown.selection = selection
            bar.moveCaret(to: selection.location, in: shown.string)
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.moveUp(_:)): bar.moveSelection(-1)
            case #selector(NSResponder.moveDown(_:)): bar.moveSelection(1)
            case #selector(NSResponder.insertNewline(_:)): bar.submit()
            case #selector(NSResponder.cancelOperation(_:)): model.closeCommandBar()
            case #selector(NSResponder.insertTab(_:)): break
            case #selector(NSResponder.deleteForward(_:))
            where NSApp.currentEvent?.modifierFlags.contains(.shift) == true:
                bar.deleteSelectedRow()
            default: return false
            }
            return true
        }
    }
}
