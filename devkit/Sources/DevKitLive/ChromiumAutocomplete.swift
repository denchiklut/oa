import DevKit
import Foundation
import Observation

/// Chromium's omnibox through OaCore, with Chromium's matches mapped to ADK's kinds as ADK's `ChromiumBrowser` does.
@MainActor
@Observable
final class ChromiumAutocomplete: Autocomplete {
    private(set) var matches: [AutocompleteMatch] = []
    private(set) var additionalMatches: [AutocompleteMatch] = []
    private(set) var input: AutocompleteInput?
    private(set) var isDone = true
    @ObservationIgnored private let core: CoreAutocomplete?
    /// As ADK's `DeletableAutocompleteMatches`: the engine's match behind each of the combined result's.
    @ObservationIgnored private var deletable: [Int: CoreAutocompleteMatch] = [:]

    init(core: CoreAutocomplete?) { self.core = core }

    func start(_ input: AutocompleteInput) {
        core?.start(
            text: input.text, cursorPosition: UInt(max(0, input.cursorPosition)),
            preventInlineAutocomplete: input.preventsInlineAutocomplete, startFresh: input.startsFresh,
            keyword: input.keyword, currentURL: input.currentURL
        ) { [weak self] object, done in
            MainActor.assumeIsolated {
                self?.answer(input, unsafeBitCast(object, to: CoreAutocompleteResult.self), done: done)
            }
        }
    }

    func stop() { core?.stop() }

    func delete(_ match: AutocompleteMatch) {
        if let found = deletable[match.id] { core?.delete(found) }
    }

    /// Chromium records the last visit only as "N hours ago".
    private static func lastVisited(_ text: String) -> Date? {
        guard let hours = text.split(separator: " ").first.flatMap({ Int($0) }) else { return nil }
        return Date(timeIntervalSinceNow: -Double(hours) * 3600)
    }

    private func answer(_ input: AutocompleteInput, _ result: CoreAutocompleteResult, done: Bool) {
        var combined: [AutocompleteMatch] = []
        var additional: [AutocompleteMatch] = []
        deletable = [:]
        func match(_ core: CoreAutocompleteMatch, id: Int, rank: Int?) -> AutocompleteMatch? {
            guard let kind = AutocompleteMatch.Kind(rawValue: core.type) else { return nil }
            return AutocompleteMatch(
                id: id, kind: kind, contents: core.contents, description: core.matchDescription,
                url: core.destinationURL, fillIntoEdit: core.fillIntoEdit,
                inlineAutocompletion: core.inlineAutocompletion, relevance: core.relevance,
                allowedToBeDefault: core.allowedToBeDefault, isDeletable: core.isDeletable, chromiumRank: rank,
                typedCount: core.additionalInfo["typed count"].flatMap { Int($0) },
                visitCount: core.additionalInfo["visit count"].flatMap { Int($0) },
                lastVisited: core.additionalInfo["last visit"].flatMap(Self.lastVisited))
        }
        for (index, object) in result.combinedMatches.enumerated() {
            let core = unsafeBitCast(object, to: CoreAutocompleteMatch.self)
            guard let match = match(core, id: combined.count, rank: index + 1) else { continue }
            if match.isDeletable { deletable[match.id] = core }
            combined.append(match)
        }
        // As ADK: a provider's match kept from the previous result isn't an additional result.
        for object in result.perProviderMatches {
            let core = unsafeBitCast(object, to: CoreAutocompleteMatch.self)
            guard !core.isFromPrevious, let match = match(core, id: combined.count + additional.count, rank: nil)
            else { continue }
            additional.append(match)
        }
        if combined != matches { matches = combined }
        if additional != additionalMatches { additionalMatches = additional }
        if input != self.input { self.input = input }
        if done != isDone { isDone = done }
    }
}
