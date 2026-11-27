import AppKit
import SwiftUI

/// Arc's `SpaceStyleEditorView`, laid out as measured on Arc 1.174: a 356 × 508 body with the 340 pt pad 8 pt in,
/// the Automatic, Light and Dark buttons and − / + inside the pad, the preset row, the intensity wave and the
/// texture dial. Oa draws its own dot grid, icons, knobs and dial.
struct SpaceStyleEditorView: View {
    static let size = CGSize(width: 356, height: 508)
    private static let pad: CGFloat = 340

    let editor: SpaceStyleEditor
    @Binding var presetPage: Int
    let update: ((inout SpaceStyleEditor) -> SpaceStyleEditor.State?) -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            ColorPad(editor: editor, update: update)
                .frame(width: Self.pad, height: Self.pad)
                .offset(x: 8, y: 8)
            PresetRow(page: $presetPage, update: update)
                .frame(width: Self.size.width, height: 32)
                .offset(y: 364)
            IntensityWave(editor: editor, update: update)
                .frame(width: 224, height: 44)
                .offset(x: 18, y: 430)
            NoiseDial(editor: editor, update: update)
                .frame(width: 84, height: 80)
                .offset(x: 258, y: 412)
        }
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
        // As Arc's: AppKit's popover material over the window behind it, so the theme being made shows through.
        .background(WindowMaterial(material: .popover, blendingMode: .behindWindow, state: .active))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .onReceive(NSApplication.shared.publisher(for: \.appearance)) { appearance in
            update {
                $0.onAppearanceUpdated(appearance?.name)
                return nil
            }
        }
    }
}

/// Arc's pad: a tap or drag anywhere sets the key colour, even over a companion's knob.
private struct ColorPad: View {
    let editor: SpaceStyleEditor
    let update: ((inout SpaceStyleEditor) -> SpaceStyleEditor.State?) -> Void
    @State private var isDragging = false

    var body: some View {
        let unit: CGFloat = 170
        ZStack {
            DotGrid()
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            isDragging = true
                            let point = CGPoint(
                                x: (value.location.x - unit) / unit, y: (value.location.y - unit) / unit)
                            update {
                                $0.didDragColorKnob(to: point)
                                return nil
                            }
                        }
                        .onEnded { _ in
                            isDragging = false
                            update { $0.didEndGesture() }
                        })
            if editor.state.primaryColor == nil {
                Text(SpaceStyleEditor.emptyStateText)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .allowsHitTesting(false)
            }
            let knobs = editor.knobs
            ZStack {
                ForEach(knobs.indices.reversed(), id: \.self) { index in
                    ColorKnob(color: knobs[index].color, isPrimary: index == 0)
                        .position(x: unit + knobs[index].point.x * unit, y: unit + knobs[index].point.y * unit)
                }
            }
            .allowsHitTesting(false)
            // As measured on Arc: a preset's knob glides to its place in about 0.11 s; a drag's follows the pointer.
            .animation(
                isDragging ? nil : .spring(response: 0.25, dampingFraction: 0.9),
                value: knobs.map { [$0.point.x, $0.point.y] })
            AppearanceToggle(editor: editor)
                .position(x: 170, y: 40)
            HStack(spacing: 8) {
                PadButton(symbol: "minus", help: "Remove color", label: "Remove", isEnabled: editor.canRemoveColor) {
                    update { $0.didRemoveColor() }
                }
                PadButton(symbol: "plus", help: "Add color", label: "Add", isEnabled: editor.canAddColor) {
                    update { $0.didAddColor() }
                }
            }
            .position(x: 170, y: 308)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

/// Oa's own grid, after Arc's: 1 pt dots 4.25 pt apart, 80 across the pad.
private struct DotGrid: View {
    var body: some View {
        Canvas { context, size in
            let spacing: CGFloat = 4.25
            var dots = Path()
            var y = spacing / 2
            while y < size.height {
                var x = spacing / 2
                while x < size.width {
                    dots.addEllipse(in: CGRect(x: x - 0.5, y: y - 0.5, width: 1, height: 1))
                    x += spacing
                }
                y += spacing
            }
            context.fill(dots, with: .style(.primary.opacity(0.14)))
        }
        .background(.primary.opacity(0.03))
    }
}

/// As measured on Arc: the key's knob is a 35 pt disc in a 5 pt white ring, a companion's a 21 pt one in 3 pt.
private struct ColorKnob: View {
    let color: EditorColor
    let isPrimary: Bool

    var body: some View {
        let (disc, ring): (CGFloat, CGFloat) = isPrimary ? (35, 5) : (21, 3)
        Circle()
            .fill(Color(nsColor: color.nsColor))
            .frame(width: disc, height: disc)
            .padding(ring)
            .background(.white, in: Circle())
            .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
    }
}

/// Arc's three buttons over the pad. They set the app's appearance, as View ▸ Appearance does, and leave the theme
/// alone; the lit one is the app's.
private struct AppearanceToggle: View {
    let editor: SpaceStyleEditor

    var body: some View {
        let state = editor.state
        HStack(spacing: 8) {
            PadButton(
                symbol: "sparkles", help: "Automatic Appearance",
                isSelected: state.hasAppeared && state.appearance == nil
            ) { AppAppearance.set(nil) }
            PadButton(symbol: "sun.max", help: "Light Appearance", isSelected: state.appearance == .aqua) {
                AppAppearance.set(.aqua)
            }
            PadButton(symbol: "moon.stars", help: "Dark Appearance", isSelected: state.appearance == .darkAqua) {
                AppAppearance.set(.darkAqua)
            }
        }
    }
}

/// As measured on Arc: 32 pt square buttons with a 16 pt glyph; hover draws the fill a lit one has.
private struct PadButton: View {
    let symbol: String
    let help: String
    var label: String?
    var isSelected = false
    var isEnabled = true
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .medium))
                .frame(width: 32, height: 32)
                .background(
                    .primary.opacity(isSelected || (isHovered && isEnabled) ? 0.1 : 0),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary.opacity(isEnabled ? 0.8 : 0.25))
        .disabled(!isEnabled)
        .onHover { isHovered = $0 }
        .oaToolTip(help)
        .accessibilityLabel(label ?? help)
    }
}

/// Arc's preset row: nine swatches a page between ‹ and ›, the window's page shared by its editors.
private struct PresetRow: View {
    @Binding var page: Int
    let update: ((inout SpaceStyleEditor) -> SpaceStyleEditor.State?) -> Void

    private static let pitch: CGFloat = 29.5
    private static let pageWidth = pitch * 9

    var body: some View {
        let pages = SpaceStyleEditor.presetPages
        ZStack(alignment: .topLeading) {
            pageButton("chevron.left", label: "Move to previous preset page.", to: page - 1)
                .position(x: 24.5, y: 16)
            HStack(spacing: 0) {
                ForEach(pages.indices, id: \.self) { index in
                    HStack(spacing: 0) {
                        ForEach(pages[index], id: \.self) { set in
                            Swatch(set: set) { update { $0.didSelectColorSet(set) } }
                                .frame(width: Self.pitch, height: 32)
                        }
                    }
                }
            }
            .offset(x: -CGFloat(page) * Self.pageWidth)
            .frame(width: Self.pageWidth, height: 32, alignment: .leading)
            .clipped()
            .offset(x: 48 - (Self.pitch - 24) / 2)
            pageButton("chevron.right", label: "Move to next preset page.", to: page + 1)
                .position(x: 331.5, y: 16)
        }
    }

    private func pageButton(_ symbol: String, label: String, to target: Int) -> some View {
        let isEnabled = SpaceStyleEditor.presetPages.indices.contains(target)
        return Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.63)) { page = target }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .medium))
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary.opacity(isEnabled ? 0.6 : 0.2))
        .disabled(!isEnabled)
        .accessibilityLabel(label)
    }
}

private struct Swatch: View {
    let set: SpaceStyleEditor.ColorSet
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(
                    LinearGradient(
                        colors: set.colors.map { Color(nsColor: $0.nsColor) }, startPoint: .topLeading,
                        endPoint: .bottomTrailing)
                )
                .overlay(Circle().strokeBorder(.black.opacity(0.08), lineWidth: 1))
                .frame(width: 24, height: 24)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Set space color")
    }
}

/// Arc's `SineSlider`: the wave grows with the value, strong up to the knob and faint after it, and the knob widens
/// from 12 × 45 pt at 0 to 26 × 58 at 1, as measured. With no colour it has no knob.
private struct IntensityWave: View {
    let editor: SpaceStyleEditor
    let update: ((inout SpaceStyleEditor) -> SpaceStyleEditor.State?) -> Void

    var body: some View {
        let value = editor.state.intensityFactor
        let hasColor = editor.state.primaryColor != nil
        let knob = CGSize(width: 12 + 14 * value, height: 45 + 13 * value)
        let knobX = knob.width / 2 + (224 - knob.width) * value
        ZStack(alignment: .leading) {
            Capsule()
                .fill(.primary.opacity(0.08))
                .frame(height: 16)
            Wave(amplitude: 15 * value)
                .stroke(.primary.opacity(hasColor ? 0.2 : 0.15), style: StrokeStyle(lineWidth: 4, lineCap: .round))
            if hasColor {
                Wave(amplitude: 15 * value)
                    .stroke(.primary.opacity(0.55), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .mask(alignment: .leading) { Rectangle().frame(width: knobX) }
                Capsule()
                    .fill(.white)
                    .frame(width: knob.width, height: knob.height)
                    .shadow(color: .black.opacity(0.2), radius: 3, y: 1)
                    .position(x: knobX, y: 22)
            }
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { drag in
                    let value = (drag.location.x - 12) / 200
                    update {
                        $0.didUpdateIntensityFactor(value)
                        return nil
                    }
                }
                .onEnded { _ in update { $0.didEndGesture() } }
        )
        .allowsHitTesting(hasColor)
        .oaToolTip("Intensity")
        .accessibilityElement()
        .accessibilityLabel("Intensity")
        .accessibilityValue("\(Int((value * 100).rounded()))%")
    }
}

private struct Wave: Shape {
    let amplitude: CGFloat

    func path(in rect: CGRect) -> Path {
        let padding: CGFloat = 8
        let period: CGFloat = 38
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + padding, y: rect.midY))
        var x = rect.minX + padding
        while x <= rect.maxX - padding {
            path.addLine(
                to: CGPoint(x: x, y: rect.midY - sin((x - rect.minX - padding) / period * 2 * .pi) * amplitude))
            x += 1
        }
        return path
    }
}

/// Arc's noise dial, as measured: 20 dots every 18° on a 32 pt radius, lit from the top round to the knob, a white
/// pill on the ring, and a 39 pt centre that shows the texture. A drag round it sets the noise, a click on the ring
/// sets it there, and a click on the centre cycles the texture.
private struct NoiseDial: View {
    let editor: SpaceStyleEditor
    let update: ((inout SpaceStyleEditor) -> SpaceStyleEditor.State?) -> Void
    @State private var isDragging = false
    @Environment(\.displayScale) private var displayScale

    private static let radius: CGFloat = 32
    private static let centre = CGPoint(x: 42, y: 40)

    var body: some View {
        let state = editor.state
        let hasColor = state.primaryColor != nil
        let noise = state.noiseFactor
        ZStack {
            ForEach(0..<20, id: \.self) { index in
                let fraction = Double(index) / 20
                let angle = (fraction * 360 - 90) * .pi / 180
                Circle()
                    .fill(.primary.opacity(hasColor && noise > 0 && fraction <= noise ? 0.6 : 0.2))
                    .frame(width: 5, height: 5)
                    .position(
                        x: Self.centre.x + cos(angle) * Self.radius, y: Self.centre.y + sin(angle) * Self.radius)
            }
            disc(hasColor && noise > 0 ? state.overlay : nil)
                .frame(width: 39, height: 39)
                .position(Self.centre)
            if hasColor {
                Capsule()
                    .fill(.white)
                    .frame(width: 8, height: 16)
                    .shadow(color: .black.opacity(0.2), radius: 1)
                    .offset(y: -Self.radius)
                    .rotationEffect(.degrees(noise * 360))
                    .position(Self.centre)
            }
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { drag in
                    guard isDragging || hypot(drag.translation.width, drag.translation.height) > 3 else { return }
                    isDragging = true
                    let value = fraction(at: drag.location)
                    update { $0.didUpdateNoiseFactor(value, .drag) }
                }
                .onEnded { drag in
                    if isDragging {
                        isDragging = false
                        return update { $0.didEndGesture() }
                    }
                    let distance = hypot(drag.location.x - Self.centre.x, drag.location.y - Self.centre.y)
                    if distance <= 19.5 {
                        update { $0.didTapNoiseKnob() }
                    } else {
                        let value = fraction(at: drag.location)
                        update { $0.didUpdateNoiseFactor(value, .dialClick) }
                    }
                }
        )
        .allowsHitTesting(hasColor)
        .oaToolTip("Cycle noise texture")
        .accessibilityElement()
        .accessibilityLabel("Cycle noise texture")
        .accessibilityValue("\(Int((noise * 100).rounded()))%")
    }

    /// As Arc's dial: a full turn from the top, clockwise, is 1.
    private func fraction(at point: CGPoint) -> Double {
        var fraction = (atan2(point.y - Self.centre.y, point.x - Self.centre.x) + .pi / 2) / (2 * .pi)
        if fraction < 0 { fraction += 1 }
        return fraction
    }

    @ViewBuilder private func disc(_ overlay: WindowTheme.Overlay?) -> some View {
        if let overlay {
            Circle()
                .fill(.primary.opacity(0.2))
                .overlay {
                    Image(decorative: WindowTexture.image(overlay), scale: displayScale)
                        .resizable(resizingMode: .tile)
                        .blendMode(.multiply)
                }
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.2), lineWidth: 1))
        } else {
            Circle().strokeBorder(.primary.opacity(0.2), lineWidth: 1)
        }
    }
}
