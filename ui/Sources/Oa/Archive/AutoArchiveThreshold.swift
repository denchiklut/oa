import Foundation

/// Arc's `Archive.AutoArchiveInactiveThreshold`, the four it offers for tabs; its `never` and debug cases sit behind
/// flags.
enum AutoArchiveInactiveThreshold: String, CaseIterable, Identifiable {
    case twelveHours, twentyFourHours, sevenDays, thirtyDays

    var id: Self { self }

    var seconds: TimeInterval {
        switch self {
        case .twelveHours: 12 * 3600
        case .twentyFourHours: 24 * 3600
        case .sevenDays: 7 * 86400
        case .thirtyDays: 30 * 86400
        }
    }

    var title: String {
        switch self {
        case .twelveHours: "12 hours"
        case .twentyFourHours: "24 hours"
        case .sevenDays: "7 days"
        case .thirtyDays: "30 days"
        }
    }

    var label: String { self == .twelveHours ? "\(title) (default)" : title }
}

/// Arc's defaults keys and case names: the profile's entry, else the value for every profile, else 12 hours. Arc keys
/// the entries by its profile value; Oa's are keyed by profile ID.
enum AutoArchiveThresholds {
    private static let key = "autoArchiveTimeThreshold"
    private static let perProfileKey = "autoArchiveTimeThresholdsPerProfile"

    static func threshold(for profileID: UUID) -> AutoArchiveInactiveThreshold {
        let defaults = UserDefaults.standard
        let name =
            defaults.dictionary(forKey: perProfileKey)?[profileID.uuidString] as? String ?? defaults.string(forKey: key)
        return name.flatMap(AutoArchiveInactiveThreshold.init) ?? .twelveHours
    }

    /// As Arc: the profile's own entry is written first. True when Arc then asks whether the change is for every
    /// profile: there are several and the stored entries now disagree. Otherwise the value for every profile is
    /// written too, which changes each profile without an entry of its own.
    static func set(_ threshold: AutoArchiveInactiveThreshold, for profileID: UUID, among profiles: [UUID]) -> Bool {
        let defaults = UserDefaults.standard
        var entries = defaults.dictionary(forKey: perProfileKey) ?? [:]
        entries[profileID.uuidString] = threshold.rawValue
        defaults.set(entries, forKey: perProfileKey)
        if profiles.count > 1, Set(entries.values.compactMap { $0 as? String }).count > 1 { return true }
        defaults.set(threshold.rawValue, forKey: key)
        return false
    }

    /// Arc's "All Profiles": an entry for each of `profiles` and the value for every profile; other entries stay.
    static func setForAll(_ threshold: AutoArchiveInactiveThreshold, profiles: [UUID]) {
        let defaults = UserDefaults.standard
        var entries = defaults.dictionary(forKey: perProfileKey) ?? [:]
        for profile in profiles { entries[profile.uuidString] = threshold.rawValue }
        defaults.set(entries, forKey: perProfileKey)
        defaults.set(threshold.rawValue, forKey: key)
    }
}
