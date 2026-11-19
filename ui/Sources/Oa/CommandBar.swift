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

    /// One of Chromium's matches, or one of the profile's tabs as Arc's sidebar offers them.
    struct Row: Identifiable, Equatable {
        enum Source: Equatable {
            case match(AutocompleteMatch)
            case tab(CommandBarRanking.Tab)
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
            case .tab(let tab): tab.title
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
    /// As Arc's `scopedSearchType`: Site Search, where Chromium searches only this engine.
    private(set) var scope: SearchEngine?
    /// The text typed before Site Search, which Backspace puts back.
    @ObservationIgnored private var textBeforeScope = ""
    /// Ranked once for each change of the text, of Chromium's answer and of the Space's tabs.
    private(set) var rows: [Row] = []
    /// Oa's own: the highlight stays on its row when results change; Arc keeps a numeric position.
    private var selectedKey: String?
    private var edited = false
    /// Chromium's rule: no completion after a deletion, unless the selection is a caret at the end, or while an
    /// input method composes, until the next typing.
    private var suppressesInline = false
    /// The user's selection in the field, in UTF-16 code units.
    private var selection: NSRange
    /// Caret movement preserves the displayed text without changing the query, as Arc does.
    private var acceptedText: String?
    @ObservationIgnored private var lastSuggestedText: String?
    @ObservationIgnored private let profileID: UUID
    @ObservationIgnored private let picks: CommandBarPicks
    @ObservationIgnored private let tabs: () -> [CommandBarRanking.Tab]
    @ObservationIgnored private let searchEngines: () -> [SearchEngine]
    @ObservationIgnored private var startedFresh = false
    /// As Arc's `pendingSelection`: Return pressed before Chromium answered the text, with its modifiers.
    @ObservationIgnored private var pendingReturn: NSEvent.ModifierFlags?
    @ObservationIgnored var perform: (Action) -> Void = { _ in }

    init(
        destination: Destination, autocomplete: any Autocomplete, currentURL: URL?, profileID: UUID,
        picks: CommandBarPicks, searchEngines: @escaping () -> [SearchEngine],
        tabs: @escaping () -> [CommandBarRanking.Tab]
    ) {
        self.destination = destination
        self.autocomplete = autocomplete
        self.currentURL = currentURL
        self.profileID = profileID
        self.picks = picks
        self.tabs = tabs
        self.searchEngines = searchEngines
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
        lastSuggestedText = suggestedField.string
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
        return suggestedField
    }

    private var suggestedField: FieldText {
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
        acceptedText = string
    }

    /// As Arc's "Search YouTube · Tab": the typed text, not the field's, starts an active engine's keyword. The
    /// shortest keyword wins, then the engines' order.
    var siteSearchHint: SearchEngine? {
        guard scope == nil, !text.isEmpty else { return nil }
        let typed = text.lowercased()
        return searchEngines().filter { $0.keyword.lowercased().hasPrefix(typed) }
            .min { $0.keyword.count < $1.keyword.count }
    }

    /// As Arc's Tab: into the hinted Site Search with an empty query, or out of Site Search while its query is empty.
    func pressTab() {
        if scope != nil {
            if text.isEmpty { leaveScope(text: "", caret: 0) }
        } else if let engine = siteSearchHint {
            enterScope(engine)
        }
    }

    func enterScope(_ engine: SearchEngine) {
        textBeforeScope = text
        scope = engine
        replaceText("", caret: 0)
    }

    /// As Arc's Backspace at the field's start: out of Site Search, the text from before it joined to the query and
    /// the caret between them.
    func leaveScopeBackward() {
        let before = textBeforeScope
        leaveScope(text: before + text, caret: before.utf16.count)
    }

    /// As Arc's Escape: out of Site Search with the field cleared. False outside it.
    func cancelScope() -> Bool {
        guard scope != nil else { return false }
        leaveScope(text: "", caret: 0)
        return true
    }

    private func leaveScope(text: String, caret: Int) {
        scope = nil
        replaceText(text, caret: caret)
    }

    private func replaceText(_ text: String, caret: Int) {
        edited = true
        selectedKey = nil
        acceptedText = nil
        suppressesInline = true
        selection = NSRange(location: caret, length: 0)
        self.text = text
        pendingReturn = nil
        if text.isEmpty { autocomplete.stop() } else { start(preventsInlineAutocomplete: true) }
        rank()
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
        case .tab(let tab): perform(.switchTo(tab.tab.id))
        case .match(let match):
            if let url = match.url { perform(.open(url, background: modifiers.contains(.command))) }
        }
    }

    /// As Arc: open tabs only when the bar makes a new tab, as Switch to Tab. In Site Search only the engine's search
    /// for the text and its past searches, as Arc's `isEligibleInSiteSearch`.
    private func rank() {
        let answered = !text.isEmpty && autocomplete.input?.keyword == scope?.keyword
        func kept(_ matches: [AutocompleteMatch]) -> [AutocompleteMatch] {
            guard answered else { return [] }
            return scope == nil ? matches : matches.filter { [.searchOtherEngine, .searchHistory].contains($0.kind) }
        }
        let ranked = CommandBarRanking.rank(
            query: text, matches: kept(autocomplete.matches), additionalMatches: kept(autocomplete.additionalMatches),
            tabs: destination == .newTab && scope == nil ? tabs() : [],
            lastPick: picks.pick(for: text, in: profileID), now: .now)
        if ranked != rows { rows = ranked }
        let output = suggestedField.string
        guard output != lastSuggestedText else { return }
        // Arc removes duplicate outputs before checking the selection, so a rejected completion isn't replayed.
        lastSuggestedText = output
        if let acceptedText, !suppressesInline,
            NSMaxRange(clamped(selection, to: acceptedText)) == (acceptedText as NSString).length
        {
            self.acceptedText = nil
        }
    }

    private func start(preventsInlineAutocomplete: Bool) {
        autocomplete.start(
            AutocompleteInput(
                text: text, cursorPosition: min(selection.location, text.utf16.count),
                preventsInlineAutocomplete: preventsInlineAutocomplete, startsFresh: !startedFresh,
                keyword: scope?.keyword, currentURL: destination == .currentTab ? currentURL : nil))
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

    /// As Arc's `autoActivatedEngineURLToPrimaryColor`, by the engine's URL; any other engine takes the row
    /// highlight's colour.
    private var scopeColor: Color {
        guard let scope = bar.scope,
            let site = SearchEngine.enginesToAutoActivate.first(where: { $0.engine.url == scope.url })
        else { return .accentColor }
        return Color(nsColor: srgb(site.color))
    }

    private func card(_ rows: [CommandBar.Row]) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                if let scope = bar.scope {
                    Image(systemName: "magnifyingglass")
                        .frame(width: 18)
                    // As measured in Arc: 13 pt from the icon, the field 11.5 pt after it.
                    SiteSearchPill(name: scope.name, color: scopeColor)
                        .padding(.leading, 3)
                        .padding(.trailing, 1.5)
                } else {
                    Image(
                        systemName: icon(for: rows.indices.contains(bar.selectedIndex) ? rows[bar.selectedIndex] : nil)
                    )
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
                }
                CommandBarField(bar: bar, model: model, isUnderDialog: model.dialog != nil)
                    .frame(height: 23)
                if let hint = bar.siteSearchHint {
                    SiteSearchHint(name: hint.name) { bar.enterScope(hint) }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            if !rows.isEmpty {
                // As measured in Arc: a 1 pt line 12 pt in from the card's sides, 6 pt above the first row.
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(height: 1)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 6)
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
                            selected: index == bar.selectedIndex, tint: bar.scope == nil ? nil : scopeColor
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
        if case .tab(let tab) = row.source { model.favicon(for: tab.tab) } else { nil }
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
    /// As Arc in Site Search: the highlight in the pill's colour, with white text.
    let tint: Color?

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if let favicon {
                    Image(nsImage: favicon).resizable().scaledToFit()
                } else {
                    Image(systemName: icon).foregroundStyle(
                        isTinted ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
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
            if case .tab(let tab) = row.source {
                // As Arc: a tab of another Space names its Space; the arrow beside it is Oa's own.
                Text(tab.spaceName ?? "Switch to Tab")
                    .foregroundStyle(.secondary)
                Image(systemName: "arrow.right")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: CommandBarView.rowHeight)
        .foregroundStyle(isTinted ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
        .background(
            selected ? tint ?? Color.accentColor.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 8)
        )
        .contentShape(Rectangle())
    }

    private var isTinted: Bool { selected && tint != nil }

    private var address: String? {
        row.isHistory || row.kind == .navSuggest ? row.url.map(CommandBarRanking.readable) : nil
    }
}

/// As measured in Arc: a 24 pt capsule in the engine's colour, glowing about 5 pt around, with its name in white.
private struct SiteSearchPill: View {
    let name: String
    let color: Color

    var body: some View {
        Text(name)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 9)
            .frame(height: 24)
            .background(color, in: Capsule())
            .shadow(color: color.opacity(0.35), radius: 5)
    }
}

/// As measured in Arc: "Search YouTube" with a 30 × 24 pt "Tab" key cap; a click enters Site Search as Tab does.
private struct SiteSearchHint: View {
    private static let label = Color(nsColor: dynamic(0xA8A7A8, 0x656565))
    private static let keyFill = Color(nsColor: dynamic(0xEEEDEE, 0x252525))
    private static let keyText = Color(nsColor: dynamic(0x777677, 0xB5B5B5))

    let name: String
    let enter: () -> Void

    var body: some View {
        Button(action: enter) {
            HStack(spacing: 8) {
                Text("Search \(name)")
                    .foregroundStyle(Self.label)
                Text("Tab")
                    .font(.system(size: 12))
                    .foregroundStyle(Self.keyText)
                    .frame(width: 30, height: 24)
                    .background(Self.keyFill, in: RoundedRectangle(cornerRadius: 4))
            }
            .font(.system(size: 14))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Search \(name), Tab")
    }
}

private func srgb(_ hex: UInt32) -> NSColor {
    NSColor(
        srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}

private func dynamic(_ light: UInt32, _ dark: UInt32) -> NSColor {
    NSColor(name: nil) { $0.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? srgb(dark) : srgb(light) }
}

/// An AppKit field, which a SwiftUI one can't be: it takes focus over a web page, selects an inline completion and
/// reports the caret, the arrow keys, Return, Esc, Tab, Backspace at its start and ⇧⌦.
private struct CommandBarField: NSViewRepresentable {
    let bar: CommandBar
    let model: WindowModel
    /// As Arc: a JavaScript dialog keeps the keys while the bar is open behind it.
    let isUnderDialog: Bool

    func makeCoordinator() -> Coordinator { Coordinator(bar: bar, model: model) }

    private var placeholder: String { bar.scope == nil ? "Search or Enter URL…" : "Search…" }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 17)
        field.placeholderString = placeholder
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
        field.placeholderString = placeholder
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
            case #selector(NSResponder.cancelOperation(_:)): if !bar.cancelScope() { model.closeCommandBar() }
            case #selector(NSResponder.insertTab(_:)): bar.pressTab()
            case #selector(NSResponder.deleteBackward(_:))
            where bar.scope != nil && textView.selectedRange() == NSRange(location: 0, length: 0):
                bar.leaveScopeBackward()
            case #selector(NSResponder.deleteForward(_:))
            where NSApp.currentEvent?.modifierFlags.contains(.shift) == true:
                bar.deleteSelectedRow()
            default: return false
            }
            return true
        }
    }
}
