import AppKit
import DevKit
import SwiftUI

/// Arc's command bar: one card for ⌘T, ⌘L, the toolbar's URL and the sidebar's New Tab row.
@MainActor
@Observable
final class CommandBar {
    /// As Arc's `CommandBarDestinationType`.
    enum Destination { case newTab, currentTab }

    /// As Arc's `CommandBarSelectionOptions.Action`.
    enum Action {
        case open(URL, background: Bool)
        case switchTo(UUID)
    }

    /// One of Chromium's matches, or one of the Space's open tabs as Arc's sidebar provider offers them.
    struct Row: Identifiable, Equatable {
        enum Source: Equatable {
            case match(AutocompleteMatch)
            case tab(SidebarTab)
        }

        let source: Source

        var kind: AutocompleteMatch.Kind? {
            if case .match(let match) = source { match.kind } else { nil }
        }
        var isTab: Bool { kind == nil }
        var isHistory: Bool { kind == .historyURL || kind == .historyTitle }
        var isNavigation: Bool { isTab || isHistory || kind == .urlWhatYouTyped || kind == .navSuggest }

        var url: URL? {
            switch source {
            case .match(let match): match.url
            case .tab(let tab): tab.url
            }
        }

        var title: String {
            switch source {
            case .tab(let tab): tab.displayTitle
            case .match(let match):
                isHistory || kind == .navSuggest
                    ? (match.description.isEmpty ? match.contents : match.description) : match.contents
            }
        }

        /// As ASE2's `DedupKey`: a search by its text and a page by its readable URL, with a tab apart from its
        /// page; ASE2 makes those two one row after the sort.
        var id: String {
            let address = CommandBarRanking.readable(url).lowercased()
            return isTab ? "tab " + address : isNavigation ? "url " + address : "search " + title.lowercased()
        }
    }

    let destination: Destination
    let autocomplete: any Autocomplete
    /// The page ⌘L edits, prefilled and selected as Arc does.
    let currentURL: URL?
    /// What the user typed; the field may show more.
    private(set) var text: String
    /// Ranked once for each change of the text, of Chromium's answer and of the Space's tabs.
    private(set) var rows: [Row] = []
    /// The highlighted row below the top one. Arc keeps an index, `currentHighlightedResultIndex`; what it does
    /// when a later answer re-ranks the rows wasn't traced. Oa's own: the highlight stays on its row.
    private var selectedKey: String?
    private var edited = false
    /// Chromium's rule: no completion after a deletion, unless the selection is a caret at the end, or while an
    /// input method composes, until the next typing.
    private var suppressesInline = false
    /// The user's selection in the field, in UTF-16 code units.
    private var selection: NSRange
    /// A completion or a row's text that stays in the field once the user moves the caret or selects in it. As Arc:
    /// the query and the rows stay those of what was typed until the next edit, which takes the field's text.
    private var acceptedText: String?
    @ObservationIgnored private let profileID: UUID
    @ObservationIgnored private let picks: CommandBarPicks
    @ObservationIgnored private let tabs: () -> [CommandBarRanking.Tab]
    @ObservationIgnored private var startedFresh = false
    /// As Arc's `pendingSelection`: Return pressed before Chromium answered the text, with its modifiers.
    @ObservationIgnored private var pendingReturn: NSEvent.ModifierFlags?
    @ObservationIgnored var perform: (Action) -> Void = { _ in }

    init(
        destination: Destination, autocomplete: any Autocomplete, currentURL: URL?, profileID: UUID,
        picks: CommandBarPicks, tabs: @escaping () -> [CommandBarRanking.Tab]
    ) {
        self.destination = destination
        self.autocomplete = autocomplete
        self.currentURL = currentURL
        self.profileID = profileID
        self.picks = picks
        self.tabs = tabs
        let text = currentURL?.absoluteString ?? ""
        self.text = text
        selection = NSRange(location: text.utf16.count, length: 0)
        if !text.isEmpty { start(preventsInlineAutocomplete: true) }
        rank()
    }

    var selectedIndex: Int {
        selectedKey.flatMap { key in rows.firstIndex { $0.id == key } } ?? 0
    }

    func select(_ index: Int) {
        selectedKey = index > 0 && rows.indices.contains(index) ? rows[index].id : nil
        acceptedText = nil
    }

    func moveSelection(_ offset: Int) {
        guard !rows.isEmpty else { return }
        select(min(max(selectedIndex + offset, 0), rows.count - 1))
    }

    struct FieldText: Equatable {
        var string: String
        var selection: NSRange
    }

    /// As Arc's field: ⌘L's URL all selected until the first edit or arrow; the typed text with the top row's
    /// completion selected after it; on another row, a search's text with the untyped rest selected, a page's URL,
    /// or for a tab the typed text.
    var field: FieldText {
        if let acceptedText { return FieldText(string: acceptedText, selection: clamped(selection, to: acceptedText)) }
        let typed = (text as NSString).length
        if !edited, destination == .currentTab, selectedKey == nil {
            return FieldText(string: text, selection: NSRange(0..<typed))
        }
        let index = selectedIndex
        if index > 0 {
            let row = rows[index]
            guard case .match(let match) = row.source else {
                return FieldText(string: text, selection: NSRange(location: typed, length: 0))
            }
            if row.isNavigation {
                let length = (match.fillIntoEdit as NSString).length
                return FieldText(string: match.fillIntoEdit, selection: NSRange(location: length, length: 0))
            }
            // In the suggestion's own units: an equivalent prefix can be shorter or longer than what was typed.
            let contents = match.contents as NSString
            let prefix = contents.range(of: text, options: [.anchored, .caseInsensitive])
            let rest = prefix.location == NSNotFound ? contents.length : NSMaxRange(prefix)
            return FieldText(string: match.contents, selection: NSRange(rest..<contents.length))
        }
        if !suppressesInline, let completion = completion(of: rows.first) {
            let length = (completion as NSString).length
            return FieldText(string: text + completion, selection: NSRange(location: typed, length: length))
        }
        return FieldText(string: text, selection: clamped(selection, to: text))
    }

    private func clamped(_ range: NSRange, to string: String) -> NSRange {
        let length = (string as NSString).length
        let location = min(range.location, length)
        return NSRange(location: location, length: min(range.length, length - location))
    }

    /// Chromium's for its default match; for a tab, the rest of its readable URL, as Arc completed "loc" to an open
    /// tab's "localtest.me:8795/…".
    private func completion(of row: Row?) -> String? {
        switch row?.source {
        case .match(let match):
            guard autocomplete.input?.text == text, match.allowedToBeDefault, !match.inlineAutocompletion.isEmpty
            else { return nil }
            return match.inlineAutocompletion
        case .tab(let tab):
            let address = CommandBarRanking.readable(tab.url)
            guard !text.isEmpty, address.count > text.count, address.lowercased().hasPrefix(text.lowercased())
            else { return nil }
            return String(address.dropFirst(text.count))
        case nil: return nil
        }
    }

    /// `selection` is the field's, in UTF-16 code units.
    func edit(_ text: String, selection: NSRange, deleting: Bool, composing: Bool = false) {
        edited = true
        selectedKey = nil
        acceptedText = nil
        self.selection = selection
        suppressesInline = deleting || composing || selection.location < (text as NSString).length
        guard text != self.text else { return }
        self.text = text
        pendingReturn = nil
        if text.isEmpty { autocomplete.stop() } else { start(preventsInlineAutocomplete: suppressesInline) }
        rank()
    }

    /// The user moved the caret or selected text without an edit.
    func selectText(_ selection: NSRange, in string: String) {
        edited = true
        self.selection = selection
        acceptedText = string == text ? nil : string
        if acceptedText == nil, selection.location < (text as NSString).length { suppressesInline = true }
    }

    /// As Arc's ⇧⌦: a past search goes, while a page from history stays.
    func deleteSelectedRow() {
        guard rows.indices.contains(selectedIndex), case .match(let match) = rows[selectedIndex].source else { return }
        if match.kind == .searchHistory, match.isDeletable { autocomplete.delete(match) }
    }

    /// As Arc from ⌘T: ⌘ opens a new tab in the background; ⇧ is plain Return. From ⌘L, where Arc's ⌘Return wasn't
    /// tested, it does the same as Oa's own. ⌥ is Arc's Split View, which Oa doesn't have yet, so it is plain Return
    /// too, as Oa's own.
    func submit(_ modifiers: NSEvent.ModifierFlags) {
        guard text.isEmpty || autocomplete.input?.text == text else {
            pendingReturn = modifiers
            return
        }
        act(modifiers)
    }

    func answered() {
        rank()
        guard let modifiers = pendingReturn, autocomplete.input?.text == text else { return }
        pendingReturn = nil
        act(modifiers)
    }

    private func act(_ modifiers: NSEvent.ModifierFlags) {
        guard rows.indices.contains(selectedIndex) else { return }
        let row = rows[selectedIndex]
        if !text.isEmpty { picks.record(row.id, for: text, in: profileID) }
        switch row.source {
        case .tab(let tab): perform(.switchTo(tab.id))
        case .match(let match):
            if let url = match.url { perform(.open(url, background: modifiers.contains(.command))) }
        }
    }

    /// As Arc: open tabs only when the bar makes a new tab, as Switch to Tab.
    private func rank() {
        let ranked = CommandBarRanking.rank(
            query: text, matches: text.isEmpty ? [] : autocomplete.matches,
            additionalMatches: text.isEmpty ? [] : autocomplete.additionalMatches,
            tabs: destination == .newTab ? tabs() : [], lastPick: picks.pick(for: text, in: profileID), now: .now)
        if ranked != rows { rows = ranked }
    }

    private func start(preventsInlineAutocomplete: Bool) {
        autocomplete.start(
            AutocompleteInput(
                text: text, cursorPosition: min(selection.location, text.utf16.count),
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
        let rows = bar.rows
        let tabs = bar.destination == .newTab ? model.commandBarTabs : []
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { model.closeCommandBar() }
                card(rows)
                    .frame(width: min(Self.width, geometry.size.width - 32))
                    .padding(.top, geometry.size.height * Self.topFraction)
            }
        }
        .onChange(of: bar.autocomplete.input) { _, _ in bar.answered() }
        .onChange(of: bar.autocomplete.matches) { _, _ in bar.answered() }
        .onChange(of: bar.autocomplete.additionalMatches) { _, _ in bar.answered() }
        .onChange(of: tabs) { _, _ in bar.answered() }
    }

    private func card(_ rows: [CommandBar.Row]) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: icon(for: rows.indices.contains(bar.selectedIndex) ? rows[bar.selectedIndex] : nil))
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
                CommandBarField(bar: bar, model: model, isUnderDialog: model.dialog != nil)
                    .frame(height: 23)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            if !rows.isEmpty {
                Divider()
                list(rows)
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator))
        .shadow(color: .black.opacity(0.25), radius: 24, y: 8)
    }

    private func list(_ rows: [CommandBar.Row]) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        CommandBarRow(
                            row: row, icon: icon(for: row), favicon: favicon(for: row),
                            selected: index == bar.selectedIndex
                        )
                        .id(index)
                        .onTapGesture {
                            bar.select(index)
                            bar.submit(NSEvent.modifierFlags)
                        }
                    }
                }
                .padding(.horizontal, 8)
            }
            .frame(height: CGFloat(min(rows.count, Self.visibleRows)) * Self.rowHeight)
            .onChange(of: bar.selectedIndex) { _, index in proxy.scrollTo(index) }
        }
    }

    private func favicon(for row: CommandBar.Row) -> NSImage? {
        if case .tab(let tab) = row.source { model.favicon(for: tab) } else { nil }
    }

    private func icon(for row: CommandBar.Row?) -> String {
        switch row?.kind {
        case .historyURL, .historyTitle: "clock"
        case .searchWhatYouTyped, .searchHistory, .searchSuggest, .searchSuggestEntity, .searchOtherEngine:
            "magnifyingglass"
        case .urlWhatYouTyped, .navSuggest, nil: "globe"
        }
    }
}

private struct CommandBarRow: View {
    let row: CommandBar.Row
    let icon: String
    let favicon: NSImage?
    let selected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if let favicon {
                    Image(nsImage: favicon).resizable().scaledToFit()
                } else {
                    Image(systemName: icon).foregroundStyle(.secondary)
                }
            }
            .frame(width: 18, height: 18)
            Text(row.title)
                .lineLimit(1)
            if let address {
                Text("— " + address)
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if row.isTab {
                Text("Switch to Tab")
                    .foregroundStyle(.secondary)
                Image(systemName: "arrow.right")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: CommandBarView.rowHeight)
        .background(selected ? Color.accentColor.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
    }

    private var address: String? {
        row.isHistory || row.kind == .navSuggest ? row.url.map(CommandBarRanking.readable) : nil
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
            bar.edit(string, selection: selection, deleting: deleting, composing: editor?.hasMarkedText() == true)
        }

        @objc func selectionChanged(_ notification: Notification) {
            guard !isShowing, let field, let editor = notification.object as? NSTextView,
                editor === field.currentEditor(), !editor.hasMarkedText(), field.stringValue == shown.string
            else { return }
            let selection = editor.selectedRange()
            guard selection != shown.selection else { return }
            shown.selection = selection
            bar.selectText(selection, in: shown.string)
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.moveUp(_:)): bar.moveSelection(-1)
            case #selector(NSResponder.moveDown(_:)): bar.moveSelection(1)
            case #selector(NSResponder.insertNewline(_:)), #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)):
                bar.submit(NSApp.currentEvent?.modifierFlags ?? [])
            // ⌘Return and ⌘Enter on the keypad.
            case Selector(("noop:")) where [36, 76].contains(NSApp.currentEvent?.keyCode):
                bar.submit(NSApp.currentEvent?.modifierFlags ?? [])
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
