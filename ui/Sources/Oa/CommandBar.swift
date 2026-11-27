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
        case openInSplitView(URL)
        case switchTo(UUID)
        case runCommand(CommandAction)
    }

    /// One of Chromium's matches, one of the profile's tabs, or a Type Travel command.
    struct Row: Identifiable, Equatable {
        enum Source: Equatable {
            case match(AutocompleteMatch)
            case tab(CommandBarRanking.Tab)
            case command(CommandAction)
        }

        let source: Source

        var kind: AutocompleteMatch.Kind? {
            if case .match(let match) = source { match.kind } else { nil }
        }
        var isTab: Bool {
            if case .tab = source { true } else { false }
        }
        var isCommand: Bool {
            if case .command = source { true } else { false }
        }
        var isHistory: Bool { kind == .historyURL || kind == .historyTitle }
        var isNavigation: Bool { isTab || isHistory || kind == .urlWhatYouTyped || kind == .navSuggest }

        var url: URL? {
            switch source {
            case .match(let match): match.url
            case .tab(let tab): tab.url
            case .command: nil
            }
        }

        var title: String {
            switch source {
            case .tab(let tab): tab.title
            case .command(let command): command.title
            case .match(let match):
                isHistory || kind == .navSuggest
                    ? (match.description.isEmpty ? match.contents : match.description) : match.contents
            }
        }

        /// As ASE2's `DedupKey`: a search by its text, a page by its readable URL, a tab apart from its page, and a
        /// command by its ID.
        var id: String {
            if case .command(let command) = source { return "command " + command.id }
            let address = CommandBarRanking.readable(url).lowercased()
            return isTab ? "tab " + address : isNavigation ? "url " + address : "search " + title.lowercased()
        }
    }

    struct ScopeColor: Equatable {
        var color: NSColor
        /// Arc's `isFromAutoActivatedList`.
        var isFromTable: Bool
    }

    let destination: Destination
    private(set) var autocomplete: any Autocomplete
    /// The page ⌘L edits, prefilled and selected as Arc does.
    let currentURL: URL?
    /// What the user typed; the field may show more.
    private(set) var text: String
    /// As Arc's `scopedSearchType`: Site Search, where Chromium searches only this engine.
    private(set) var scope: SearchEngine?
    /// As Arc's `scopedSearchColor`: nil until the Site Search has one, and for good when it has none.
    private(set) var scopeColor: ScopeColor?
    @ObservationIgnored private var scopeColorTask: Task<Void, Never>?
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
    private var context: any BrowserContext
    @ObservationIgnored private let picks: CommandBarPicks
    /// Off in an incognito window, which neither applies the profile's picks nor records its own, as seen in Arc.
    @ObservationIgnored private let usesPicks: Bool
    @ObservationIgnored private let tabs: () -> [CommandBarRanking.Tab]
    @ObservationIgnored private var commands: [CommandAction]
    @ObservationIgnored private var startedFresh = false
    /// As Arc's `pendingSelection`: Return pressed before Chromium answered the text, with its modifiers.
    @ObservationIgnored private var pendingReturn: NSEvent.ModifierFlags?
    @ObservationIgnored var perform: (Action) -> Void = { _ in }

    init(
        destination: Destination, autocomplete: any Autocomplete, currentURL: URL?, context: any BrowserContext,
        picks: CommandBarPicks, usesPicks: Bool = true, commands: [CommandAction] = [],
        tabs: @escaping () -> [CommandBarRanking.Tab]
    ) {
        self.destination = destination
        self.autocomplete = autocomplete
        self.currentURL = currentURL
        self.context = context
        self.picks = picks
        self.usesPicks = usesPicks
        self.commands = commands
        self.tabs = tabs
        let text = currentURL?.absoluteString ?? ""
        self.text = text
        selection = NSRange(location: text.utf16.count, length: 0)
        if !text.isEmpty { start(preventsInlineAutocomplete: true) }
        rank()
    }

    func changeSpace(to context: any BrowserContext, autocomplete: any Autocomplete, commands: [CommandAction]) {
        self.commands = commands
        pendingReturn = nil
        if self.context.id != context.id {
            self.autocomplete.stop()
            self.context = context
            self.autocomplete = autocomplete
            startedFresh = false
            if let scope {
                self.scope = context.preferences.activeSearchEngines.first { $0.keyword == scope.keyword }
                scopeColorTask?.cancel()
                scopeColor = nil
                if let engine = self.scope { loadScopeColor(for: engine) }
            }
            replaceText(text, caret: min(selection.location, text.utf16.count))
        } else {
            rank()
        }
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
            guard answersText, match.allowedToBeDefault, !match.inlineAutocompletion.isEmpty
            else { return nil }
            return match.inlineAutocompletion
        case .tab(let tab):
            let address = CommandBarRanking.readable(tab.url)
            guard !text.isEmpty, address.count > text.count, address.lowercased().hasPrefix(text.lowercased())
            else { return nil }
            return String(address.dropFirst(text.count))
        case .command, nil: return nil
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
        return context.preferences.activeSearchEngines.filter { $0.keyword.lowercased().hasPrefix(typed) }
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
        loadScopeColor(for: engine)
        replaceText("", caret: 0)
    }

    /// As Arc's reducer on entering a Site Search: its table's colour at once, else the favicon's when it comes.
    private func loadScopeColor(for engine: SearchEngine) {
        scopeColorTask?.cancel()
        scopeColor = engine.autoActivatedColor.map { ScopeColor(color: displayP3($0), isFromTable: true) }
        guard scopeColor == nil, let host = engine.emptySearchURL?.host() else { return }
        scopeColorTask = Task { [weak self, context] in
            guard let color = await context.siteSearchDominantColor(host: host), !Task.isCancelled else { return }
            self?.scopeColor = ScopeColor(color: color, isFromTable: false)
        }
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
        scopeColorTask?.cancel()
        scopeColor = nil
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

    /// As Arc from ⌘T: ⌘ opens a new tab in the background, ⌥ one in a split beside the current tab; ⇧ is plain
    /// Return. From ⌘L, where Arc's ⌘Return and ⌥Return weren't tested, ⌘ does the same and ⌥ is plain Return, as
    /// Oa's own.
    func submit(_ modifiers: NSEvent.ModifierFlags) {
        guard text.isEmpty || answersText else {
            pendingReturn = modifiers
            return
        }
        act(modifiers)
    }

    func answered() {
        rank()
        guard let modifiers = pendingReturn, answersText else { return }
        pendingReturn = nil
        act(modifiers)
    }

    private var answersText: Bool {
        autocomplete.input?.text == text && autocomplete.input?.keyword == scope?.keyword
    }

    private func act(_ modifiers: NSEvent.ModifierFlags) {
        guard rows.indices.contains(selectedIndex) else { return }
        let row = rows[selectedIndex]
        if !text.isEmpty, usesPicks { picks.record(row.id, for: text, in: context.id) }
        switch row.source {
        case .tab(let tab): perform(.switchTo(tab.tab.id))
        case .command(let command):
            if usesPicks { picks.recordCommand(command.id, in: context.id) }
            perform(.runCommand(command))
        case .match(let match):
            guard let url = match.url else { return }
            if modifiers.contains(.option), destination == .newTab {
                perform(.openInSplitView(url))
            } else {
                perform(.open(url, background: modifiers.contains(.command)))
            }
        }
    }

    /// As Arc: open tabs only when the bar makes a new tab, as Switch to Tab. Commands show for non-empty queries in
    /// both ⌘T and ⌘L outside Site Search. In Site Search only the engine's search for the text and its past searches,
    /// as Arc's `isEligibleInSiteSearch`.
    private func rank() {
        let answered = !text.isEmpty && autocomplete.input?.keyword == scope?.keyword
        func kept(_ matches: [AutocompleteMatch]) -> [AutocompleteMatch] {
            guard answered else { return [] }
            return scope == nil ? matches : matches.filter { [.searchOtherEngine, .searchHistory].contains($0.kind) }
        }
        let ranked = CommandBarRanking.rank(
            query: text, matches: kept(autocomplete.matches), additionalMatches: kept(autocomplete.additionalMatches),
            tabs: destination == .newTab && scope == nil ? tabs() : [],
            commands: scope == nil ? commands : [],
            commandUsage: usesPicks ? picks.commandUsage(in: context.id) : [:],
            lastPick: usesPicks ? picks.pick(for: text, in: context.id) : nil, now: .now)
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

/// Measured in Arc: a 766 pt card centred on the whole window, its top 169.5 pt above the window's middle (270 pt down
/// an 879 pt window, 256.5 down an 851 pt one), five 50 pt rows showing before the list scrolls.
struct CommandBarView: View {
    /// As seen in Arc: a Little window's bar is narrower and has a ✕, and before the window has a page the bar is
    /// the whole window.
    enum Presentation {
        case window, littleWindow, littleBar

        @MainActor var width: CGFloat { self == .window ? CommandBarView.width : LittleBrowserFrame.barSize.width }
    }

    static let width: CGFloat = 766
    static let rowHeight: CGFloat = 50
    static let visibleRows = 5
    static let topAboveMiddle: CGFloat = 169.5

    let model: WindowModel
    let bar: CommandBar
    /// The window theme's `focus`, which Arc's bar draws a Site Search without a colour in.
    let themeFocus: Color
    var presentation = Presentation.window
    @Environment(\.colorScheme) private var colorScheme
    @State private var bounces = 0.0
    @State private var glow: (id: UUID, color: Color)?

    var body: some View {
        let rows = bar.rows
        let tabs = bar.destination == .newTab ? model.commandBarTabs : []
        GeometryReader { geometry in
            let fills = presentation == .littleBar
            ZStack(alignment: .top) {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { model.closeCommandBar() }
                card(rows)
                    .background { if let glow { SiteSearchGlow(color: glow.color).id(glow.id) } }
                    .modifier(CommandBarBounce(count: fills ? 0 : bounces))
                    .frame(width: fills ? geometry.size.width : min(presentation.width, geometry.size.width - 32))
                    .padding(.top, fills ? 0 : max(geometry.size.height / 2 - Self.topAboveMiddle, 0))
            }
        }
        // As Arc: the bar bounces whenever it enters or leaves a Site Search.
        .onChange(of: bar.scope != nil) { _, _ in
            withAnimation(.linear(duration: CommandBarBounce.duration)) { bounces += 1 }
        }
        // As Arc: the glow plays on entry once the colour is known, so a favicon's starts when it arrives.
        .onChange(of: bar.scopeColor) { _, color in
            if let color { glow = (UUID(), Color(nsColor: color.color)) }
        }
        .task(id: glow?.id) {
            try? await Task.sleep(for: .seconds(SiteSearchGlow.duration))
            if !Task.isCancelled { glow = nil }
        }
        .onChange(of: bar.autocomplete.input) { _, _ in bar.answered() }
        .onChange(of: bar.autocomplete.matches) { _, _ in bar.answered() }
        .onChange(of: bar.autocomplete.additionalMatches) { _, _ in bar.answered() }
        .onChange(of: tabs) { _, _ in bar.answered() }
    }

    /// What Arc draws the pill and the scoped row in: its table's colour as it is, a favicon's colour as the
    /// `focus` of the theme that colour generates, and the window theme's `focus` without either.
    private var scopeFocus: Color {
        guard let scope = bar.scopeColor else { return themeFocus }
        if scope.isFromTable { return Color(nsColor: scope.color) }
        let palette = WindowTheme.PrimaryColorPalette(key: scope.color)
        return WindowTheme.SemanticColorPalette(palette, colorScheme == .dark ? .dark : .light).focus.color
    }

    /// As measured on Arc 1.174 over three themes, light and dark: the card and its inks go by the app's appearance,
    /// not the theme's, and only the chosen row takes the theme, its `focus`.
    private func card(_ rows: [CommandBar.Row]) -> some View {
        let isDark = colorScheme == .dark
        return VStack(spacing: 0) {
            HStack(spacing: 10) {
                if let scope = bar.scope {
                    Image(systemName: "magnifyingglass")
                        .frame(width: 18)
                    // As measured in Arc: 13 pt from the icon, the field 11.5 pt after it.
                    SiteSearchPill(name: scope.name, color: scopeFocus)
                        .padding(.leading, 3)
                        .padding(.trailing, 1.5)
                } else {
                    Image(
                        systemName: fieldIcon(rows.indices.contains(bar.selectedIndex) ? rows[bar.selectedIndex] : nil)
                    )
                    .frame(width: 18)
                }
                CommandBarField(bar: bar, model: model, isUnderDialog: model.dialog != nil, isDark: isDark)
                    .frame(height: 24)
                if let hint = bar.siteSearchHint {
                    SiteSearchHint(name: hint.name) { bar.enterScope(hint) }
                }
                if presentation != .window {
                    Button {
                        model.closeCommandBar()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .frame(width: 26, height: 26)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .opacity(0.5)
                    .accessibilityLabel("Close")
                }
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(isDark ? Color.white : .black)
            .padding(.leading, 23)
            .padding(.trailing, 16)
            .frame(height: 64)
            if !rows.isEmpty {
                // A hairline 12 pt in from the card's sides, 6 pt above the first row's fill.
                Rectangle()
                    .fill(CommandBarInk.color(isDark, 0.1, 0.1))
                    .frame(height: 0.5)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 4)
                list(rows)
                    .padding(.bottom, 9.5)
            }
        }
        .frame(maxHeight: presentation == .littleBar ? .infinity : nil, alignment: .top)
        // As Arc: `CommandBarConstants.cornerRadius` and the floating bar's shadow; the window's own where the bar
        // is the window.
        .modifier(
            PopoverBackgroundView(
                cornerRadius: presentation == .littleBar ? 0 : 12,
                shadowColor: .black.opacity(presentation == .littleBar ? 0 : 0.5), shadowRadius: 48, shadowY: 24))
    }

    private func list(_ rows: [CommandBar.Row]) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        CommandBarRow(
                            row: row, icon: icon(for: row), favicon: favicon(for: row),
                            selected: index == bar.selectedIndex, focus: scopeFocus
                        )
                        .id(index)
                        .onTapGesture {
                            bar.select(index)
                            bar.submit(NSEvent.modifierFlags)
                        }
                    }
                }
                .padding(.horizontal, 10)
            }
            .frame(height: CGFloat(min(rows.count, Self.visibleRows)) * Self.rowHeight)
            .onChange(of: bar.selectedIndex) { _, index in proxy.scrollTo(index) }
        }
    }

    private func favicon(for row: CommandBar.Row) -> NSImage? {
        if case .tab(let tab) = row.source { model.favicon(for: tab.tab) } else { nil }
    }

    /// As measured on Arc: the magnifier stays while the chosen row is an open tab or a command.
    private func fieldIcon(_ row: CommandBar.Row?) -> String {
        switch row?.source {
        case .tab, .command: "magnifyingglass"
        default: icon(for: row)
        }
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

/// Black over Arc's light card and white over its dark one, at the alphas measured there.
private enum CommandBarInk {
    static func color(_ isDark: Bool, _ light: Double, _ dark: Double) -> Color {
        isDark ? .white.opacity(dark) : .black.opacity(light)
    }
}

private struct CommandBarRow: View {
    let row: CommandBar.Row
    let icon: String
    let favicon: NSImage?
    let selected: Bool
    /// As Arc: the chosen row is filled with the theme's `focus`, or a Site Search's colour, under white text.
    let focus: Color
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let isDark = colorScheme == .dark
        let faint = selected ? Color.white : CommandBarInk.color(isDark, 0.33, 0.33)
        let box = RoundedRectangle(cornerRadius: 6, style: .continuous)
        HStack(spacing: 9) {
            Group {
                if case .command(let command) = row.source {
                    if let extIcon = command.extensionIcon {
                        Image(nsImage: extIcon).resizable().scaledToFit()
                            .frame(width: 16, height: 16)
                            .frame(width: 24, height: 24)
                            .background(selected ? Color.white : .clear, in: box)
                    } else {
                        Image(systemName: command.icon)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(selected ? focus : CommandBarInk.color(isDark, 0.65, 0.78))
                            .frame(width: 24, height: 24)
                            .background(selected ? Color.white : CommandBarInk.color(isDark, 0.06, 0.1), in: box)
                    }
                } else if let favicon {
                    // As Arc: the chosen row's favicon sits on a white tile.
                    Image(nsImage: favicon).resizable().scaledToFit()
                        .frame(width: 16, height: 16)
                        .frame(width: 24, height: 24)
                        .background(selected ? Color.white : .clear, in: box)
                } else {
                    Image(systemName: icon)
                        .foregroundStyle(selected ? Color.white : CommandBarInk.color(isDark, 0.5, 0.66))
                        .frame(width: 24, height: 24)
                }
            }
            Text(row.title)
                .lineLimit(1)
            if case .command(let command) = row.source, let capsule = command.capsule {
                HStack(spacing: 4) {
                    if let icon = capsule.icon {
                        SpaceIconGlyph(icon: icon)
                            .font(.system(size: 11, weight: .medium))
                    }
                    Text(capsule.title)
                        .lineLimit(1)
                }
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 7)
                .frame(height: 22)
                .background(selected ? Color.white.opacity(0.2) : CommandBarInk.color(isDark, 0.07, 0.12), in: box)
            }
            if let address {
                Text("— " + address)
                    .lineLimit(1)
                    .foregroundStyle(faint)
            }
            Spacer(minLength: 0)
            if case .tab(let tab) = row.source {
                // As Arc: a tab of another Space names its Space.
                Text(tab.spaceName ?? (tab.isSplitView ? "Switch to Split View" : "Switch to Tab"))
                    .foregroundStyle(faint)
                Image(systemName: "arrow.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(selected ? focus : CommandBarInk.color(isDark, 0.5, 0.66))
                    .frame(width: 24, height: 24)
                    .background(selected ? Color.white : CommandBarInk.color(isDark, 0.05, 0.05), in: box)
            } else if case .command(let command) = row.source, let shortcut = command.shortcut {
                Text(shortcut.symbols.joined())
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(selected ? Color.white : CommandBarInk.color(isDark, 0.55, 0.68))
                    .padding(.horizontal, 7)
                    .frame(height: 24)
                    .background(
                        selected ? Color.white.opacity(0.2) : CommandBarInk.color(isDark, 0.06, 0.1),
                        in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            }
        }
        .font(.system(size: 13, weight: .medium))
        .padding(.leading, 10)
        .padding(.trailing, 13)
        .frame(height: 46)
        .foregroundStyle(selected ? Color.white : CommandBarInk.color(isDark, 0.8, 0.8))
        .background(selected ? focus : .clear, in: RoundedRectangle(cornerRadius: 8))
        .frame(height: CommandBarView.rowHeight)
        .contentShape(Rectangle())
    }

    private var address: String? {
        row.isHistory || row.kind == .navSuggest ? row.url.map(CommandBarRanking.readable) : nil
    }
}

/// Arc's pill: 24 pt high with continuous 12 pt corners, its name in white, and an `NSShadow` of blur 8 one point
/// down in its colour at 0.3, which is a SwiftUI radius of 4.
private struct SiteSearchPill: View {
    let name: String
    let color: Color

    var body: some View {
        Text(name)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 9)
            .frame(height: 24)
            .background(color, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .shadow(color: color.opacity(0.3), radius: 4, y: 1)
    }
}

/// Arc's `arc_commandBarBounce`: a spring of damping ratio 0.9 and response 0.7 toward a scale of 0.95, cut off
/// after 0.1 s and played back, so the bar dips to about 0.988. `count` runs linearly from one bounce to the next.
private struct CommandBarBounce: GeometryEffect {
    static let duration = 0.2

    var count: Double

    var animatableData: Double {
        get { count }
        set { count = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        let progress = count - count.rounded(.down)
        let time = Self.duration / 2 * (1 - abs(2 * progress - 1))
        let frequency = 2 * Double.pi / 0.7
        let decay = 0.9 * frequency
        let damped = frequency * (1 - 0.9 * 0.9).squareRoot()
        let travelled = 1 - exp(-decay * time) * (cos(damped * time) + decay / damped * sin(damped * time))
        let scale = 1 - 0.05 * travelled
        return ProjectionTransform(
            CGAffineTransform(translationX: size.width / 2, y: size.height / 2).scaledBy(x: scale, y: scale)
                .translatedBy(x: -size.width / 2, y: -size.height / 2))
    }
}

/// Arc's glow on entering a Site Search: the colour as it is, behind the card and of its size, blurring out.
private struct SiteSearchGlow: View {
    static let duration = 1.2

    let color: Color
    @State private var faded = false

    var body: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(color)
            .blur(radius: faded ? 150 : 0)
            .opacity(faded ? 0 : 1)
            .onAppear { withAnimation(.easeOut(duration: Self.duration)) { faded = true } }
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

/// Arc reads its table's hex colours as Display P3: its YouTube red measures #FF0000 in the display's own space.
private func displayP3(_ hex: UInt32) -> NSColor {
    NSColor(
        displayP3Red: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}

private func dynamic(_ light: UInt32, _ dark: UInt32) -> NSColor {
    NSColor(name: nil) { $0.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? srgb(dark) : srgb(light) }
}

/// As Arc's `commandBarUndoManager`: the bar's typing has its own undo steps, apart from the window's.
private final class CommandBarTextField: NSTextField {
    private let commandBarUndoManager = UndoManager()

    override var undoManager: UndoManager? { commandBarUndoManager }
}

/// An AppKit field, which a SwiftUI one can't be: it takes focus over a web page, selects an inline completion and
/// reports the caret, the arrow keys, Return, Esc, Tab, Backspace at its start and ⇧⌦.
private struct CommandBarField: NSViewRepresentable {
    let bar: CommandBar
    let model: WindowModel
    /// As Arc: a JavaScript dialog keeps the keys while the bar is open behind it.
    let isUnderDialog: Bool
    let isDark: Bool

    func makeCoordinator() -> Coordinator { Coordinator(bar: bar, model: model) }

    private static let font = NSFont.systemFont(ofSize: 18, weight: .medium)

    private var placeholder: String { bar.scope == nil ? "Search or Enter URL…" : "Search…" }

    /// The card's light or dark is the app's, which the field's own colours must follow; the prompt as measured on
    /// Arc.
    private func style(_ field: NSTextField) {
        field.appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
        field.placeholderAttributedString = NSAttributedString(
            string: placeholder,
            attributes: [
                .font: Self.font,
                .foregroundColor: isDark ? NSColor.white.withAlphaComponent(0.55) : .black.withAlphaComponent(0.5),
            ])
    }

    func makeNSView(context: Context) -> NSTextField {
        let field = CommandBarTextField()
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = Self.font
        style(field)
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
        style(field)
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
