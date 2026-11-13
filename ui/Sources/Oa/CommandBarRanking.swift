import DevKit
import Foundation

/// Arc's ASE2 ranking with its compiled-in constants (Arc 1.172.2): every row gets all of ASE2's features, each is
/// z-normalised over the query's rows, categories are weighted means, and boosts join the final weighted mean.
/// Features Oa has no source for keep ASE2's defaults, which normalise to 0, as in an Arc query without such rows.
enum CommandBarRanking {
    struct Tab: Equatable {
        let tab: SidebarTab
        /// As Arc's `urlForTab`: the live page's, else the saved one.
        let url: URL
        /// The owning Space's, for a tab of another Space; Arc offers those only before anything is typed.
        let spaceName: String?
        /// When the bar's window last showed it, else when it was made there; nil for a tab the window never had.
        let activeAt: Date?
        let isVisible: Bool
        /// Pinned tabs and Favorites: folders above them; nil for the rest, as ASE2 gives unsaved items its default.
        let saveLevel: Int?

        var title: String { tab.title.isEmpty ? url.host() ?? readable(url) : tab.title }
    }

    struct Pick: Codable, Equatable {
        let key: String
        let selectedAt: Date
    }

    /// The `maxSuggestions` Arc's bar gives ASE2. Where Arc cuts the list wasn't traced, so the cut after ranking is
    /// Oa's own.
    static let maxSuggestions = 15
    /// Arc's `maxNullStateNavigationSuggestions`.
    static let maxEmptySuggestions = 4

    private enum Category: CaseIterable { case match, importance, recency, chromium, save }

    private struct Weighting {
        let category: Category
        let weight: Double
        let lowerIsBetter: Bool
        let defaultValue: Double
    }

    private static let categoryWeights: [Category: Double] = [
        .match: 2, .importance: 10, .recency: 15, .chromium: 25, .save: 15,
    ]
    private static let archetypeWeight = 35.0

    private enum Feature: CaseIterable {
        case urlMatchScore, urlMatchPosition, urlMatchPercentage, titleMatchScore, titleMatchPosition
        case titleMatchPercentage, hotWordsScore, hotWordsPosition, hotWordsPercentage, fuzzySearchConfidence
        case frequencyEver, typedCountEver, mostVisitedRank, siteEngagementScore, globalSiteRank
        case typeTravelCandidateBump, lastNavigated, chromiumRank, chromiumRelevanceScore, saveLevel
    }

    private static let weightings: [Feature: Weighting] = [
        .urlMatchScore: Weighting(category: .match, weight: 1, lowerIsBetter: false, defaultValue: 0),
        .urlMatchPosition: Weighting(category: .match, weight: 1, lowerIsBetter: true, defaultValue: 30),
        .urlMatchPercentage: Weighting(category: .match, weight: 1, lowerIsBetter: false, defaultValue: 0),
        .titleMatchScore: Weighting(category: .match, weight: 0.5, lowerIsBetter: false, defaultValue: 0),
        .titleMatchPosition: Weighting(category: .match, weight: 0.5, lowerIsBetter: true, defaultValue: 30),
        .titleMatchPercentage: Weighting(category: .match, weight: 0.5, lowerIsBetter: false, defaultValue: 0),
        .hotWordsScore: Weighting(category: .match, weight: 1.5, lowerIsBetter: false, defaultValue: 0),
        .hotWordsPosition: Weighting(category: .match, weight: 1.5, lowerIsBetter: true, defaultValue: 30),
        .hotWordsPercentage: Weighting(category: .match, weight: 1.5, lowerIsBetter: false, defaultValue: 0),
        .fuzzySearchConfidence: Weighting(category: .match, weight: 20, lowerIsBetter: false, defaultValue: 0),
        .frequencyEver: Weighting(category: .importance, weight: 3, lowerIsBetter: false, defaultValue: 0),
        .typedCountEver: Weighting(category: .importance, weight: 4, lowerIsBetter: false, defaultValue: 0),
        .mostVisitedRank: Weighting(category: .importance, weight: 2, lowerIsBetter: true, defaultValue: 20),
        .siteEngagementScore: Weighting(category: .importance, weight: 2, lowerIsBetter: false, defaultValue: 0),
        .globalSiteRank: Weighting(category: .importance, weight: 1, lowerIsBetter: true, defaultValue: 505),
        .typeTravelCandidateBump: Weighting(category: .importance, weight: 1, lowerIsBetter: false, defaultValue: 0),
        .lastNavigated: Weighting(category: .recency, weight: 3, lowerIsBetter: true, defaultValue: 5_184_000),
        .chromiumRank: Weighting(category: .chromium, weight: 5, lowerIsBetter: true, defaultValue: 11),
        .chromiumRelevanceScore: Weighting(category: .chromium, weight: 3, lowerIsBetter: false, defaultValue: 0),
        .saveLevel: Weighting(category: .save, weight: 3, lowerIsBetter: true, defaultValue: 8),
    ]

    /// ASE2's boosts that Oa's rows can get, with its `BoostConfiguration` score and weight. `customTitlePrefix` is
    /// left out: an Oa tab has no custom title.
    private enum Boost {
        case exactBaseDomain, exactURL, baseDomain, chromiumSpecialSearchFunction
        case autocompleteDefault, veryRecentTabOrDocumentBoost, autocompleteSearchOnly

        var score: Double {
            switch self {
            case .exactBaseDomain: 15
            case .autocompleteSearchOnly: 2
            case .exactURL, .baseDomain, .chromiumSpecialSearchFunction, .autocompleteDefault,
                .veryRecentTabOrDocumentBoost:
                3
            }
        }

        var weight: Double {
            switch self {
            case .exactBaseDomain: 100
            case .exactURL, .baseDomain, .chromiumSpecialSearchFunction: 40
            case .autocompleteDefault, .veryRecentTabOrDocumentBoost, .autocompleteSearchOnly: 15
            }
        }
    }

    private static func archetype(_ row: CommandBar.Row) -> Double {
        switch row.source {
        case .tab: 101
        case .match(let match):
            switch match.kind {
            case .searchWhatYouTyped, .historyURL, .historyTitle, .urlWhatYouTyped: 100
            case .searchHistory: 99
            case .navSuggest: 96
            case .searchOtherEngine: 96.2
            case .searchSuggest, .searchSuggestEntity: 95
            }
        }
    }

    private struct Candidate {
        let row: CommandBar.Row
        var values: [Feature: Double] = [:]
        var boosts: [Boost] = []
        var score = 0.0

        func value(_ feature: Feature) -> Double { values[feature] ?? weightings[feature]!.defaultValue }
    }

    static func rank(
        query: String, matches: [AutocompleteMatch], additionalMatches: [AutocompleteMatch], tabs: [Tab],
        lastPick: Pick?, now: Date
    ) -> [CommandBar.Row] {
        guard !query.isEmpty else { return recent(tabs) }
        let lowered = query.lowercased()
        var candidates: [Candidate] = []
        // As Arc's sidebar provider: the Space's tabs and the profile's Favorites whose title or whole URL holds
        // the query.
        for tab in tabs where tab.spaceName == nil {
            guard
                tab.title.localizedStandardContains(query)
                    || tab.url.absoluteString.localizedStandardContains(query)
            else { continue }
            var candidate = Candidate(row: CommandBar.Row(source: .tab(tab)))
            // As Arc's `SidebarTab.timeLastActiveAt`.
            candidate.values[.lastNavigated] = tab.tab.viewedAt.map { now.timeIntervalSince($0) }
            candidate.values[.saveLevel] = tab.saveLevel.map(Double.init)
            candidates.append(candidate)
        }
        // As Arc's Chromium provider: of the additional results only pages and what was typed, without a rank.
        let additional = additionalMatches.filter {
            switch $0.kind {
            case .searchWhatYouTyped, .historyURL, .historyTitle, .urlWhatYouTyped, .navSuggest: true
            case .searchHistory, .searchSuggest, .searchSuggestEntity, .searchOtherEngine: false
            }
        }
        for match in matches + additional {
            var candidate = Candidate(row: CommandBar.Row(source: .match(match)))
            candidate.values[.chromiumRank] = match.chromiumRank.map(Double.init)
            candidate.values[.chromiumRelevanceScore] = Double(match.relevance)
            candidate.values[.frequencyEver] = match.visitCount.map(Double.init)
            candidate.values[.typedCountEver] = match.typedCount.map(Double.init)
            candidate.values[.lastNavigated] = match.lastVisited.map { now.timeIntervalSince($0) }
            candidates.append(candidate)
        }
        for index in candidates.indices {
            let row = candidates[index].row
            let title = String(row.title.lowercased().prefix(512))
            let url = row.isNavigation ? String(readable(row.url).lowercased().prefix(512)) : ""
            if !lowered.isEmpty {
                if let found = firstMatch(lowered, in: url) {
                    candidates[index].values[.urlMatchScore] = found.score
                    candidates[index].values[.urlMatchPosition] = found.position
                    candidates[index].values[.urlMatchPercentage] = Double(lowered.count) / Double(url.count)
                }
                if let found = firstMatch(lowered, in: title) {
                    candidates[index].values[.titleMatchScore] = found.score
                    candidates[index].values[.titleMatchPosition] = found.position
                    candidates[index].values[.titleMatchPercentage] = Double(lowered.count) / Double(title.count)
                }
            }
            candidates[index].boosts = boosts(for: candidates[index], query: lowered)
        }
        score(&candidates)
        var rows = dedup(candidates).sorted { $0.score > $1.score }
        applyPostSortRules(&rows, query: query, lastPick: lastPick, now: now)
        return rows.prefix(maxSuggestions).map(\.row)
    }

    /// As Arc's null state, which ASE2 never scores: the tabs the window has shown or made, latest first, then the
    /// rest by their own last view, one row for an address. Arc then adds most visited sites and its onboarding
    /// links, which Oa doesn't have; a tab never viewed has a creation date in Arc, and comes last here as Oa's own.
    private static func recent(_ tabs: [Tab]) -> [CommandBar.Row] {
        let shown = tabs.filter { $0.activeAt != nil }.sorted { $0.activeAt! > $1.activeAt! }
        let rest = tabs.filter { $0.activeAt == nil }
            .sorted { $0.tab.viewedAt ?? .distantPast > $1.tab.viewedAt ?? .distantPast }
        var addresses: Set<String> = []
        let rows = (shown + rest).map { CommandBar.Row(source: .tab($0)) }.filter { addresses.insert($0.id).inserted }
        return Array(rows.prefix(maxEmptySuggestions))
    }

    private static func score(_ candidates: inout [Candidate]) {
        guard !candidates.isEmpty else { return }
        func z(_ values: [Double]) -> [Double] {
            let mean = values.reduce(0, +) / Double(values.count)
            let deviation = (values.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(values.count)).squareRoot()
            return values.map { deviation == 0 ? 0 : ($0 - mean) / deviation }
        }
        let archetypes = z(candidates.map { archetype($0.row) })
        var normalised: [Feature: [Double]] = [:]
        for feature in Feature.allCases {
            let values = z(candidates.map { $0.value(feature) })
            normalised[feature] = weightings[feature]!.lowerIsBetter ? values.map { -$0 } : values
        }
        for index in candidates.indices {
            var entries: [(score: Double, weight: Double)] = [(archetypes[index], archetypeWeight)]
            for category in Category.allCases {
                let members = Feature.allCases.filter { weightings[$0]!.category == category }
                let total = members.reduce(0) { $0 + weightings[$1]!.weight }
                let sum = members.reduce(0) { $0 + weightings[$1]!.weight * normalised[$1]![index] }
                entries.append((sum / total, categoryWeights[category]!))
            }
            entries += candidates[index].boosts.map { ($0.score, $0.weight) }
            let weight = entries.reduce(0) { $0 + $1.weight }
            candidates[index].score = entries.reduce(0) { $0 + $1.score * $1.weight } / weight
        }
    }

    /// ASE2's `Boost.applies`, for a tab and for Chromium's rows: the URL boosts go to a tab and to a page (history,
    /// a typed URL, a navigation suggestion), the search-only one to a search. Of the three URL boosts a page gets at
    /// most one; a tab can get both `exactURL` and `baseDomain`.
    ///
    /// Two of its conditions are narrowed to Arc's live orders, which the decoded ones don't reproduce: the typed
    /// search gets no `autocompleteSearchOnly`, as a matching page always stood above it, and a navigation
    /// suggestion gets no `baseDomain`, as "quillbot.com" stood below the history rows for "quill".
    private static func boosts(for candidate: Candidate, query: String) -> [Boost] {
        let row = candidate.row
        var result: [Boost] = []
        if row.isTab, candidate.value(.lastNavigated) < 3600 { result.append(.veryRecentTabOrDocumentBoost) }
        guard !query.isEmpty else { return result }
        guard row.isNavigation else {
            if row.kind != .searchWhatYouTyped, row.title == query || row.title.hasPrefix(query) {
                result.append(.autocompleteSearchOnly)
            }
            if candidate.values[.chromiumRank] == 1, isSearchOperator(query) {
                result.append(.chromiumSpecialSearchFunction)
            }
            return result
        }
        guard let url = row.url else { return result }
        let address = readable(url).lowercased()
        // Arc compares a typed URL's own text, and any other page's readable URL.
        let completes = row.kind == .urlWhatYouTyped ? row.title : address
        if completes == query || completes.hasPrefix(query) { result.append(.autocompleteDefault) }
        guard query != "arc://", !query.hasPrefix("arc://") else { return result }
        let isExact = readable(query) == address || query == url.absoluteString
        let prefix = query.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let isBase =
            row.kind != .navSuggest && url.query() == nil
            && url.path().trimmingCharacters(in: CharacterSet(charactersIn: "/")).isEmpty
            && (url.absoluteString.hasPrefix(prefix) || address.hasPrefix(prefix))
        if isExact, isBase, !row.isTab { result.append(.exactBaseDomain) }
        if isExact, row.isTab || !isBase { result.append(.exactURL) }
        if isBase, row.isTab || !isExact { result.append(.baseDomain) }
        return result
    }

    private static func dedup(_ candidates: [Candidate]) -> [Candidate] {
        var kept: [String: Int] = [:]
        var result: [Candidate] = []
        for candidate in candidates {
            if let index = kept[candidate.row.id] {
                if candidate.score > result[index].score { result[index] = candidate }
            } else {
                kept[candidate.row.id] = result.count
                result.append(candidate)
            }
        }
        return result
    }

    private static func applyPostSortRules(_ rows: inout [Candidate], query: String, lastPick: Pick?, now: Date) {
        if rows.count > 1, case .tab(let tab) = rows[0].row.source, !rows[1].row.isTab, !tab.isVisible,
            rows[0].value(.lastNavigated) > 604_800
        {
            rows.swapAt(0, 1)
        }
        mergeTabsWithHistory(&rows)
        // ASE2's target index for the pick wasn't decoded; the top is Oa's reading of "promote".
        if let lastPick, now.timeIntervalSince(lastPick.selectedAt) <= 86_400,
            let index = rows.firstIndex(where: { $0.row.id == lastPick.key })
        {
            rows.insert(rows.remove(at: index), at: 0)
        }
        // ASE2's next pass moves the current page off the top when `derankCurrentItemURLEnabled` is set. In Arc's
        // live runs the current page stayed first, so the flag reads as off and the pass is left out.
        applyPreferredMaxRanks(&rows, query: query)
        // ASE2 asks that the query isn't a URL, which is read here as Chromium offering no typed URL, and its
        // target index wasn't decoded; Arc's live run put the typed search first.
        if query.contains(" "), !rows.contains(where: { $0.row.kind == .urlWhatYouTyped }),
            let index = rows.firstIndex(where: { $0.row.kind == .searchWhatYouTyped })
        {
            rows.insert(rows.remove(at: index), at: 0)
        }
    }

    /// ASE2's two passes after the sort: a history row gives its place to the open tab of its page, and the tab or
    /// history row that comes later goes. So a tab and its page are one row, the tab, at the better of their places.
    private static func mergeTabsWithHistory(_ rows: inout [Candidate]) {
        func address(_ candidate: Candidate) -> String { readable(candidate.row.url).lowercased() }
        func tabID(_ candidate: Candidate) -> UUID? {
            if case .tab(let tab) = candidate.row.source { tab.tab.id } else { nil }
        }
        let tabs = Dictionary(grouping: rows.filter(\.row.isTab), by: address)
        var placed: Set<UUID> = []
        rows = rows.compactMap { candidate in
            if let id = tabID(candidate) { return placed.insert(id).inserted ? candidate : nil }
            guard candidate.row.isHistory,
                let tab = tabs[address(candidate)]?.first(where: { tabID($0).map(placed.contains) == false }),
                let id = tabID(tab)
            else { return candidate }
            placed.insert(id)
            return tab
        }
        var shown: Set<String> = []
        rows = rows.filter { candidate in
            if candidate.row.isTab { shown.insert(address(candidate)) }
            return !candidate.row.isHistory || !shown.contains(address(candidate))
        }
    }

    /// ASE2's preferred max ranks as Arc's bar sets them for a window that isn't incognito: the typed search no
    /// lower than second, or first for a search operator, and a typed URL of four characters or more first. From the
    /// bottom up, a row below its rank moves up to it, once.
    private static func applyPreferredMaxRanks(_ rows: inout [Candidate], query: String) {
        let isOperator = isSearchOperator(query)
        func maxRank(_ row: CommandBar.Row) -> Int? {
            switch row.kind {
            case .searchWhatYouTyped: isOperator ? 0 : 1
            case .urlWhatYouTyped: !isOperator && query.count >= 4 ? 0 : nil
            default: nil
            }
        }
        var moved: Set<String> = []
        var index = rows.count - 1
        while index > 0 {
            if let rank = maxRank(rows[index].row), rank < index, moved.insert(rows[index].row.id).inserted {
                rows.insert(rows.remove(at: index), at: rank)
            } else {
                index -= 1
            }
        }
    }

    /// Arc's pattern for a search operator such as "site:example": two words around a colon, the first not a URL
    /// scheme.
    private static func isSearchOperator(_ query: String) -> Bool {
        searchOperator.firstMatch(in: query, range: NSRange(query.startIndex..., in: query)) != nil
    }

    private static let searchOperator = try! NSRegularExpression(
        pattern: #"^(?!aaas?|about|acap|adiumxtra|af[ps]|aim|apt|arc|attachment|aw|beshare|bitcoin|bolo|callto|cap|"#
            + #"chrome(?:-extension)?|cid|coap|com-eventbrite-attendee|content|crid|cvs|data|dav|dict|"#
            + #"dlna-(?:playcontainer|playsingle)|dns|doi|dtn|dvb|ed2k|facetime|feed|file|finger|fish|ftp|geo|gg|git|"#
            + #"gizmoproject|go|gopher|gtalk|h323|hcp|https?|iax|icap|icon|im|imap|info|ipn|ipp|irc[6s]?|"#
            + #"iris(?:\.beep|\.lwz|\.xpc|\.xpcs)?|itms|jar|javascript|jms|keyparc|lastfm|ldaps?|localhost|magnet|"#
            + #"mailto|maps|market|message|mid|mms|ms-help|msnim|msrps?|mtqp|mumble|mupdate|mvn|news|nfs|nih?|nntp|"#
            + #"notes|oid|opaquelocktoken|palm|paparazzi|platform|pop|pres|proxy|psyc|query|res(?:ource)?|rmi|rsync|"#
            + #"rtmp|rtsp|secondlife|service|session|sftp|sgn|shttp|sieve|sips?|skype|sm[bs]|snmp|soap\.beeps?|soldat|"#
            + #"spotify|ssh|steam|svn|tag|teamspeak|tel(?:net)?|tftp|things|thismessage|tip|tn3270|tv|udp|unreal|urn|"#
            + #"ut2004|vemmi|ventrilo|view-source|webcal|wss?|wtai|wyciwyg|xcon(?:-userid)?|xfire|xmlrpc\.beeps?|"#
            + #"xmpp|xri|ymsgr|z39\.50[rs])\w+:\w+$"#)

    /// Oa's own, as Arc's matcher wasn't decoded: 2 for a prefix, 1 at a word start, 0.5 inside a word.
    private static func firstMatch(_ query: String, in text: String) -> (score: Double, position: Double)? {
        guard let first = text.range(of: query) else { return nil }
        let position = Double(text.distance(from: text.startIndex, to: first.lowerBound))
        if first.lowerBound == text.startIndex { return (2, position) }
        var search = first.lowerBound
        while let found = text.range(of: query, range: search..<text.endIndex) {
            let before = text[text.index(before: found.lowerBound)]
            if !(before.isLetter || before.isNumber) { return (1, position) }
            search = text.index(after: found.lowerBound)
        }
        return (0.5, position)
    }

    /// As Arc's human-readable URL, which its boosts and dedup compare lowercased.
    static func readable(_ text: String) -> String {
        var text = Substring(text)
        if text.hasSuffix("?") { text.removeLast() }
        if text.hasSuffix("/") { text.removeLast() }
        if text.hasPrefix("https://") { text.removeFirst(8) } else if text.hasPrefix("http://") { text.removeFirst(7) }
        if text.hasPrefix("www.") { text.removeFirst(4) }
        return String(text)
    }

    static func readable(_ url: URL?) -> String { url.map { readable($0.absoluteString) } ?? "" }
}

/// As Arc's `queriesToSelectedArchetype` in `StorableCommandBarAdditionalRanking.json`: by profile, the row picked
/// for a query, which ASE2 promotes for 24 hours. Older picks no longer count, so they are dropped, and so are a
/// profile's when it is gone, both as Oa's own: Arc keeps them.
@MainActor
final class CommandBarPicks {
    private let url: URL
    /// By profile ID string, so the file is a JSON object.
    private var picks: [String: [String: CommandBarRanking.Pick]]

    init(directory: URL) {
        url = directory.appendingPathComponent("command-bar.json")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        picks =
            (try? Data(contentsOf: url)).flatMap {
                try? decoder.decode([String: [String: CommandBarRanking.Pick]].self, from: $0)
            } ?? [:]
    }

    func pick(for query: String, in profileID: UUID) -> CommandBarRanking.Pick? {
        picks[profileID.uuidString]?[query]
    }

    func record(_ key: String, for query: String, in profileID: UUID) {
        let now = Date.now
        picks[profileID.uuidString, default: [:]][query] = CommandBarRanking.Pick(key: key, selectedAt: now)
        picks = picks.mapValues { $0.filter { now.timeIntervalSince($1.selectedAt) <= 86_400 } }.filter { !$1.isEmpty }
        save()
    }

    func prune(keeping profileIDs: [UUID]) {
        let kept = Set(profileIDs.map(\.uuidString))
        guard picks.keys.contains(where: { !kept.contains($0) }) else { return }
        picks = picks.filter { kept.contains($0.key) }
        save()
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? encoder.encode(picks).write(to: url, options: .atomic)
    }
}
