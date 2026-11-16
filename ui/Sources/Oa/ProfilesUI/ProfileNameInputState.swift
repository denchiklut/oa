import Foundation

enum ProfileName {
    /// Chromium's own profiles' names, which Arc refuses for a profile.
    static let reserved: Set<String> = ["System Profile", "Guest Profile", "__ARC_SYSTEM_PROFILE"]
}
