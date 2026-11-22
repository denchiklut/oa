import Foundation
import Observation

/// Arc's `LinkRoutingClient`: one for the app, kept in its own file as Arc's.
@MainActor
@Observable
final class LinkRoutingClient {
    private(set) var state: StorableLinkRoutingState
    @ObservationIgnored private let url: URL

    init(directory: URL) {
        url = directory.appendingPathComponent("StorableLinkRouting.json")
        state =
            (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(StorableLinkRoutingState.self, from: $0) }
            ?? StorableLinkRoutingState()
    }

    func updateState(_ state: StorableLinkRoutingState) {
        guard state != self.state else { return }
        self.state = state
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? encoder.encode(state).write(to: url, options: .atomic)
    }
}
