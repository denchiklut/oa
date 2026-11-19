import AppKit
import Observation

/// Arc's `TopBarColorClient`: the colour for the toolbar over each page it shows, sampled from the top right corner
/// of the page's thumbnails, and a cache by host for a page not sampled yet. Observable: a sample changes its page's
/// `appliedColor`.
///
/// A sample's components are kept as the thumbnail has them, which is in the colours of the display the page is on,
/// and Arc's cache holds the same numbers. A colour handed out is in the colour space of the page's window, so the
/// toolbar matches the page. LIKELY Arc's: which space it assigns isn't decoded, but its toolbar matches too.
@MainActor
@Observable
public final class TopBarColorClient {
    /// Arc's `TopBarColorState`.
    private struct State {
        var colorToDisplay: Sample?
        var currentColorSample: Sample?
        var numConvergenceAttempts = 0
        var requireConvergence = false
        var lastUpdated = Date.distantPast
    }

    private struct Sample: Equatable {
        var red: Double
        var green: Double
        var blue: Double

        /// The Euclidean distance of the components, as Arc's.
        func distance(to other: Sample) -> Double {
            let (red, green, blue) = (red - other.red, green - other.green, blue - other.blue)
            return (red * red + green * green + blue * blue).squareRoot()
        }
    }

    private struct CacheEntry {
        var color: Sample
        var lastUpdated: Date
    }

    private struct TrackedPage {
        weak var page: (any Page)?
    }

    private static let defaultsKey = "TopBarColorCache"
    /// About 2.2 of a channel's 255 steps.
    private static let convergenceDistance = 0.015

    private var states: [UUID: State] = [:]
    @ObservationIgnored private var tracked: [AnyHashable: TrackedPage] = [:]
    @ObservationIgnored private var watched: Set<UUID> = []
    @ObservationIgnored private var cache: [String: CacheEntry] = [:]
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var pendingSave: Task<Void, Never>?

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        for (key, value) in defaults.dictionary(forKey: Self.defaultsKey) ?? [:] {
            guard let value = value as? [String: Any],
                let hex = (value["Color"] as? String).flatMap({ UInt32($0, radix: 16) }),
                let lastUsed = value["LastUsed"] as? Double
            else { continue }
            let color = Sample(
                red: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255,
                blue: Double(hex & 0xFF) / 255)
            cache[key] = CacheEntry(color: color, lastUpdated: Date(timeIntervalSinceReferenceDate: lastUsed))
        }
    }

    /// The page's last sample, which its toolbar shows.
    public func appliedColor(for page: any Page) -> NSColor? {
        states[page.id]?.colorToDisplay.map { color($0, on: page) }
    }

    /// As Arc's `cachedColorForURL`: the last settled colour of a page on the host of this page's URL, for a toolbar
    /// whose page has no sample yet.
    public func cachedColor(for page: any Page) -> NSColor? {
        page.url.flatMap { cache[Self.cacheKey(for: $0)] }.map { color($0.color, on: page) }
    }

    private func color(_ sample: Sample, on page: any Page) -> NSColor {
        NSColor(
            colorSpace: page.view.window?.colorSpace ?? NSScreen.main?.colorSpace ?? .sRGB,
            components: [sample.red, sample.green, sample.blue, 1], count: 4)
    }

    /// As Arc's `setTrackedContentIDs`, a toolbar at a time: `owner`'s toolbar shows `page` now, or none. A page that
    /// starts being shown is sampled 250 ms later, unless its colour is under half an hour old.
    public func setTrackedPage(_ page: (any Page)?, for owner: AnyHashable) {
        let wasTracked = page.map { isTracking($0.id) } ?? true
        tracked[owner] = page.map { TrackedPage(page: $0) }
        guard let page, !wasTracked else { return }
        if watched.insert(page.id).inserted { watch(page, loadsDocument: false) }
        if Date.now.timeIntervalSince(states[page.id]?.lastUpdated ?? .distantPast) >= 1800 {
            requestHeaderColorUpdate(for: page.id, requireConvergence: false, delay: .milliseconds(250))
        }
    }

    /// As Arc's: asks the page for a thumbnail after `delay`. `requireConvergence` says whether the sample it gives
    /// must match the one before it to be cached.
    public func requestHeaderColorUpdate(for pageID: UUID, requireConvergence: Bool, delay: Duration) {
        guard isTracking(pageID) else { return }
        states[pageID, default: State()].requireConvergence = requireConvergence
        requestThumbnail(of: pageID, after: delay)
    }

    /// As Arc's WebContent feature does with every thumbnail of a tracked page, whoever asked for it: the pixel at
    /// its top right, one row down, is the page's new sample. Its components are read as they are.
    public func process(thumbnail: NSImage, ofPage pageID: UUID, at url: URL?) {
        guard isTracking(pageID), let cgImage = thumbnail.cgImage(forProposedRect: nil, context: nil, hints: nil),
            let pixel = NSBitmapImageRep(cgImage: cgImage).colorAt(x: Int(thumbnail.size.width) - 1, y: 1),
            pixel.numberOfComponents >= 3
        else { return }
        var components = [CGFloat](repeating: 0, count: pixel.numberOfComponents)
        pixel.getComponents(&components)
        processHeaderColorUpdate(
            color: Sample(red: components[0], green: components[1], blue: components[2]), for: pageID, at: url)
    }

    /// Arc's rule. Every sample is shown at once; whether it matches the one before only decides if it is cached
    /// or the page is asked again, 400 ms later and at most four times.
    private func processHeaderColorUpdate(color: Sample, for pageID: UUID, at url: URL?) {
        var state = states[pageID] ?? State()
        let key = url.map(Self.cacheKey)
        let converged =
            state.currentColorSample.map { $0.distance(to: color) <= Self.convergenceDistance } ?? false
        let differsFromCache =
            key.flatMap { cache[$0] }.map { $0.color.distance(to: color) > Self.convergenceDistance } ?? true
        var asksAgain = false
        if state.requireConvergence, !converged, differsFromCache {
            asksAgain = state.numConvergenceAttempts <= 3
            if asksAgain { state.numConvergenceAttempts += 1 }
        } else {
            if let key {
                cache[key] = CacheEntry(color: color, lastUpdated: .now)
                scheduleSave()
            }
            state.numConvergenceAttempts = 0
            state.requireConvergence = true
        }
        state.colorToDisplay = color
        state.currentColorSample = color
        state.lastUpdated = .now
        states[pageID] = state
        if asksAgain { requestHeaderColorUpdate(for: pageID, requireConvergence: true, delay: .milliseconds(400)) }
    }

    private func trackedPage(_ pageID: UUID) -> (any Page)? {
        tracked.values.lazy.compactMap(\.page).first { $0.id == pageID }
    }

    private func isTracking(_ pageID: UUID) -> Bool { trackedPage(pageID) != nil }

    private func requestThumbnail(of pageID: UUID, after delay: Duration) {
        Task { [weak self] in
            try? await Task.sleep(for: delay)
            self?.trackedPage(pageID)?.requestThumbnail()
        }
    }

    /// Oa's own, as Arc's triggers aren't decoded: a tracked page is sampled 200 ms after a document finishes
    /// loading and 1 s after a navigation within one, near the delays measured in Arc. A document's load is known by
    /// the page loading when the navigation starts.
    private func watch(_ page: any Page, loadsDocument: Bool) {
        let pageID = page.id
        withObservationTracking {
            _ = page.navigationResult
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard let page = trackedPage(pageID) else {
                    watched.remove(pageID)
                    return
                }
                if page.navigationResult == nil {
                    watch(page, loadsDocument: page.isLoading)
                } else {
                    requestThumbnail(of: pageID, after: loadsDocument ? .milliseconds(200) : .seconds(1))
                    watch(page, loadsDocument: false)
                }
            }
        }
    }

    /// Arc's key: a hash of the URL's host as it is, so `www.` hosts and bare ones differ and the port doesn't count.
    static func cacheKey(for url: URL) -> String {
        guard let host = url.host() else { return "NullString" }
        var hash = 5381
        for byte in host.utf8 {
            hash = ((hash & 0x00FF_FFFF_FFFF_FFFF) << 7) &- (hash & 0x00FF_FFFF_FFFF_FFFF) &+ Int(byte)
        }
        return String(hash)
    }

    /// Oa's own moment, as Arc's isn't known: once, 2 s after a colour is cached.
    private func scheduleSave() {
        guard pendingSave == nil else { return }
        pendingSave = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            self?.pendingSave = nil
            self?.saveToDisk()
        }
    }

    /// As Arc's: the 50 entries used last, in its defaults format, so the two apps' caches can be compared.
    private func saveToDisk() {
        let newest = cache.sorted { $0.value.lastUpdated > $1.value.lastUpdated }.prefix(50)
        let stored = newest.map { key, entry -> (String, [String: Any]) in
            let channels = [entry.color.red, entry.color.green, entry.color.blue]
            let hex = channels.map { String(format: "%02X", Int(($0 * 255).rounded())) }.joined()
            return (key, ["Color": hex, "LastUsed": entry.lastUpdated.timeIntervalSinceReferenceDate])
        }
        defaults.set(Dictionary(uniqueKeysWithValues: stored), forKey: Self.defaultsKey)
    }
}
