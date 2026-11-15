#!/usr/bin/env swift
import AppKit
import simd

// Oa's original textures. Fixed seeds keep regeneration reproducible; the app only loads the resulting PNGs.
private enum Texture: String, CaseIterable {
    case grain, sand, denim, tweed

    var seed: UInt64 {
        switch self {
        case .grain: 1
        case .sand: 4
        case .denim: 2
        case .tweed: 3
        }
    }
}

// SplitMix64 supplies a stable sequence without depending on Swift's random-number distribution implementation.
private struct Random {
    var state: UInt64

    mutating func next() -> UInt64 {
        state &+= 0x9e3779b97f4a7c15
        var value = state
        value = (value ^ (value >> 30)) &* 0xbf58476d1ce4e5b9
        value = (value ^ (value >> 27)) &* 0x94d049bb133111eb
        return value ^ (value >> 31)
    }
}

private enum TextureGenerator {
    private static let side = 200

    static func image(_ overlay: Texture) -> CGImage {
        var random = Random(state: overlay.seed)
        func unit() -> Double { Double(random.next() >> 11) * 0x1p-53 }
        func standardized(_ field: [Double]) -> [Double] {
            let average = field.reduce(0, +) / Double(field.count)
            let scale = (field.reduce(0) { $0 + ($1 - average) * ($1 - average) } / Double(field.count)).squareRoot()
            return field.map { ($0 - average) / scale }
        }
        func softened(_ field: [Double], _ spread: (x: Double, y: Double), passes: Int = 1) -> [Double] {
            var field = field
            for _ in 0..<passes {
                for (step, spread) in [(1, spread.x), (side, spread.y)] {
                    let row = step == 1 ? side : side * side
                    field = field.indices.map { index in
                        let line = index / row * row
                        let before = line + (index - line - step + row) % row
                        let after = line + (index - line + step) % row
                        return field[index] + spread * (field[before] + field[after])
                    }
                }
            }
            return standardized(field)
        }
        func noise(_ spread: (x: Double, y: Double), passes: Int = 1) -> [Double] {
            softened(
                (0..<side * side).map { _ in (0..<4).reduce(0.0) { sum, _ in sum + unit() } }, spread, passes: passes)
        }
        func broadNoise(radius: Int) -> [Double] {
            var field = (0..<side * side).map { _ in (0..<4).reduce(0.0) { sum, _ in sum + unit() } }
            // Sliding box filters give the broad variations without dozens of full-resolution softening passes.
            for _ in 0..<3 {
                for (step, lineStep) in [(1, side), (side, 1)] {
                    var blurred = field
                    for line in 0..<side {
                        let start = line * lineStep
                        var sum = (-radius...radius).reduce(0.0) { sum, offset in
                            sum + field[start + (offset + side) % side * step]
                        }
                        for position in 0..<side {
                            blurred[start + position * step] = sum / Double(2 * radius + 1)
                            sum +=
                                field[start + (position + radius + 1) % side * step]
                                - field[start + (position - radius + side) % side * step]
                        }
                    }
                    field = blurred
                }
            }
            return standardized(field)
        }
        func pebbles() -> [Double] {
            let count = 45
            let pitch = Double(side) / Double(count)
            let seeds = (0..<count * count).map { index in
                (
                    x: (Double(index % count) + 1.25 * unit() - 0.125) * pitch,
                    y: (Double(index / count) + 1.25 * unit() - 0.125) * pitch, tone: 1 - 0.1 * unit()
                )
            }
            return (0..<side * side).map { index in
                let x = Double(index % side) + 0.5
                let y = Double(index / side) + 0.5
                var nearest = (distance: Double.infinity, tone: 0.0, offset: SIMD2<Double>.zero)
                var neighbors: [SIMD2<Double>] = []
                var next = Double.infinity
                for row in -2...2 {
                    for column in -2...2 {
                        let seed = seeds[
                            (Int(y / pitch) + row + count) % count * count + (Int(x / pitch) + column + count) % count]
                        var offset = SIMD2(seed.x - x, seed.y - y)
                        offset.x -= Double(side) * (offset.x / Double(side)).rounded()
                        offset.y -= Double(side) * (offset.y / Double(side)).rounded()
                        neighbors.append(offset)
                        let distance = simd_length(offset)
                        if distance < nearest.distance {
                            (next, nearest) = (nearest.distance, (distance, seed.tone, offset))
                        } else if distance < next {
                            next = distance
                        }
                    }
                }
                // Close seeds can darken a whole pebble; distance to the cell boundary limits those spots.
                let boundary = neighbors.reduce(Double.infinity) { boundary, offset in
                    let separation = simd_distance(offset, nearest.offset)
                    guard separation > 0.000001 else { return boundary }
                    let distance =
                        (simd_length_squared(offset) - nearest.distance * nearest.distance) / (2 * separation)
                    return min(boundary, max(0, distance))
                }
                let inside = min(max((next - nearest.distance) / 2.1, boundary / 2.6), 1)
                return nearest.tone * cbrt(inside * inside * (3 - 2 * inside)) + 0.06 * unit()
            }
        }
        func wave(_ index: Int, _ across: Double, _ down: Double, drift: Double = 0) -> Double {
            cos(2 * .pi * (Double(index % side) * across + Double(index / side) * down) / Double(side) + drift)
        }
        let alpha: Double
        let channels: [[Double]]
        switch overlay {
        case .grain:
            // Arc's grain is a faint film: each channel its own noise.
            alpha = 0.26
            channels = (0..<3).map { _ in noise((0.27, 0.27)).map { 0.735 + 0.24 * $0 } }
        case .sand:
            alpha = 1
            channels = [softened(pebbles(), (0.2, 0.2)).map { 0.658 + 0.207 * $0 }]
        case .denim:
            // A twill: diagonal ribs five texels apart.
            alpha = 1
            let fine = noise((0.2, 0.2))
            channels = [fine.indices.map { 0.841 + 0.022 * fine[$0] + 0.062 * wave($0, 40, -44) }]
        case .tweed:
            alpha = 1
            let fine = noise((0.17, 0.22))
            let medium = noise((0.5, 0.5), passes: 12)
            let broad = broadNoise(radius: 7)
            let drift = [broadNoise(radius: 6), broadNoise(radius: 6)]
            // Crossing threads preserve Arc's five-pixel and eight-pixel repeats in both directions.
            let weave = standardized(
                fine.indices.map { index in
                    fine[index] + 0.36 * medium[index] + 0.22 * broad[index]
                        + 0.74 * wave(index, 38, 0, drift: 0.18 * drift[0][index])
                        * wave(index, 0, 25, drift: 0.18 * drift[1][index])
                })
            channels = [
                standardized(weave.map { $0 - 0.04 * ($0 * $0 - 1) }).map { 0.7075 + 0.046 * $0 }
            ]
        }
        let pixels = (0..<side * side).flatMap { index in
            (0..<3).map { UInt8(min(max(channels[$0 % channels.count][index], 0), 1) * alpha * 255) }
                + [UInt8(alpha * 255)]
        }
        let image = CGImage(
            width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: side * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: CGDataProvider(data: Data(pixels) as CFData)!, decode: nil, shouldInterpolate: true,
            intent: .defaultIntent)!
        return image
    }
}

guard CommandLine.arguments.count <= 2 else {
    fatalError("usage: swift scripts/generate_theme_textures.swift [output-directory]")
}
let output =
    CommandLine.arguments.count == 2
    ? URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    : URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("ui/Sources/Oa/Resources/ThemeTextures", isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for texture in Texture.allCases {
    let image = TextureGenerator.image(texture)
    let bitmap = NSBitmapImageRep(cgImage: image)
    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        fatalError("could not encode \(texture.rawValue)")
    }
    try png.write(to: output.appendingPathComponent("\(texture.rawValue).png"), options: .atomic)
}
