import Foundation
import Observation

/// As Arc's `StorableHome.json`: the Library section last shown, one for the app, kept across launches.
@MainActor
@Observable
final class StorableHome {
    private struct Stored: Codable {
        var lastSelectedHomePage: LibrarySection
    }

    @ObservationIgnored private let url: URL
    /// Downloads until a section is chosen, Oa's own: Arc's first value wasn't traced.
    var lastSelectedHomePage: LibrarySection {
        didSet {
            guard lastSelectedHomePage != oldValue else { return }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try? encoder.encode(Stored(lastSelectedHomePage: lastSelectedHomePage)).write(to: url, options: .atomic)
        }
    }

    init(directory: URL) {
        url = directory.appendingPathComponent("home.json")
        let stored = (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(Stored.self, from: $0) }
        lastSelectedHomePage = stored?.lastSelectedHomePage ?? .downloads
    }
}
