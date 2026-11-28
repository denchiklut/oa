import DevKit
import Foundation

enum RecentPagesFetcher {
    private static let excludedSubstrings = [
        "notion.so/samlauthcallback",
        "notion.so/externalintegrationauthcallback",
        "notion.so/googlepopupcallback",
        "notion.so/oauth2callback",
        "figma.com/files/recent",
    ]

    private static let titleSuffixes: [RecentPagesDomain: [String]] = [
        .notion: [" | Notion", " – Notion", " - Notion"],
        .figma: [" – Figma", " - Figma"],
        .linear: [" — Linear", " – Linear", " - Linear"],
        .confluence: [" - Confluence", " – Confluence"],
    ]

    @MainActor
    static func fetch(_ domain: RecentPagesDomain, in context: any BrowserContext) async -> PreviewState {
        let entries = await context.history(matching: domain.searchQuery, maxResults: 60)
        var seen = Set<String>()
        var items: [RecentPageItem] = []
        for entry in entries {
            guard domain.matches(entry.url), !isExcluded(entry.url, domain: domain) else { continue }
            let key = canonicalKey(entry.url)
            guard seen.insert(key).inserted else { continue }
            let title = tidy(entry.title, domain: domain, url: entry.url)
            guard !title.isEmpty else { continue }
            items.append(RecentPageItem(title: title, url: entry.url, lastVisited: entry.lastVisited))
        }
        items.sort { ($0.lastVisited ?? .distantPast) > ($1.lastVisited ?? .distantPast) }
        return .loaded(.recentPages(domain, Array(items.prefix(8))))
    }

    private static func isExcluded(_ url: URL, domain: RecentPagesDomain) -> Bool {
        let absolute = url.absoluteString.lowercased()
        if excludedSubstrings.contains(where: { absolute.contains($0) }) { return true }
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
        if path.isEmpty || path == "login" || path == "signin" || path == "auth" || path == "new" { return true }
        if domain == .confluence, path == "wiki" || path == "wiki/home" { return true }
        return false
    }

    private static func canonicalKey(_ url: URL) -> String {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.fragment = nil
        let raw = components?.string ?? url.absoluteString
        return raw.hasSuffix("/") ? String(raw.dropLast()) : raw
    }

    private static func tidy(_ title: String, domain: RecentPagesDomain, url: URL) -> String {
        var cleaned = title.trimmingCharacters(in: .whitespacesAndNewlines)
        for suffix in titleSuffixes[domain] ?? [] where cleaned.hasSuffix(suffix) {
            cleaned = String(cleaned.dropLast(suffix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            break
        }
        if cleaned.isEmpty {
            return url.lastPathComponent.replacingOccurrences(of: "-", with: " ")
        }
        return cleaned
    }
}

enum GmailPreviewFetcher {
    private static let accept = "application/atom+xml, application/xml;q=0.9, */*;q=0.8"

    @MainActor
    static func fetch(inboxNumber: Int, in context: any BrowserContext) async -> PreviewState {
        let base = URL(string: "https://mail.google.com/mail/u/\(inboxNumber)/feed/atom/")!
        let socialURL = base.appendingPathComponent("^sq_ig_i_social")
        let promoURL = base.appendingPathComponent("^sq_ig_i_promo")

        let primaryTask = Task { @MainActor in await context.loadDocument(at: base, accept: accept) }
        let socialTask = Task { @MainActor in await context.loadDocument(at: socialURL, accept: accept) }
        let promoTask = Task { @MainActor in await context.loadDocument(at: promoURL, accept: accept) }
        let primary = await primaryTask.value
        let social = await socialTask.value
        let promo = await promoTask.value

        guard let primary else { return .failed }
        if isSignedOut(primary) { return .signedOut }
        guard primary.status == 200, let allEmails = parseAtom(primary.body) else { return .failed }

        var excludedIDs = Set<String>()
        for category in [social, promo] {
            guard let category, category.status == 200, let items = parseAtom(category.body) else { continue }
            for item in items { excludedIDs.insert(emailKey(item.url)) }
        }
        let filtered = allEmails.filter { !excludedIDs.contains(emailKey($0.url)) }
        return .loaded(.gmail(inboxNumber: inboxNumber, Array(filtered.prefix(10))))
    }

    private static func isSignedOut(_ document: ProfileDocument) -> Bool {
        if document.status == 401 || document.status == 403 { return true }
        guard let host = document.url.host()?.lowercased() else { return false }
        return host == "accounts.google.com" || host == "workspace.google.com"
    }

    private static func emailKey(_ url: URL) -> String {
        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            let messageID = components.queryItems?.first(where: { $0.name == "message_id" })?.value
        {
            return messageID
        }
        return url.absoluteString
    }

    static func parseAtom(_ data: Data) -> [UnreadEmailItem]? {
        guard !data.isEmpty,
            let document = try? XMLDocument(data: data, options: [.nodeLoadExternalEntitiesNever]),
            let root = document.rootElement(),
            root.localName == "feed"
        else { return nil }

        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let standard = ISO8601DateFormatter()

        var result: [UnreadEmailItem] = []
        for child in root.children ?? [] {
            guard let entry = child as? XMLElement, entry.localName == "entry" else { continue }
            let title = elementText(named: "title", in: entry)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let summary =
                elementText(named: "summary", in: entry)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let issuedText = elementText(named: "issued", in: entry) ?? elementText(named: "modified", in: entry)
            let date = issuedText.flatMap { fractional.date(from: $0) ?? standard.date(from: $0) }
            let link =
                (entry.children ?? []).compactMap { $0 as? XMLElement }
                .first { $0.localName == "link" }?
                .attribute(forName: "href")?.stringValue
                .flatMap(URL.init(string:))
            guard let url = link else { continue }

            var senderName = ""
            var senderEmail: String?
            if let author = (entry.children ?? []).compactMap({ $0 as? XMLElement }).first(where: {
                $0.localName == "author"
            }) {
                senderName =
                    elementText(named: "name", in: author)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                senderEmail = elementText(named: "email", in: author)?.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            let sender = !senderName.isEmpty ? senderName : (senderEmail ?? "Unknown")
            let subject = title.isEmpty ? "(No Subject)" : title
            result.append(
                UnreadEmailItem(
                    title: subject, summary: summary, sender: sender, authorEmail: senderEmail, date: date, url: url))
        }
        return result
    }

    private static func elementText(named localName: String, in parent: XMLElement) -> String? {
        (parent.children ?? []).compactMap { $0 as? XMLElement }.first { $0.localName == localName }?.stringValue
    }
}

enum LiveCalendarFetcher {
    private static let joinPatterns = [
        #"(https?://)?meet\.google\.com/[a-zA-Z0-9%:/#?\[\]@!$&'()*+,;=\-\.]+"#,
        #"(https?://)?[a-zA-Z0-9_\-]+\.zoom\.us/[a-zA-Z0-9%:/#?\[\]@!$&'()*+,;=\-\.]+"#,
        #"(https?://)?teams\.live\.com/meet/[a-zA-Z0-9%:/#?\[\]@!$&'()*+,;=\-\.]+"#,
        #"(https?://)?around\.co/r/[a-zA-Z0-9%:/#?\[\]@!$&'()*+,;=\-\.]+"#,
    ]

    @MainActor
    static func fetch(accountNumber: Int, isNotionCalendar: Bool, in context: any BrowserContext) async -> PreviewState
    {
        guard let capture = await context.fetchLiveCalendar(accountNumber: accountNumber) else { return .failed }
        if capture.isSignedOut { return .signedOut }
        guard !capture.eventPayloads.isEmpty else { return .failed }

        let now = Date.now
        let calendar = Calendar.current
        let endOfTomorrow =
            calendar.date(byAdding: .day, value: 2, to: calendar.startOfDay(for: now))
            ?? now.addingTimeInterval(48 * 3600)

        var seen = Set<String>()
        var events: [CalendarEventItem] = []
        var decodedAny = false

        for payload in capture.eventPayloads {
            guard let data = payload.data(using: .utf8),
                let response = try? JSONDecoder().decode(EventsResponse.self, from: data)
            else { continue }
            decodedAny = true
            for raw in response.items ?? [] {
                guard !isDeclined(raw.attendees),
                    let range = parseRange(start: raw.start, end: raw.end, calendar: calendar),
                    range.end > now, range.start < endOfTomorrow
                else { continue }
                let id = raw.id ?? "\(raw.summary ?? "")-\(range.start.timeIntervalSince1970)"
                let dedupeKey = "\(id)-\(Int(range.start.timeIntervalSince1970))"
                guard seen.insert(dedupeKey).inserted else { continue }
                let title = (raw.summary ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let permalink = makePermalink(raw: raw, isNotionCalendar: isNotionCalendar)
                let joinLink = extractJoinLink(from: raw)
                events.append(
                    CalendarEventItem(
                        id: dedupeKey,
                        title: title.isEmpty ? "(No title)" : title,
                        start: range.start,
                        end: range.end,
                        isAllDay: range.isAllDay,
                        permalink: permalink,
                        joinLink: joinLink,
                        location: raw.location))
            }
        }
        guard decodedAny else { return .failed }
        events.sort {
            if $0.start != $1.start { return $0.start < $1.start }
            return $0.title < $1.title
        }
        return .loaded(
            .calendar(
                accountNumber: accountNumber, isNotionCalendar: isNotionCalendar, Array(events.prefix(12))))
    }

    private struct EventsResponse: Decodable {
        let items: [RawEvent]?
    }

    private struct RawEvent: Decodable {
        let id: String?
        let htmlLink: String?
        let summary: String?
        let description: String?
        let location: String?
        let hangoutLink: String?
        let start: EventTime?
        let end: EventTime?
        let conferenceData: ConferenceData?
        let attendees: [Attendee]?
    }

    private struct EventTime: Decodable {
        let dateTime: String?
        let date: String?
    }

    private struct ConferenceData: Decodable {
        let entryPoints: [EntryPoint]?
    }

    private struct EntryPoint: Decodable {
        let entryPointType: String?
        let uri: String?
    }

    private struct Attendee: Decodable {
        let isSelf: Bool?
        let responseStatus: String?

        enum CodingKeys: String, CodingKey {
            case isSelf = "self"
            case responseStatus
        }
    }

    private static func isDeclined(_ attendees: [Attendee]?) -> Bool {
        attendees?.contains { $0.isSelf == true && $0.responseStatus == "declined" } == true
    }

    private static func parseRange(start: EventTime?, end: EventTime?, calendar: Calendar) -> (
        start: Date, end: Date, isAllDay: Bool
    )? {
        guard let start else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let standard = ISO8601DateFormatter()

        if let startText = start.dateTime,
            let startDate = fractional.date(from: startText) ?? standard.date(from: startText)
        {
            let endDate =
                end?.dateTime.flatMap { fractional.date(from: $0) ?? standard.date(from: $0) }
                ?? startDate.addingTimeInterval(3600)
            return (startDate, endDate, false)
        }
        if let dayText = start.date {
            let dayFormatter = DateFormatter()
            dayFormatter.calendar = calendar
            dayFormatter.locale = Locale(identifier: "en_US_POSIX")
            dayFormatter.dateFormat = "yyyy-MM-dd"
            if let startDate = dayFormatter.date(from: dayText) {
                let endDate =
                    end?.date.flatMap(dayFormatter.date(from:))
                    ?? calendar.date(byAdding: .day, value: 1, to: startDate)
                    ?? startDate.addingTimeInterval(86_400)
                return (startDate, endDate, true)
            }
        }
        return nil
    }

    private static func makePermalink(raw: RawEvent, isNotionCalendar: Bool) -> URL? {
        if isNotionCalendar, let id = raw.id, !id.isEmpty {
            return URL(string: "https://calendar.notion.so/event/\(id)")
        }
        return raw.htmlLink.flatMap(URL.init(string:))
    }

    private static func extractJoinLink(from event: RawEvent) -> URL? {
        if let videoURI = event.conferenceData?.entryPoints?.first(where: { $0.entryPointType == "video" })?.uri,
            let url = URL(string: videoURI)
        {
            return url
        }
        if let hangout = event.hangoutLink, let url = URL(string: hangout) {
            return url
        }
        let haystack = [event.location, event.description].compactMap { $0 }.joined(separator: "\n")
        guard !haystack.isEmpty else { return nil }
        for pattern in joinPatterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { continue }
            let range = NSRange(haystack.startIndex..., in: haystack)
            if let match = regex.firstMatch(in: haystack, range: range),
                let swiftRange = Range(match.range, in: haystack)
            {
                let raw = String(haystack[swiftRange])
                let normalized = raw.lowercased().hasPrefix("http") ? raw : "https://" + raw
                if let url = URL(string: normalized) { return url }
            }
        }
        return nil
    }
}
