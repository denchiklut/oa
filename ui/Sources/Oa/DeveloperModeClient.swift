import Foundation
import Observation

@MainActor
@Observable
final class DeveloperModeClient {
    private struct Hosts: Codable {
        var enabledHosts: Set<String> = []
        var disabledDefaultHosts: Set<String> = []
    }

    private struct Stored: Codable {
        var version = 1
        var state = Hosts()
    }

    private let file: URL
    private var stored: Stored

    init(directory: URL) {
        file = directory.appendingPathComponent("StorableDeveloperModeState.json")
        stored = (try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode(Stored.self, from: $0) } ?? Stored()
    }

    func isEnabled(for url: URL?) -> Bool {
        guard let host = url?.host()?.lowercased() else { return false }
        return stored.state.enabledHosts.contains(host)
            || (isDefault(host) && !stored.state.disabledDefaultHosts.contains(host))
    }

    func toggle(for url: URL?) {
        guard let host = url?.host()?.lowercased(), !host.isEmpty else { return }
        var next = stored
        if isEnabled(for: url) {
            next.state.enabledHosts.remove(host)
            if isDefault(host) { next.state.disabledDefaultHosts.insert(host) }
        } else if isDefault(host) {
            next.state.disabledDefaultHosts.remove(host)
        } else {
            next.state.enabledHosts.insert(host)
        }
        do {
            try FileManager.default.createDirectory(
                at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(next).write(to: file, options: .atomic)
            stored = next
        } catch {
            NSLog("Could not save Developer Mode settings: %@", error.localizedDescription)
        }
    }

    private func isDefault(_ host: String) -> Bool {
        host == "localhost" || host == "127.0.0.1" || host.hasSuffix(".localhost") || host.hasSuffix(".127.0.0.1")
    }
}
