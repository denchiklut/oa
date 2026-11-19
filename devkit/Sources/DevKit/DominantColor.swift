import AppKit

/// An image's dominant colour, as the ColorThief port Arc uses finds it: modified median cut quantization (MMCQ)
/// over 5 bits a channel.
public enum DominantColor {
    /// The first of `image`'s five palette colours at least `minimumBrightness` bright (HSB), else the first one, as
    /// Arc's strategy for a Site Search icon. Every `quality`th pixel counts, and none that is mostly transparent or,
    /// with `ignoreWhite`, nearly white. Nil when no pixel counts.
    public static func color(
        of image: NSImage, quality: Int = 10, ignoreWhite: Bool = true, minimumBrightness: Double = 0.15
    ) -> NSColor? {
        guard let pixels = pixels(of: image) else { return nil }
        let palette = MMCQ.palette(of: pixels, quality: quality, ignoreWhite: ignoreWhite, maxColors: 5)
        let bright = palette.first { Double(max($0.r, $0.g, $0.b)) / 255 >= minimumBrightness }
        return (bright ?? palette.first).map {
            NSColor(srgbRed: CGFloat($0.r) / 255, green: CGFloat($0.g) / 255, blue: CGFloat($0.b) / 255, alpha: 1)
        }
    }

    /// RGBA bytes of the image's bitmap at its own pixels, as ColorThief redraws it.
    private static func pixels(of image: NSImage) -> [UInt8]? {
        guard let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil), source.width > 0,
            source.height > 0, let space = CGColorSpace(name: CGColorSpace.sRGB)
        else { return nil }
        var bytes = [UInt8](repeating: 0, count: source.width * source.height * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer in
            guard
                let context = CGContext(
                    data: buffer.baseAddress, width: source.width, height: source.height, bitsPerComponent: 8,
                    bytesPerRow: source.width * 4, space: space,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.draw(source, in: CGRect(x: 0, y: 0, width: source.width, height: source.height))
            return true
        }
        return drawn ? bytes : nil
    }
}

extension NSColor {
    /// HSL lightness lowered by `amount` and clamped, as the `darkened` Arc applies to a Site Search colour.
    public func darkened(byLightness amount: CGFloat) -> NSColor {
        guard let color = usingColorSpace(.extendedSRGB) else { return self }
        let (r, g, b) = (color.redComponent, color.greenComponent, color.blueComponent)
        let high = max(r, g, b)
        let low = min(r, g, b)
        let lightness = (high + low) / 2
        let chroma = high - low
        guard chroma > 0 else {
            let grey = min(max(lightness - amount, 0), 1)
            return NSColor(srgbRed: grey, green: grey, blue: grey, alpha: color.alphaComponent)
        }
        let saturation = chroma / (1 - abs(2 * lightness - 1))
        let darker = min(max(lightness - amount, 0), 1)
        let scale = (1 - abs(2 * darker - 1)) * saturation / chroma
        func channel(_ value: CGFloat) -> CGFloat { darker + (value - lightness) * scale }
        return NSColor(srgbRed: channel(r), green: channel(g), blue: channel(b), alpha: color.alphaComponent)
    }
}

/// ColorThief's quantizer, kept step for step so a favicon gives the colour it gives in Arc.
private enum MMCQ {
    struct Color {
        var r: UInt8
        var g: UInt8
        var b: UInt8
    }

    private static let shift = 3
    private static let side = 1 << (8 - shift)
    private static let fractionByPopulation = 0.75
    private static let maxIterations = 1000

    private static func index(_ r: Int, _ g: Int, _ b: Int) -> Int { (r << 10) + (g << 5) + b }

    private struct Box {
        /// Inclusive bounds per channel, in 5-bit units. A cut can leave a box with `low` one past `high`: empty.
        var low: [Int]
        var high: [Int]

        func range(_ channel: Int) -> Range<Int> { low[channel]..<max(high[channel] + 1, low[channel]) }

        var volume: Int { (0..<3).reduce(1) { $0 * (high[$1] - low[$1] + 1) } }

        func count(_ histogram: [Int]) -> Int {
            var count = 0
            for r in range(0) { for g in range(1) { for b in range(2) { count += histogram[index(r, g, b)] } } }
            return count
        }

        func average(_ histogram: [Int]) -> Color {
            var total = 0
            var sums = [0, 0, 0]
            for r in range(0) {
                for g in range(1) {
                    for b in range(2) {
                        let count = histogram[index(r, g, b)]
                        total += count
                        for (channel, value) in [r, g, b].enumerated() {
                            sums[channel] += Int(Double(count) * (Double(value) + 0.5) * 8)
                        }
                    }
                }
            }
            let channels =
                total > 0
                ? sums.map { $0 / total }
                : (0..<3).map { min(8 * (low[$0] + high[$0] + 1) / 2, 255) }
            return Color(r: UInt8(channels[0]), g: UInt8(channels[1]), b: UInt8(channels[2]))
        }

        var widestChannel: Int {
            let widths = (0..<3).map { high[$0] - low[$0] }
            return widths.firstIndex(of: widths.max() ?? 0) ?? 0
        }
    }

    static func palette(of pixels: [UInt8], quality: Int, ignoreWhite: Bool, maxColors: Int) -> [Color] {
        var histogram = [Int](repeating: 0, count: side * side * side)
        var box = Box(low: [side, side, side], high: [-1, -1, -1])
        for pixel in stride(from: 0, to: pixels.count / 4, by: max(quality, 1)) {
            let (r, g, b, a) = (pixels[pixel * 4], pixels[pixel * 4 + 1], pixels[pixel * 4 + 2], pixels[pixel * 4 + 3])
            guard a >= 125, !(ignoreWhite && r > 250 && g > 250 && b > 250) else { continue }
            let units = [Int(r) >> shift, Int(g) >> shift, Int(b) >> shift]
            for channel in 0..<3 {
                box.low[channel] = min(box.low[channel], units[channel])
                box.high[channel] = max(box.high[channel], units[channel])
            }
            histogram[index(units[0], units[1], units[2])] += 1
        }
        guard box.high[0] >= 0 else { return [] }

        func byCount(_ a: Box, _ b: Box) -> Bool { a.count(histogram) < b.count(histogram) }
        func byProduct(_ a: Box, _ b: Box) -> Bool {
            let (aCount, bCount) = (a.count(histogram), b.count(histogram))
            return aCount == bCount ? a.volume < b.volume : aCount * a.volume < bCount * b.volume
        }
        var queue = [box]
        iterate(&queue, by: byCount, target: Int((fractionByPopulation * Double(maxColors)).rounded(.up)), histogram)
        queue.sort(by: byProduct)
        iterate(&queue, by: byProduct, target: maxColors - queue.count, histogram)
        return queue.reversed().map { $0.average(histogram) }
    }

    private static func iterate(
        _ queue: inout [Box], by areInIncreasingOrder: (Box, Box) -> Bool, target: Int, _ histogram: [Int]
    ) {
        var colors = 1
        for _ in 0..<maxIterations {
            guard let box = queue.last else { return }
            if box.count(histogram) == 0 {
                queue.sort(by: areInIncreasingOrder)
                continue
            }
            queue.removeLast()
            let halves = cut(box, histogram)
            queue.append(contentsOf: halves)
            if halves.count == 2 { colors += 1 }
            queue.sort(by: areInIncreasingOrder)
            if colors >= target { return }
        }
    }

    private static func cut(_ box: Box, _ histogram: [Int]) -> [Box] {
        let count = box.count(histogram)
        guard count > 1 else { return count == 0 ? [] : [box] }
        let axis = box.widestChannel
        let others = [0, 1, 2].filter { $0 != axis }
        var total = 0
        var partialSum = [Int](repeating: -1, count: side)
        for value in box.range(axis) {
            var units = [0, 0, 0]
            units[axis] = value
            for first in box.range(others[0]) {
                for second in box.range(others[1]) {
                    units[others[0]] = first
                    units[others[1]] = second
                    total += histogram[index(units[0], units[1], units[2])]
                }
            }
            partialSum[value] = total
        }
        let (low, high) = (box.low[axis], box.high[axis])
        for value in low...high where partialSum[value] > total / 2 {
            let (left, right) = (value - low, high - value)
            var edge =
                left <= right
                ? min(high - 1, value + right / 2)
                : max(low, Int(Double(value - 1) - Double(left) / 2))
            while edge < 0 || partialSum[edge] <= 0 { edge += 1 }
            while total - partialSum[edge] == 0, edge > 0, partialSum[edge - 1] > 0 { edge -= 1 }
            var (lower, upper) = (box, box)
            lower.high[axis] = edge
            upper.low[axis] = edge + 1
            return [lower, upper]
        }
        return [box]
    }
}
