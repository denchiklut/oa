import DevKit
import Foundation
import Observation

/// A sidebar item with its own identity. Its page arrives after the engine has created it.
@MainActor
@Observable
final class Tab: Identifiable {
    let id = UUID()
    var page: (any Page)?
    @ObservationIgnored var pendingURL: URL?

    var title: String {
        guard let title = page?.title, !title.isEmpty else { return "New Tab" }
        return title
    }
}
