import DevKit
import Foundation

struct GmailAccount: Hashable {
    let number: Int

    init?(url: URL?) {
        guard let url, url.scheme == "https", url.host()?.lowercased() == "mail.google.com",
            url.port == nil || url.port == 443
        else { return nil }
        let path = url.pathComponents.filter { $0 != "/" }
        if path.isEmpty || path == ["mail"] {
            number = 0
        } else {
            guard path.starts(with: ["mail", "u"]), path.count >= 3, let index = Int(path[2]),
                index >= 0, String(index) == path[2]
            else { return nil }
            number = index
        }
    }

    var inbox: URL { URL(string: "https://mail.google.com/mail/u/\(number)/")! }
    var compose: URL { URL(string: "#compose", relativeTo: inbox)!.absoluteURL }

    func messageURL(_ link: String) -> URL? {
        guard var parts = URLComponents(string: link), ["http", "https"].contains(parts.scheme),
            parts.host?.lowercased() == "mail.google.com", parts.user == nil, parts.password == nil,
            parts.port == nil || parts.port == 443
        else { return nil }
        parts.scheme = "https"
        if parts.path == "/mail" || parts.path == "/mail/" { parts.path = inbox.path(percentEncoded: false) }
        guard let url = parts.url, GmailAccount(url: url) == self else { return nil }
        return url
    }
}

struct GmailMessage: Identifiable {
    let id: String
    let subject: String
    let senders: String
    let summary: String
    let date: Date
    let url: URL
}

@MainActor
@Observable
final class GmailInbox {
    enum State {
        case loading, unavailable, loaded([GmailMessage])
    }

    let account: GmailAccount
    private(set) var state = State.loading
    @ObservationIgnored private var pending: Task<Void, Never>?
    @ObservationIgnored private var refreshed: Date?

    init(account: GmailAccount) { self.account = account }

    func hasUnread(since date: Date?) -> Bool {
        guard case .loaded(let messages) = state else { return false }
        return messages.contains { $0.date > (date ?? .distantPast) }
    }

    func refresh(in context: any BrowserContext) async {
        if let pending { return await pending.value }
        guard refreshed.map({ Date.now.timeIntervalSince($0) >= 60 }) ?? true else { return }
        let task = Task { await fetch(in: context) }
        pending = task
        await task.value
    }

    private func fetch(in context: any BrowserContext) async {
        defer { pending = nil }
        let inbox = Task { await entries(in: context, label: nil) }
        let social = Task { await entries(in: context, label: "^sq_ig_i_social") }
        let promotions = Task { await entries(in: context, label: "^sq_ig_i_promo") }
        let results = await (inbox.value, social.value, promotions.value)
        guard !Task.isCancelled else { return }
        refreshed = .now
        if let inbox = results.0, let social = results.1, let promotions = results.2 {
            var excluded = Set((social + promotions).map(\.id))
            state = .loaded(inbox.filter { excluded.insert($0.id).inserted })
        } else {
            state = .unavailable
        }
    }

    private func entries(in context: any BrowserContext, label: String?) async -> [GmailMessage]? {
        let base = account.inbox.appending(path: "feed/atom", directoryHint: .isDirectory)
        let url = label.map { base.appending(component: $0) } ?? base
        guard let document = await context.loadDocument(at: url), document.status == 200,
            GmailAccount(url: document.url) == account, document.url.path == url.path,
            let xml = try? XMLDocument(data: document.body, options: [.nodeLoadExternalEntitiesNever]),
            let root = xml.rootElement(), root.localName == "feed",
            ["http://purl.org/atom/ns#", "http://www.w3.org/2005/Atom"].contains(root.uri)
        else { return nil }
        return root.elements(forLocalName: "entry", uri: root.uri).compactMap { entry in
            func field(_ name: String) -> String? {
                entry.elements(forLocalName: name, uri: root.uri).first?.stringValue
            }
            guard let subject = field("title"), let stamp = field("issued") ?? field("published") ?? field("updated"),
                let date = (try? Date(stamp, strategy: .iso8601))
                    ?? (try? Date(stamp, strategy: .iso8601.time(includingFractionalSeconds: true))),
                let href = entry.elements(forLocalName: "link", uri: root.uri)
                    .first(where: { ($0.attribute(forName: "rel")?.stringValue ?? "alternate") == "alternate" })?
                    .attribute(forName: "href")?.stringValue,
                let url = account.messageURL(href)
            else { return nil }
            let senders = entry.elements(forLocalName: "author", uri: root.uri).compactMap {
                $0.elements(forLocalName: "name", uri: root.uri).first?.stringValue
            }
            return GmailMessage(
                id: field("id") ?? url.absoluteString, subject: subject,
                senders: senders.joined(separator: ", "), summary: field("summary") ?? "", date: date, url: url)
        }
    }
}
