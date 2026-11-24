import AppKit
import DevKit
import SwiftUI

/// Arc's toast as its views draw it with `newToastBackgroundEnabled` off, which is how Arc ships: the Space
/// theme's colour at 0.8 over a light material with a sheen, the words and key caps of its kind, and for a
/// consumed shortcut the accessory under the card's bottom edge, half a second later. The consumed shortcut's
/// paddings are the ones measured on Arc's, which are a point under the ones its code names.
struct ToastView: View {
    let toast: WindowToast
    let background: WindowTheme.Background
    let onAccessoryTap: () -> Void
    @State private var showsAccessory = false
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let base = background.toastBaseColor
        let isLight = base.hslLightness >= 0.45
        let foreground = isLight ? Color.black : .white
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        content(foreground)
            .fixedSize()
            .padding(.vertical, 10)
            .frame(minHeight: 42)
            .background {
                fill(base, in: shape)
                LinearGradient(
                    colors: isLight
                        ? [.white.opacity(0.4), .white.opacity(0.2)] : [.black.opacity(0.2), .black.opacity(0.4)],
                    startPoint: .top, endPoint: .bottom
                )
                .clipShape(shape)
            }
            .overlay(shape.strokeBorder(.black.opacity(0.3), lineWidth: 1 / displayScale))
            // Cast from a point inside the card and cut out under it, so it doesn't darken the see-through fill.
            .background {
                shape.padding(1)
                    .shadow(color: .black.opacity(0.2), radius: 16, y: 6)
                    .mask {
                        Rectangle().padding(-60).overlay { shape.blendMode(.destinationOut) }.compositingGroup()
                    }
            }
            .overlay(alignment: .bottomTrailing) {
                if case .webContentConsumedHotkey = toast.type {
                    Button(action: onAccessoryTap) {
                        HStack(alignment: .firstTextBaseline, spacing: 2) {
                            Text("Edit the shortcut")
                            Image(systemName: "arrow.up.right")
                        }
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(foreground)
                        .fixedSize()
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background { fill(base, in: RoundedRectangle(cornerRadius: 12)) }
                    }
                    .buttonStyle(.plain)
                    .opacity(showsAccessory ? 1 : 0)
                    .alignmentGuide(.bottom) { $0[.top] }
                    .padding(.trailing, 13)
                    .task {
                        try? await Task.sleep(for: .seconds(0.5))
                        withAnimation(Self.animation) { showsAccessory = true }
                    }
                }
            }
            .foregroundStyle(foreground)
    }

    @ViewBuilder
    private func content(_ foreground: Color) -> some View {
        switch toast.type {
        case .webContentConsumedHotkey(_, let shortcut, let title):
            HStack(spacing: 7.5) {
                keyCap(shortcut.symbols.joined(), foreground, padding: 7.25)
                label("again to \(title)")
            }
            .padding(.leading, 11)
            .padding(.trailing, 11.5)
        case .copyTabURL(let trackingRemoved, let urls):
            let words =
                switch (trackingRemoved, urls.count > 1) {
                case (false, false): "Copied Current URL"
                case (false, true): "Copied URLs"
                case (true, false): "Copied a clean link without trackers"
                case (true, true): "Copied clean links without trackers"
                }
            label(words)
                .padding(.horizontal, 12)
        case .undo(let text):
            HStack(spacing: 6) {
                label("\(text)! Use")
                keyCap("⌘Z", foreground, padding: 8)
                label("to undo.")
            }
            .padding(.horizontal, 12)
        case .tabUnarchived(_, let location):
            label("Tab restored to \(location). Click to view.")
                .padding(.horizontal, 12)
        // As seen in Arc: the singular, for several tabs too.
        case .itemsMoved:
            label("Tab moved! Click to go there.")
                .padding(.horizontal, 12)
        case .zoomChanged(let text):
            label(text)
                .padding(.horizontal, 12)
        }
    }

    private func label(_ text: String) -> some View {
        Text(text).font(.system(size: 14, weight: .medium))
    }

    private func keyCap(_ keys: String, _ foreground: Color, padding: CGFloat) -> some View {
        Text(keys)
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, padding)
            .frame(minHeight: 27)
            .background(foreground.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
    }

    static let animation = Animation.spring(response: 0.4, dampingFraction: 0.7, blendDuration: 0.1)

    private func fill(_ base: NSColor, in shape: RoundedRectangle) -> some View {
        ZStack {
            WindowMaterial(
                material: NSVisualEffectView.Material(rawValue: 1)!, blendingMode: .withinWindow, state: .active)
            Color(nsColor: base).opacity(0.8)
        }
        .clipShape(shape)
    }
}

extension WindowTheme.Background {
    /// Arc's colour for a toast: the theme's own, or the mean of a gradient's base colours, worked in Display P3.
    var toastBaseColor: NSColor {
        let colors: [ThemeColor] =
            switch style {
            case .color(.blendedGradient(let gradient)): gradient.baseColors
            case .color(.blendedSingleColor(let single)): [single.color]
            case .color(.basicColor(let basic)): [basic.color]
            }
        let components = colors.compactMap { color -> [CGFloat]? in
            let color = NSColor(
                colorSpace: .extendedSRGB,
                components: [color.red, color.green, color.blue, 1].map { CGFloat($0) }, count: 4
            ).usingColorSpace(.displayP3)
            return color.map { [$0.redComponent, $0.greenComponent, $0.blueComponent] }
        }
        guard !components.isEmpty else { return .white }
        let mean = (0..<3).map { index in components.reduce(0) { $0 + $1[index] } / CGFloat(components.count) }
        return NSColor(displayP3Red: mean[0], green: mean[1], blue: mean[2], alpha: 1)
    }
}

extension NSColor {
    fileprivate var hslLightness: CGFloat {
        let components = [redComponent, greenComponent, blueComponent]
        return (components.max()! + components.min()!) / 2
    }
}

extension View {
    /// As Arc's toast on a page: 8 pt in from the card's top and right, coming and going on one spring, growing
    /// from a point a tenth of the way down its middle.
    func toast(of model: WindowModel, on page: (any Page)?) -> some View {
        overlay(alignment: .topTrailing) {
            if let page { ToastSlot(model: model, location: .windowContent(page.id), inset: 8) }
        }
    }

    /// As Arc's toast on the window: 4 pt in from its top and right.
    func windowToast(of model: WindowModel) -> some View {
        overlay(alignment: .topTrailing) { ToastSlot(model: model, location: .window, inset: 4) }
    }
}

private struct ToastSlot: View {
    let model: WindowModel
    let location: WindowToast.Location
    let inset: CGFloat
    @Environment(\.windowColorScheme) private var scheme

    var body: some View {
        ZStack {
            if let toast = model.toast, toast.location == location {
                ToastView(toast: toast, background: (model.space.map(model.theme(of:)) ?? .default).background[scheme])
                {
                    model.editShortcut(of: toast)
                }
                .onTapGesture {
                    switch toast.type {
                    case .tabUnarchived(let id, _), .itemsMoved(let id): model.viewRestored(id)
                    default: break
                    }
                }
                .id(toast.id)
                .transition(.scale(scale: 0.001, anchor: UnitPoint(x: 0.5, y: 0.1)).combined(with: .opacity))
            }
        }
        .padding([.top, .trailing], inset)
        .animation(ToastView.animation, value: model.toast?.id)
    }
}
