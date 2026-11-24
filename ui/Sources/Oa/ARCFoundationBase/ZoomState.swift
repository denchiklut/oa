/// Arc's `ZoomState`: a cursor on Arc's own presets, Chromium's list but with 0.33 and 0.67 for a third and two
/// thirds.
struct ZoomState: Equatable {
    static let presets: [Float] = [0.25, 0.33, 0.5, 0.67, 0.75, 0.8, 0.9, 1, 1.1, 1.25, 1.5, 1.75, 2, 2.5, 3, 4, 5]

    private(set) var cursor = ZoomState.presets.firstIndex(of: 1)!

    init() {}

    /// The preset nearest to the factor, the first on a tie, as Arc's.
    init(factor: Float) {
        cursor = Self.presets.indices.min { abs(Self.presets[$0] - factor) < abs(Self.presets[$1] - factor) }!
    }

    var factor: Float { Self.presets[cursor] }
    var isAtMin: Bool { cursor == 0 }
    var isAtMax: Bool { cursor == Self.presets.count - 1 }
    var isActualSize: Bool { factor == 1 }

    mutating func zoomIn() { cursor = min(cursor + 1, Self.presets.count - 1) }
    mutating func zoomOut() { cursor = max(cursor - 1, 0) }
}
