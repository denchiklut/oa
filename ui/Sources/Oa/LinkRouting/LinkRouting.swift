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
            let address = pattern.contains("://") ? pattern : "\(url.scheme ?? "https")://\(pattern)"
            guard let candidate = URLComponents(string: address),
                let actual = URLComponents(url: url, resolvingAgainstBaseURL: true)
            else { return false }
            return Self.normalized(candidate) == Self.normalized(actual)
        }
    }

    private static func normalized(_ address: URLComponents) -> URLComponents {
        var address = address
        address.scheme = address.scheme?.lowercased()
        address.host = address.host?.lowercased()
        if address.path.isEmpty { address.path = "/" }
        return address
    }
}

enum LinkDestination: Codable, Hashable {
    enum ProfileDestination: Codable, Hashable {
        /// Oa's profile ID where Arc stores its `Profile`.
        case profile(UUID)
        case space(UUID)
        case mostRecent
    }

    case space(ProfileDestination)
    case littleArc(ProfileDestination)

    /// Oa has no Little Arc, so a `littleArc` destination opens where its Space or profile would.
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

    func destination(for url: URL?) -> LinkDestination.ProfileDestination {
        guard let url, ["http", "https"].contains(url.scheme?.lowercased()) else { return .mostRecent }
        return (rules.first { $0.matches(url) }?.destination ?? defaultDestination).target
    }
}
