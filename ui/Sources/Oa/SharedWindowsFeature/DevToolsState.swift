import DevKit
import Foundation
import Observation

/// As Arc's `SharedWindowsFeature.DevToolsState`: shared by every window and kept in memory only, one docked size per
/// side, as DevTools' share of the page's split.
@MainActor
@Observable
final class DevToolsState {
    static let shared = DevToolsState()
    /// As measured in Arc: a third of the split, splitter included, on each side until resized.
    static let defaultDimension: CGFloat = 1 / 3

    var sizePreferences: [DevToolsDisplay: CGFloat] = [:]

    func dimension(for side: DevToolsDisplay) -> CGFloat { sizePreferences[side] ?? Self.defaultDimension }
}
