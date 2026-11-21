import Foundation

extension URL {
    /// Arc's `URL.TrackingRemovalResult`.
    struct TrackingRemovalResult {
        let url: URL
        let trackingRemoved: Bool
    }

    /// Arc's `withTrackingRemoved`, with its lists. The URL is put together again from what is left of its query
    /// even when nothing was a tracker, so it can come back spelled differently (`%2B` as `+`), as Arc's does.
    var withTrackingRemoved: TrackingRemovalResult {
        let unchanged = TrackingRemovalResult(url: self, trackingRemoved: false)
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false) else { return unchanged }
        var items = components.queryItems ?? []
        let isAmazon = isDomain("amazon.com")
        guard !items.isEmpty || isAmazon, components.query?.contains(";") != true else { return unchanged }
        if isDomain("twitter.com") || isDomain("x.com") { items.removeAll { Self.twitterNames.contains($0.name) } }
        var removedPath = false
        if isAmazon {
            items.removeAll { item in Self.amazonPrefixes.contains { item.name.hasPrefix($0) } }
            items.removeAll { Self.amazonNames.contains($0.name) }
            if let last = pathComponents.last, last.hasPrefix("ref=") {
                var path = deletingLastPathComponent().path(percentEncoded: true)
                if path.hasSuffix("/") { path.removeLast() }
                components.path = path
                removedPath = true
            }
        }
        if isDomain("youtube.com") { items.removeAll { Self.youtubeNames.contains($0.name) } }
        if isDomain("ebay.com") {
            items.removeAll { Self.ebayNames.contains($0.name) }
            items.removeAll { Self.ebayItemNames.contains($0.name) }
        }
        items.removeAll { item in
            Self.trackingPrefixes.contains { item.name.hasPrefix($0) } || Self.trackingNames.contains(item.name)
        }
        components.queryItems = items.isEmpty ? nil : items
        let url = components.url ?? self
        return TrackingRemovalResult(
            url: url, trackingRemoved: removedPath || queryItemNames != url.queryItemNames)
    }

    private var queryItemNames: Set<String> {
        Set(URLComponents(url: self, resolvingAgainstBaseURL: false)?.queryItems?.map(\.name) ?? [])
    }

    private func isDomain(_ domain: String) -> Bool {
        guard let host = host() else { return false }
        return host == domain || host.hasSuffix("." + domain) || host.components(separatedBy: ".").contains(domain)
    }

    private static let trackingPrefixes: Set<String> = [
        "_bta_c", "_bta_tid", "_ga", "_hsenc", "_hsmi", "_ke", "_openstat", "dm_i", "ef_id", "epik", "gclsrc",
        "gdffi", "gdfms", "gdftrk", "hsa_", "igsh", "matomo_", "mc_", "mkwid", "msclkid", "mtm_", "ns_",
        "oly_anon_id", "oly_enc_id", "otc", "pcrid", "piwik_", "pk_", "rb_clickid", "redirect_log_mongo_id",
        "redirect_mongo_id", "ref", "s_kwcid", "sb_referer_host", "soc_src", "soc_trk", "spm", "sr_", "stm_",
        "trk_", "utm_", "vero_",
    ]
    private static let trackingNames: Set<String> = [
        "cm_mmc", "fbclid", "gad_source", "gclid", "ref", "pla", "spm", "si", "trackingId", "mt", "mcid",
        "linkCode", "srsltid", "ocid", "trk", "ncid", "mtc", "srcid", "nr_email_referer", "_pos", "_sid", "_ss",
        "share_id",
    ]
    private static let twitterNames: Set<String> = ["t", "s"]
    private static let amazonPrefixes: Set<String> = [
        "_encoding", "ascsubtag", "pd_rd_", "pf", "pf_rd_", "psc", "tag", "ie", "hv",
    ]
    private static let amazonNames: Set<String> = [
        "content-id", "crid", "dib", "dib_tag", "keywords", "qid", "rnid", "s", "sprefix", "th",
    ]
    private static let youtubeNames: Set<String> = ["feature", "app", "embeds_referring_euri", "source_ve_path"]
    private static let ebayNames: Set<String> = ["_trkparms", "_trksid", "_from", "hash"]
    private static let ebayItemNames: Set<String> = ["_skw", "itmmeta", "itmprp"]
}
