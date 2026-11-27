import Foundation
import Observation

enum FlyoutSource: String, CaseIterable {
    case captures, downloads

    var title: String {
        switch self {
        case .captures: "Oa Captures"
        case .downloads: "Downloads"
        }
    }
}

/// As Arc's `StorableHome.json`: the Library section last shown, one for the app, kept across launches.
@MainActor
@Observable
final class StorableHome {
    private struct Stored: Codable {
        var lastSelectedHomePage: LibrarySection
        var flyoutSources: [String]?
    }

    @ObservationIgnored private let url: URL
    /// Downloads until a section is chosen, Oa's own: Arc's first value wasn't traced.
    var lastSelectedHomePage: LibrarySection {
        didSet { if oldValue != lastSelectedHomePage { save() } }
    }
    var flyoutSources: Set<FlyoutSource> {
        didSet { if oldValue != flyoutSources { save() } }
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let stored = Stored(
            lastSelectedHomePage: lastSelectedHomePage,
            flyoutSources: FlyoutSource.allCases.filter(flyoutSources.contains).map(\.rawValue))
        try? encoder.encode(stored).write(to: url, options: .atomic)
    }

    init(directory: URL) {
        url = directory.appendingPathComponent("home.json")
        let stored = (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(Stored.self, from: $0) }
        lastSelectedHomePage = stored?.lastSelectedHomePage ?? .downloads
        flyoutSources =
            stored?.flyoutSources.map { Set($0.compactMap(FlyoutSource.init(rawValue:))) } ?? Set(FlyoutSource.allCases)
    }
}
