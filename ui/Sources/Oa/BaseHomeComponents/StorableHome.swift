import Foundation
import Observation

enum FlyoutSource: String, CaseIterable, Codable {
    case documents, desktop, screenshots, captures, downloads

    var title: String {
        switch self {
        case .documents: "Documents"
        case .desktop: "Desktop"
        case .screenshots: "Screenshots"
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
        var flyoutSources: Set<FlyoutSource>?
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
        let stored = Stored(lastSelectedHomePage: lastSelectedHomePage, flyoutSources: flyoutSources)
        try? encoder.encode(stored).write(to: url, options: .atomic)
    }

    init(directory: URL) {
        url = directory.appendingPathComponent("home.json")
        let stored = (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(Stored.self, from: $0) }
        lastSelectedHomePage = stored?.lastSelectedHomePage ?? .downloads
        flyoutSources = stored?.flyoutSources ?? Set(FlyoutSource.allCases)
    }
}
