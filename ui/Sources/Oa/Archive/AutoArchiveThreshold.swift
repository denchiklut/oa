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

    var label: String {
        switch self {
        case .twelveHours: "12 hours (default)"
        case .twentyFourHours: "24 hours"
        case .sevenDays: "7 days"
        case .thirtyDays: "30 days"
        }
    }
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

    /// As Arc: the profile's own entry when there are several profiles, else the value for every profile.
    static func set(_ threshold: AutoArchiveInactiveThreshold, for profileID: UUID, amongSeveral: Bool) {
        let defaults = UserDefaults.standard
        guard amongSeveral else { return defaults.set(threshold.rawValue, forKey: key) }
        var entries = defaults.dictionary(forKey: perProfileKey) ?? [:]
        entries[profileID.uuidString] = threshold.rawValue
        defaults.set(entries, forKey: perProfileKey)
    }
}
