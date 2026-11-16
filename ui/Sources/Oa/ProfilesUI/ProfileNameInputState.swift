import Foundation

enum ProfileName {
    /// Chromium's own profiles' names, which Arc refuses for a profile.
    static let reserved: Set<String> = ["System Profile", "Guest Profile", "__ARC_SYSTEM_PROFILE"]
}

/// Arc's `ProfileNameInputState` for a new profile's name. As it is typed, newlines become spaces and the name is cut
/// at `limit`; no character is refused.
struct ProfileNameInputState {
    var limit = 500
    let existingProfileNames: Set<String>
    var profileNameRawValue = "" {
        didSet {
            let line = profileNameRawValue.components(separatedBy: .newlines).joined(separator: " ")
            let cut = String(line.prefix(limit))
            if cut != profileNameRawValue { profileNameRawValue = cut }
        }
    }

    var trimmed: String { profileNameRawValue.trimmingCharacters(in: .whitespaces) }

    var isValid: Bool { !trimmed.isEmpty && error == nil }

    var error: String? {
        if existingProfileNames.contains(trimmed) { return "A Profile with that name already exists." }
        return ProfileName.reserved.contains(trimmed) ? "Invalid Profile name." : nil
    }
}
