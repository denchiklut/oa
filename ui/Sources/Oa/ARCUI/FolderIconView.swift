import AppKit
import QuartzCore
import SwiftUI

enum FolderIconState: Equatable {
    case collapsed
    case expanded
    case peekedOpen
    case peekedClosed
}

struct FolderIcon: NSViewRepresentable {
    static let size = CGSize(width: 17, height: 17)

    let state: FolderIconState
    let customIcon: String?
    let theme: Theme

    func makeNSView(context: Context) -> FolderIconNSView {
        let view = FolderIconNSView(frame: CGRect(origin: .zero, size: Self.size))
        view.configure(state: state, customIcon: customIcon, theme: theme, animated: false)
        return view
    }

    func updateNSView(_ view: FolderIconNSView, context: Context) {
        view.configure(state: state, customIcon: customIcon, theme: theme, animated: true)
    }
}

@MainActor
final class FolderIconNSView: NSView {
    private let backContainerLayer = CALayer()
    private let backPathLayer = CAShapeLayer()
    private let backShadingLayer = CAGradientLayer()
    private let backShadingMask = CAShapeLayer()

    private let frontContainerLayer = CALayer()
    private let frontPathLayer = CAShapeLayer()
    private let frontShadingLayer = CAGradientLayer()
    private let customIconLayer = CALayer()
    private let customIconMask = CALayer()
    private let ellipsisLayer = CALayer()
    private let ellipsisMask = CALayer()

    private var currentState: FolderIconState = .collapsed
    private var currentCustomIcon: String?
    private var currentTheme: Theme?
    private var lastLayoutSize = CGSize.zero
    private var lastScale: CGFloat = 0

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        setupLayers()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func setupLayers() {
        guard let root = layer else { return }
        root.masksToBounds = false

        backContainerLayer.anchorPoint = CGPoint(x: 0, y: 1)
        backContainerLayer.masksToBounds = false
        backPathLayer.lineJoin = .round
        backPathLayer.lineCap = .round

        backShadingLayer.colors = [
            NSColor.black.withAlphaComponent(0).cgColor,
            NSColor.black.withAlphaComponent(0.36).cgColor,
        ]
        backShadingLayer.startPoint = CGPoint(x: 0, y: 0)
        backShadingLayer.endPoint = CGPoint(x: 0.6, y: 1)
        backShadingLayer.mask = backShadingMask

        backContainerLayer.addSublayer(backPathLayer)
        backContainerLayer.addSublayer(backShadingLayer)

        frontContainerLayer.anchorPoint = CGPoint(x: 0, y: 1)
        frontContainerLayer.masksToBounds = false
        frontPathLayer.lineJoin = .round
        frontPathLayer.lineCap = .round

        frontShadingLayer.colors = [
            NSColor.black.withAlphaComponent(0).cgColor,
            NSColor.black.withAlphaComponent(0.15).cgColor,
        ]
        frontShadingLayer.startPoint = CGPoint(x: 0.1, y: 0)
        frontShadingLayer.endPoint = CGPoint(x: 0.9, y: 1)

        customIconMask.contentsGravity = .resizeAspect
        customIconLayer.mask = customIconMask

        ellipsisMask.contentsGravity = .resizeAspect
        ellipsisMask.contents = Self.ellipsisImage
        ellipsisLayer.mask = ellipsisMask

        frontContainerLayer.addSublayer(frontPathLayer)
        frontContainerLayer.addSublayer(frontShadingLayer)
        frontContainerLayer.addSublayer(customIconLayer)
        frontContainerLayer.addSublayer(ellipsisLayer)

        root.addSublayer(backContainerLayer)
        root.addSublayer(frontContainerLayer)
    }

    func configure(state: FolderIconState, customIcon: String?, theme: Theme, animated: Bool) {
        let stateChanged = state != currentState
        let iconChanged = customIcon != currentCustomIcon
        currentState = state
        currentCustomIcon = customIcon
        currentTheme = theme

        if iconChanged {
            customIconMask.contents = customIcon.flatMap(Self.customIconImage(for:))
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        updateGeometryIfNeeded()
        updateColors(theme: theme)
        CATransaction.commit()

        applyState(state, animated: animated && stateChanged)
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        updateGeometryIfNeeded()
        if let currentTheme { updateColors(theme: currentTheme) }
        applyState(currentState, animated: false)
        CATransaction.commit()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        guard let currentTheme else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        updateColors(theme: currentTheme)
        CATransaction.commit()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        updateGeometryIfNeeded()
        CATransaction.commit()
    }

    private func pixelAligned(_ value: CGFloat, scale: CGFloat) -> CGFloat {
        (value * scale).rounded() / scale
    }

    private func updateGeometryIfNeeded() {
        let w = bounds.width
        let h = bounds.height
        let scale = window?.backingScaleFactor ?? 2
        guard w > 0, h > 0, bounds.size != lastLayoutSize || scale != lastScale else { return }
        lastLayoutSize = bounds.size
        lastScale = scale

        let r = (w / 7).rounded()
        let lineWidth = pixelAligned(1.25, scale: scale)
        let tabHeight = pixelAligned((h * 0.25).rounded(), scale: scale)
        let notchY = floor(tabHeight / 1.5)

        let backPath = CGMutablePath()
        backPath.move(to: CGPoint(x: r, y: 0))
        backPath.addLine(to: CGPoint(x: 0.42 * w, y: 0))
        backPath.addLine(to: CGPoint(x: 0.58 * w, y: notchY))
        backPath.addLine(to: CGPoint(x: w - r, y: notchY))
        backPath.addArc(tangent1End: CGPoint(x: w, y: notchY), tangent2End: CGPoint(x: w, y: h), radius: r)
        backPath.addArc(tangent1End: CGPoint(x: w, y: h), tangent2End: CGPoint(x: 0, y: h), radius: r)
        backPath.addArc(tangent1End: CGPoint(x: 0, y: h), tangent2End: CGPoint(x: 0, y: 0), radius: r)
        backPath.addArc(tangent1End: CGPoint(x: 0, y: 0), tangent2End: CGPoint(x: w, y: 0), radius: r)
        backPath.closeSubpath()

        let frontRect = CGRect(x: 0, y: tabHeight, width: w, height: h - tabHeight)
        let frontPath = CGPath(roundedRect: frontRect, cornerWidth: r, cornerHeight: r, transform: nil)

        for container in [backContainerLayer, frontContainerLayer] {
            let saved = container.transform
            container.transform = CATransform3DIdentity
            container.bounds = CGRect(origin: .zero, size: bounds.size)
            container.position = CGPoint(x: 0, y: h)
            container.transform = saved
        }

        backPathLayer.frame = bounds
        backPathLayer.path = backPath
        backPathLayer.lineWidth = lineWidth
        backPathLayer.contentsScale = scale

        backShadingLayer.frame = bounds
        backShadingLayer.contentsScale = scale
        backShadingMask.frame = bounds
        backShadingMask.path = backPath
        backShadingMask.contentsScale = scale

        frontPathLayer.frame = bounds
        frontPathLayer.path = frontPath
        frontPathLayer.lineWidth = lineWidth
        frontPathLayer.contentsScale = scale

        frontShadingLayer.frame = frontRect
        frontShadingLayer.cornerRadius = r
        frontShadingLayer.contentsScale = scale

        let iconSide = max(0, min(frontRect.width - 2.5, frontRect.height - 2.5))
        let iconFrame = CGRect(
            x: frontRect.midX - iconSide / 2, y: frontRect.midY - iconSide / 2, width: iconSide, height: iconSide)
        customIconLayer.frame = iconFrame
        customIconLayer.contentsScale = scale
        customIconMask.frame = customIconLayer.bounds
        customIconMask.contentsScale = scale

        let ellipsisSide = min(frontRect.width, frontRect.height)
        let ellipsisFrame = CGRect(
            x: frontRect.midX - ellipsisSide / 2, y: frontRect.midY - ellipsisSide / 2, width: ellipsisSide,
            height: ellipsisSide)
        ellipsisLayer.frame = ellipsisFrame
        ellipsisLayer.contentsScale = scale
        ellipsisMask.frame = ellipsisLayer.bounds
        ellipsisMask.contentsScale = scale
    }

    private func updateColors(theme: Theme) {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let stroke = NSColor(theme.maxContrast).cgColor
            let backFill = NSColor(theme.folderBackFill).cgColor
            let frontFill = NSColor(theme.cutout).cgColor
            backPathLayer.strokeColor = stroke
            backPathLayer.fillColor = backFill
            frontPathLayer.strokeColor = stroke
            frontPathLayer.fillColor = frontFill
            customIconLayer.backgroundColor = stroke
            ellipsisLayer.backgroundColor = stroke
        }
    }

    private func applyState(_ state: FolderIconState, animated: Bool) {
        let tx: CGFloat
        let rotY: CGFloat
        let frontRotX: CGFloat
        let backRotX: CGFloat
        let isOpen: Bool
        let isPeeked: Bool

        switch state {
        case .collapsed:
            (tx, rotY, frontRotX, backRotX, isOpen, isPeeked) = (0, 0, 0, 0, false, false)
        case .expanded:
            (tx, rotY, frontRotX, backRotX, isOpen, isPeeked) = (3, 32, -30, 28, true, false)
        case .peekedOpen:
            (tx, rotY, frontRotX, backRotX, isOpen, isPeeked) = (1.5, 16, -15, 14, true, true)
        case .peekedClosed:
            (tx, rotY, frontRotX, backRotX, isOpen, isPeeked) = (0, 0, 0, 0, false, true)
        }

        func transform(rotX: CGFloat) -> CATransform3D {
            var t = CATransform3DIdentity
            t.m34 = -1 / 350
            t = CATransform3DTranslate(t, tx, 0, 0)
            t = CATransform3DRotate(t, rotY * .pi / 180, 0, 1, 0)
            t = CATransform3DRotate(t, rotX * .pi / 180, 1, 0, 0)
            return t
        }

        CATransaction.begin()
        CATransaction.setDisableActions(!animated)
        frontContainerLayer.transform = transform(rotX: frontRotX)
        backContainerLayer.transform = transform(rotX: backRotX)
        frontShadingLayer.opacity = isOpen ? 1 : 0
        backShadingLayer.opacity = isOpen ? 1 : 0.2
        ellipsisLayer.opacity = isPeeked ? 1 : 0
        customIconLayer.opacity = !isPeeked && currentCustomIcon != nil ? 1 : 0
        CATransaction.commit()
    }

    private static var iconCache: [String: CGImage] = [:]

    private static let ellipsisImage: CGImage? = {
        let config = NSImage.SymbolConfiguration(pointSize: 10, weight: .heavy)
        guard
            let symbol = NSImage(systemSymbolName: "ellipsis", accessibilityDescription: nil)?
                .withSymbolConfiguration(config)
        else { return nil }
        return renderMask(from: symbol, size: CGSize(width: 13, height: 13))
    }()

    /// Renders either an SF Symbol or an emoji into a 2× alpha mask so `TintableImageLayer`-style masking tints both
    /// uniformly in `strokeColor`, matching Arc's `FolderIconView`.
    private static func customIconImage(for icon: String) -> CGImage? {
        if let cached = iconCache[icon] { return cached }
        let image: CGImage?
        if icon == "github", let url = Bundle.module.url(forResource: "mark-github", withExtension: "svg"),
            let mark = NSImage(contentsOf: url)
        {
            image = renderMask(from: mark, size: CGSize(width: 16, height: 16))
        } else if icon.allSatisfy(\.isASCII) {
            let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
            if let symbol = NSImage(systemSymbolName: icon, accessibilityDescription: nil)?
                .withSymbolConfiguration(config)
            {
                image = renderMask(from: symbol, size: CGSize(width: 16, height: 16))
            } else {
                image = nil
            }
        } else {
            let size = CGSize(width: 16, height: 16)
            let rendered = NSImage(size: size, flipped: false) { rect in
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 13),
                    .foregroundColor: NSColor.black,
                ]
                let text = NSAttributedString(string: icon, attributes: attrs)
                let textSize = text.size()
                text.draw(
                    at: NSPoint(x: (rect.width - textSize.width) / 2, y: (rect.height - textSize.height) / 2))
                return true
            }
            image = rendered.cgImage(forProposedRect: nil, context: nil, hints: nil)
        }
        if let image { iconCache[icon] = image }
        return image
    }

    private static func renderMask(from image: NSImage, size: CGSize) -> CGImage? {
        let rendered = NSImage(size: size, flipped: false) { rect in
            let aspect = image.size.height > 0 ? image.size.width / image.size.height : 1
            let drawSize =
                aspect >= 1
                ? CGSize(width: rect.width, height: rect.width / aspect)
                : CGSize(width: rect.height * aspect, height: rect.height)
            let target = CGRect(
                x: (rect.width - drawSize.width) / 2, y: (rect.height - drawSize.height) / 2, width: drawSize.width,
                height: drawSize.height)
            image.draw(in: target)
            return true
        }
        return rendered.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }
}
