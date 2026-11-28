import DevKit
import Foundation

struct GitHubPullRequest: Codable, Hashable {
    let url: URL
    let title: String

    static func repository(of url: URL) -> String {
        url.path.split(separator: "/").prefix(2).joined(separator: "/")
    }
}

enum GitHubPullRequestFilter: String, Codable, CaseIterable {
    case createdByMe, reviewRequests, teamReviewRequests

    var title: String {
        switch self {
        case .createdByMe: "Created by Me"
        case .reviewRequests: "Review Requests"
        case .teamReviewRequests: "Team Review Requests"
        }
    }
}

enum GitHubFolderError: Error, Codable, Hashable {
    case signedOut, singleSignOn(URL), unavailable

    var message: String {
        switch self {
        case .signedOut: "Sign back in to GitHub."
        case .singleSignOn: "Login with SSO to unlock this folder"
        case .unavailable: "We’re having trouble connecting to GitHub; click here to see your Pull Requests."
        }
    }

    var symbol: String {
        if case .singleSignOn = self { return "key" }
        return "exclamationmark.triangle"
    }

    var destination: URL {
        switch self {
        case .signedOut: URL(string: "https://github.com/login")!
        case .singleSignOn(let url): url
        case .unavailable: URL(string: "https://github.com/pulls")!
        }
    }
}

enum GitHubPullRequests {
    private static let github = URL(string: "https://github.com")!

    @MainActor
    static func fetch(_ filters: Set<GitHubPullRequestFilter>, in context: any BrowserContext) async throws
        -> [GitHubPullRequest]
    {
        var seen = Set<URL>()
        var result: [GitHubPullRequest] = []
        var searches: [(view: String, qualifier: String)] = []
        if filters.contains(.createdByMe) { searches.append(("authored", "author:@me involves:@me")) }
        switch (filters.contains(.reviewRequests), filters.contains(.teamReviewRequests)) {
        case (true, true): searches.append(("reviews", "review-requested:@me"))
        case (true, false): searches.append(("reviews", "user-review-requested:@me involves:@me"))
        case (false, true): searches.append(("reviews", "team-review-requested-user:@me"))
        case (false, false): break
        }
        for (view, qualifier) in searches {
            var path = "/pulls/" + view
            for number in 1...10 {
                try Task.checkCancellation()
                var request = URLComponents(url: github, resolvingAgainstBaseURL: false)!
                request.path = path
                request.queryItems = [
                    URLQueryItem(name: "q", value: "is:pr is:open sort:updated-desc \(qualifier)"),
                    URLQueryItem(name: "page", value: String(number)),
                ]
                guard var response = await context.loadDocument(at: request.url!) else {
                    throw GitHubFolderError.unavailable
                }
                // Older dashboards serve these searches at /pulls. Reissue the query if a redirect dropped it.
                if path != "/pulls", response.url.host == github.host,
                    response.status == 404 || (response.status == 200 && response.url.path == "/pulls")
                {
                    path = "/pulls"
                    request.path = path
                    guard let legacy = await context.loadDocument(at: request.url!) else {
                        throw GitHubFolderError.unavailable
                    }
                    response = legacy
                }
                let page = try await parse(response, path: path, number: number)
                result.append(contentsOf: page.items.filter { seen.insert($0.url).inserted })
                if !page.hasNext { break }
                guard number < 10 else { throw GitHubFolderError.unavailable }
            }
        }
        return result
    }

    private struct Page: Sendable {
        var items: [GitHubPullRequest]
        var hasNext: Bool
    }

    private struct Payload: Decodable {
        var pullsDashboardSurfaceContentRoute: Content?
        var pullsDashboardSurfaceLayoutRoute: Layout?

        struct Layout: Decodable {
            var sso_organizations: [Organization]?
            var sso: SSO?

            struct SSO: Decodable { var sso_organizations: [Organization]? }

            struct Organization: Decodable {
                let login: String

                init(from decoder: Decoder) throws {
                    let value = try decoder.singleValueContainer()
                    if let name = try? value.decode(String.self) {
                        login = name
                    } else {
                        struct Named: Decodable { let login: String }
                        login = try value.decode(Named.self).login
                    }
                }
            }
        }
        struct Content: Decodable {
            var results: [Row]
            var pageInfo: PageInfo?
        }
        struct Row: Decodable {
            var repoNameWithOwner: String
            var number: Int
            var title: String
        }
        struct PageInfo: Decodable { var totalPages: Int }
    }

    private struct Embedded: Decodable { var payload: Payload }

    private static func parse(_ response: ProfileDocument, path: String, number: Int) async throws -> Page {
        guard response.url.scheme == "https", response.url.host == "github.com" else {
            throw GitHubFolderError.unavailable
        }
        if response.status == 401 || (response.status == 200 && response.url.path == "/login") {
            throw GitHubFolderError.signedOut
        }
        if let sso = ssoURL(response.url.absoluteString) { throw GitHubFolderError.singleSignOn(sso) }
        guard response.status == 200, response.url.path == path, !response.body.isEmpty else {
            throw GitHubFolderError.unavailable
        }
        let document = try XMLDocument(
            data: response.body, options: [.documentTidyHTML, .nodeLoadExternalEntitiesNever])
        if let node = try document.nodes(
            forXPath:
                "//*[@data-testid='global-sso-banner' or contains(concat(' ',normalize-space(@class),' '),' flash ')]//a/@href | //a[starts-with(@href,'/orgs/') and contains(@href,'/sso')]/@href"
        )
        .compactMap({ $0.stringValue.flatMap(ssoURL) }).first {
            throw GitHubFolderError.singleSignOn(node)
        }
        let next = try document.nodes(
            forXPath: "//a[@rel='next' or contains(concat(' ',normalize-space(@class),' '),' next_page ')][@href]")
        var content: Payload.Content?
        var hasDashboardLayout = false
        for script in try document.nodes(forXPath: "//script[@type='application/json']") {
            guard let json = script.stringValue,
                json.contains("\"pullsDashboardSurfaceContentRoute\"")
                    || json.contains("\"pullsDashboardSurfaceLayoutRoute\"")
            else { continue }
            let envelope = try JSONDecoder().decode(Embedded.self, from: Data(json.utf8))
            let layout = envelope.payload.pullsDashboardSurfaceLayoutRoute
            if layout != nil { hasDashboardLayout = true }
            if let org = layout?.sso?.sso_organizations?.first ?? layout?.sso_organizations?.first,
                let sso = ssoURL("/orgs/\(org.login)/sso")
            {
                throw GitHubFolderError.singleSignOn(sso)
            }
            if let route = envelope.payload.pullsDashboardSurfaceContentRoute { content = route }
        }
        let login = try document.nodes(forXPath: "//meta[@name='octolytics-actor-login']/@content").first?.stringValue
        guard let login, !login.isEmpty else {
            let signedOut = try document.nodes(
                forXPath: "//body[contains(concat(' ',normalize-space(@class),' '),' logged-out ')]")
            throw signedOut.isEmpty ? GitHubFolderError.unavailable : GitHubFolderError.signedOut
        }
        if let content {
            let rows = try content.results.map {
                try row(path: "/\($0.repoNameWithOwner)/pull/\($0.number)", title: $0.title)
            }
            guard let total = content.pageInfo?.totalPages, total >= 0 else { throw GitHubFolderError.unavailable }
            return Page(items: rows, hasNext: total > number || !next.isEmpty)
        }
        // The Inbox also renders a blankslate. Only a legacy results page can use it as an empty search.
        guard !hasDashboardLayout, path == "/pulls" else { throw GitHubFolderError.unavailable }
        let links = try document.nodes(
            forXPath: "//a[@data-hovercard-type='pull_request' or starts-with(@id,'issue_')][@href]")
        let items = try links.compactMap { node -> GitHubPullRequest? in
            guard let element = node as? XMLElement, let href = element.attribute(forName: "href")?.stringValue else {
                return nil
            }
            return try row(path: href, title: element.stringValue ?? "")
        }
        // An unfamiliar page must not empty a folder that was fetched successfully.
        if items.isEmpty {
            let empty = try document.nodes(
                forXPath: "//*[contains(concat(' ',normalize-space(@class),' '),' blankslate ')]")
            let list = try document.nodes(
                forXPath: """
                    //*[@id='js-issues-toolbar' or contains(concat(' ',normalize-space(@class),' '),' js-navigation-container ')
                    or contains(concat(' ',normalize-space(@class),' '),' js-active-navigation-container ')
                    or contains(concat(' ',normalize-space(@class),' '),' table-list-header-toggle ')]
                    """)
            guard !list.isEmpty, !empty.isEmpty, next.isEmpty else { throw GitHubFolderError.unavailable }
        }
        return Page(items: items, hasNext: !next.isEmpty)
    }

    private static func row(path: String, title: String) throws -> GitHubPullRequest {
        guard let url = URL(string: path, relativeTo: github)?.absoluteURL, url.scheme == "https",
            url.host == "github.com",
            url.user == nil, url.password == nil, url.port == nil, url.query == nil, url.fragment == nil
        else { throw GitHubFolderError.unavailable }
        let parts = url.path.split(separator: "/")
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard parts.count == 4, parts[2] == "pull", (Int(parts[3]) ?? 0) > 0, !title.isEmpty else {
            throw GitHubFolderError.unavailable
        }
        return GitHubPullRequest(url: url, title: title)
    }

    private static func ssoURL(_ href: String) -> URL? {
        guard let url = URL(string: href, relativeTo: github)?.absoluteURL, url.scheme == "https",
            url.host == "github.com",
            url.user == nil, url.password == nil, url.port == nil
        else { return nil }
        let parts = url.path.split(separator: "/")
        return parts.count == 3 && parts.first == "orgs" && parts.last == "sso" ? url : nil
    }
}
