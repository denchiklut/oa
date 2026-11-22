import Foundation

struct LinkRouting: Codable {
    struct Route: Identifiable, Codable {
        enum Match: String, Codable, CaseIterable {
            case contains = "Contains"
            case equals = "Is equal to"
        }

        var id = UUID()
        var match = Match.contains
        var pattern = ""
        var spaceID: UUID?

        func matches(_ url: URL) -> Bool {
            let pattern = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !pattern.isEmpty else { return false }
            switch match {
            case .contains:
                return url.absoluteString.localizedCaseInsensitiveContains(pattern)
            case .equals:
                // Oa accepts addresses pasted with or without a scheme. Paths and queries keep their case.
                let address = pattern.contains("://") ? pattern : "\(url.scheme ?? "https")://\(pattern)"
                guard let candidate = URLComponents(string: address),
                    let actual = URLComponents(url: url, resolvingAgainstBaseURL: true)
                else { return false }
                return normalized(candidate) == normalized(actual)
            }
        }

        private func normalized(_ address: URLComponents) -> URLComponents {
            var address = address
            address.scheme = address.scheme?.lowercased()
            address.host = address.host?.lowercased()
            if address.path.isEmpty { address.path = "/" }
            return address
        }
    }

    var routes: [Route] = []
    var defaultSpaceID: UUID?

    // Oa uses the first matching rule in display order. A nil destination means Most Recent Space.
    func destination(for url: URL?, recent: UUID) -> UUID {
        guard let url, ["http", "https"].contains(url.scheme?.lowercased()) else { return recent }
        if let route = routes.first(where: { $0.matches(url) }) { return route.spaceID ?? recent }
        return defaultSpaceID ?? recent
    }
}
