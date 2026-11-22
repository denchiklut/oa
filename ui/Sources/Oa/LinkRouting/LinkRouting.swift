import Foundation

enum LinkSourceTextMatchingStyle: Codable, CaseIterable, Hashable {
    case matches
    case contains
}

struct LinkSourceComponent: Identifiable, Codable, Hashable {
    enum ComponentType: Codable, Hashable {
        case urlMatch(LinkSourceTextMatchingStyle, String)
    }

    var id = UUID()
    var componentType = ComponentType.urlMatch(.contains, "")

    func matches(_ url: URL) -> Bool {
        guard case .urlMatch(let style, let text) = componentType else { return false }
        let pattern = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pattern.isEmpty else { return false }
        switch style {
        case .contains:
            return url.absoluteString.localizedCaseInsensitiveContains(pattern)
        case .matches:
            // As seen in Arc: host and path, ignoring case, scheme, port, query, fragment and a trailing slash. A
            // pattern without a scheme is read as https, so "host:port" parses as a scheme and never matches.
            let parsed = URLComponents(string: pattern)
            guard let candidate = parsed?.scheme == nil ? URLComponents(string: "https://" + pattern) : parsed,
                let host = candidate.host, let actual = URLComponents(url: url, resolvingAgainstBaseURL: true)
            else { return false }
            return host.lowercased() == actual.host?.lowercased() && Self.path(of: candidate) == Self.path(of: actual)
        }
    }

    private static func path(of address: URLComponents) -> String {
        let path = address.path.lowercased()
        return path.hasSuffix("/") ? String(path.dropLast()) : path
    }
}

enum LinkDestination: Codable, Hashable {
    enum ProfileDestination: Codable, Hashable {
        /// Oa's profile ID where Arc stores its `Profile`. Arc's menu offers no profile, so neither does Oa's.
        case profile(UUID)
        case space(UUID)
        case mostRecent
    }

    case space(ProfileDestination)
    case littleArc(ProfileDestination)

    /// Arc opens Little Arc for `littleArc`; Oa has none, so it opens where the inner destination would.
    var target: ProfileDestination {
        switch self {
        case .space(let destination), .littleArc(let destination): destination
        }
    }
}

struct LinkMatchingRule: Identifiable, Codable, Hashable {
    var id = UUID()
    var sourceComponents = [LinkSourceComponent()]
    var destination = LinkDestination.space(.mostRecent)

    func matches(_ url: URL) -> Bool {
        sourceComponents.contains { $0.matches(url) }
    }
}

/// As Arc's `StorableLinkRouting.json`, in its nesting.
struct StorableLinkRoutingState: Codable, Hashable {
    var version = 1
    var rules: [LinkMatchingRule] = []
    var defaultDestination = LinkDestination.space(.mostRecent)

    /// As seen in Arc: the first matching route in list order.
    func rule(for url: URL?) -> LinkMatchingRule? {
        guard let url, ["http", "https"].contains(url.scheme?.lowercased()) else { return nil }
        return rules.first { $0.matches(url) }
    }
}
