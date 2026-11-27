import AppKit
import DevKit
import SwiftUI
import UniformTypeIdentifiers

private enum PortraitBackground: String {
    case website, wallpaper, custom
}

private struct PortraitSettings: DynamicProperty {
    @AppStorage("portraitCaptureBackground") var background = PortraitBackground.custom
    @AppStorage("portraitCaptureColorPercentage") var hue = 0.59
    @AppStorage("portraitCaptureHidesWatermark") var hidesWatermark = false

    static let stops: [Color] = [.pink.opacity(0.3), .pink, .red, .orange, .yellow, .green, .cyan, .blue, .indigo]
    var sliderPosition: Double {
        get { min(1, ((hue + 0.13).truncatingRemainder(dividingBy: 1)) / 0.82) }
        nonmutating set {
            hue = (0.87 + min(1, max(0, newValue)) * 0.82).truncatingRemainder(dividingBy: 1)
            background = .custom
        }
    }
}

@MainActor
struct PortraitCapture {
    fileprivate static let previewSize = CGSize(width: 240, height: 128)
    let image: CGImage
    let websiteColor: NSColor
    let wallpaper: NSImage?
    let host: String?

    init?(snapshot: NSImage?, page: any Page, colors: TopBarColorClient) {
        guard let image = snapshot?.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        self.image = image
        websiteColor =
            colors.appliedColor(for: page)
            ?? NSBitmapImageRep(cgImage: image).colorAt(x: image.width - 1, y: min(1, image.height - 1))
            ?? colors.startingColor(for: page)
        wallpaper = page.view.window?.screen.flatMap(NSWorkspace.shared.desktopImageURL(for:)).flatMap(
            NSImage.init(contentsOf:))
        host = page.url?.host()
    }

    fileprivate func artwork(width: CGFloat, settings: PortraitSettings, preview: Bool = false) -> some View {
        let height = width * Self.previewSize.height / Self.previewSize.width
        let inset = height * 0.10
        return ZStack(alignment: .bottomLeading) {
            Color(nsColor: websiteColor)
            if settings.background == .wallpaper, let wallpaper {
                Image(nsImage: wallpaper).resizable().scaledToFill().frame(width: width, height: height).clipped()
            } else if settings.background == .custom {
                LinearGradient(
                    colors: [
                        Color(
                            hue: (settings.hue + 0.94).truncatingRemainder(dividingBy: 1), saturation: 0.40,
                            brightness: 0.94),
                        Color(hue: settings.hue, saturation: 0.50, brightness: 0.76),
                    ], startPoint: .topLeading, endPoint: .bottomTrailing)
            }
            Image(decorative: image, scale: 1)
                .resizable().scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: width * 0.008))
                .padding(width * 0.01)
                .background(.white.opacity(0.55), in: RoundedRectangle(cornerRadius: width * 0.018))
                .shadow(color: .black.opacity(0.25), radius: width * 0.02, y: width * 0.008)
                .padding(inset)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if !preview && !settings.hidesWatermark {
                Text("Oa")
                    .font(.system(size: inset * 0.40, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, inset * 0.24)
                    .background(.black.opacity(0.55), in: Capsule())
                    .padding(.leading, inset * 0.3)
                    .padding(.bottom, inset * 0.18)
            }
        }
        .frame(width: width, height: height)
    }

    func png() -> Data? {
        // Keep every viewport pixel when adding Oa's frame.
        let aspect = Self.previewSize.width / Self.previewSize.height
        let width = max(CGFloat(image.width) / (0.98 - 0.2 / aspect), CGFloat(image.height) / (0.8 / aspect - 0.02))
        let renderer = ImageRenderer(
            content: artwork(width: width, settings: PortraitSettings()))
        return renderer.cgImage.flatMap { NSBitmapImageRep(cgImage: $0).representation(using: .png, properties: [:]) }
    }
}

@MainActor
final class PortraitCaptureController: NSObject, NSPopoverDelegate {
    private var popover: NSPopover?
    private var request = UUID()

    private weak var hoverAnchor: NSView?
    private var hoverTask: Task<Void, Never>?
    private var overButton = false
    private var overPreview = false

    func hover(_ inside: Bool, anchor: NSView, page: any Page, model: WindowModel) {
        if inside && hoverAnchor !== anchor {
            cancel()
            hoverAnchor = anchor
        }
        guard hoverAnchor === anchor else { return }
        overButton = inside
        hoverTask?.cancel()
        if inside && popover == nil {
            hoverTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(220))
                guard !Task.isCancelled, anchor.window?.isKeyWindow == true else { return }
                self?.capture(page: page, in: model, quick: false, anchor: anchor)
            }
        } else {
            scheduleDismissal()
        }
    }

    func leave(anchor: NSView) {
        if hoverAnchor === anchor { cancel() }
    }

    func cancel() {
        hoverTask?.cancel()
        hoverAnchor = nil
        overPreview = false
        overButton = false
        request = UUID()
        popover?.close()
    }

    private func scheduleDismissal() {
        hoverTask?.cancel()
        guard hoverAnchor != nil, !overButton, !overPreview else { return }
        hoverTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(200))
            if !Task.isCancelled { self?.cancel() }
        }
    }

    func capture(page: any Page, in model: WindowModel, quick: Bool, anchor: NSView? = nil) {
        if anchor == nil {
            cancel()
            model.regionCapture.cancel()
        }
        let token = UUID()
        request = token
        let url = page.url
        page.snapshot { [weak self, weak page, weak model, weak anchor] snapshot in
            guard let self, request == token, let model, let page, page.url == url, page.view.window != nil,
                anchor?.window != nil || model.frontPage?.id == page.id
            else { return }
            guard let capture = PortraitCapture(snapshot: snapshot, page: page, colors: model.topBarColors) else {
                if anchor == nil {
                    model.present(.capture("Couldn’t capture this page"), at: .windowContent(page.id))
                }
                return
            }
            let copy = { [weak self, weak model, pageID = page.id] in
                self?.cancel()
                model?.copyCapture(capture.png(), for: pageID)
            }
            if quick {
                copy()
                return
            }
            let editor = PortraitCaptureEditor(capture: capture, copy: copy) { [weak self, weak model] in
                self?.cancel()
                if let window = model?.window { capture.save(in: window) }
            }
            .onHover { [weak self] inside in
                self?.overPreview = inside
                self?.scheduleDismissal()
            }
            .onExitCommand { [weak self] in self?.cancel() }
            let controller = NSHostingController(rootView: editor)
            controller.sizingOptions = .preferredContentSize
            let popover = NSPopover()
            self.popover = popover
            popover.contentViewController = controller
            popover.behavior = anchor == nil ? .transient : .applicationDefined
            popover.animates = false
            popover.delegate = self
            if let anchor {
                popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
            } else {
                let view = page.view
                let edge = NSRect(
                    x: view.bounds.midX, y: view.isFlipped ? 0 : view.bounds.maxY - 1, width: 1, height: 1)
                popover.show(relativeTo: edge, of: view, preferredEdge: .minY)
            }
        }
    }

    func popoverDidClose(_ notification: Notification) {
        if notification.object as? NSPopover === popover { popover = nil }
    }
}

private extension PortraitCapture {
    func save(in window: NSWindow) {
        guard let png = png() else {
            window.presentError(CocoaError(.fileWriteUnknown))
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = (host ?? "Portrait Capture") + ".png"
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let file = panel.url else { return }
            do { try png.write(to: file, options: .atomic) } catch { window.presentError(error) }
        }
    }
}

private struct PortraitCaptureEditor: View {
    let capture: PortraitCapture
    let copy: () -> Void
    let save: () -> Void
    private var settings = PortraitSettings()

    var body: some View {
        VStack(spacing: 8) {
            Button(action: copy) {
                Text("Capture in Portrait Mode").font(.system(size: 13, weight: .semibold))
                    .frame(maxWidth: .infinity).frame(height: 32)
                    .background(.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                    .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(.primary.opacity(0.12)) }
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction)
            ZStack(alignment: .bottomLeading) {
                capture.artwork(width: PortraitCapture.previewSize.width, settings: settings, preview: true)
                Button {
                    settings.hidesWatermark.toggle()
                } label: {
                    Text("Oa").font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(.black.opacity(settings.hidesWatermark ? 0.35 : 0.7))
                        .frame(width: 32, height: 32)
                        .background(.black.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
                .help(settings.hidesWatermark ? "Show watermark" : "Hide watermark")
                .accessibilityLabel("Watermark")
                .accessibilityValue(settings.hidesWatermark ? "Off" : "On")
                .padding(4)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .contextMenu { Button("Save PNG…", action: save) }
            HStack(spacing: 12) {
                swatch("Use Website Color", selected: settings.background == .website) {
                    settings.background = .website
                } label: {
                    Color(nsColor: capture.websiteColor)
                }
                GeometryReader { geometry in
                    let travel = max(1, geometry.size.width - 20)
                    ZStack(alignment: .leading) {
                        Capsule().fill(
                            LinearGradient(colors: PortraitSettings.stops, startPoint: .leading, endPoint: .trailing)
                        )
                        .frame(height: 12)
                        Circle().fill(.white).shadow(radius: 1)
                            .frame(width: 20, height: 20)
                            .offset(x: travel * settings.sliderPosition)
                    }
                    .frame(maxHeight: .infinity).contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0).onChanged { value in
                            settings.sliderPosition = (value.location.x - 10) / travel
                        }
                    )
                    .accessibilityRepresentation {
                        Slider(
                            value: Binding(
                                get: { settings.sliderPosition }, set: { settings.sliderPosition = $0 }), in: 0...1
                        ) { Text("Background color") }
                    }
                }
                swatch("Use Desktop Wallpaper", selected: settings.background == .wallpaper && capture.wallpaper != nil)
                {
                    settings.background = .wallpaper
                } label: {
                    if let wallpaper = capture.wallpaper {
                        Image(nsImage: wallpaper).resizable().scaledToFill()
                    } else {
                        Image(systemName: "desktopcomputer")
                    }
                }
                .disabled(capture.wallpaper == nil)
            }
            .padding(.horizontal, 4)
            .frame(height: 24)
        }
        .padding(10).frame(width: 260)
    }

    private func swatch(
        _ title: String, selected: Bool, action: @escaping () -> Void, @ViewBuilder label: () -> some View
    ) -> some View {
        Button(action: action) {
            label().frame(width: 16, height: 16).clipShape(Circle())
                .overlay { if selected { Circle().strokeBorder(.white, lineWidth: 2) } }
        }
        .buttonStyle(.plain).accessibilityLabel(title).help(title)
    }
}

struct PortraitCaptureButton: View {
    let model: WindowModel
    let page: any Page
    let tabID: UUID
    @State private var anchor = NSView()
    @State private var hovered = false

    var body: some View {
        Button {
            model.select(tabID)
            model.portraitCapture.capture(page: page, in: model, quick: true)
        } label: {
            Image(systemName: "camera.macro")
                .font(.system(size: 10))
                .frame(width: 16, height: 12)
                .overlay { RoundedRectangle(cornerRadius: 2).strokeBorder(lineWidth: 1) }
                .frame(width: 28, height: 28)
                .background(.foreground.opacity(hovered ? 0.12 : 0), in: RoundedRectangle(cornerRadius: 5))
                .contentShape(Rectangle())
        }
        .background { Anchor(view: anchor).allowsHitTesting(false) }
        .accessibilityLabel("Capture in Portrait Mode")
        .accessibilityAction(named: "Capture options") {
            model.select(tabID)
            model.portraitCapture.capture(page: page, in: model, quick: false)
        }
        .onHover { inside in
            hovered = inside
            model.portraitCapture.hover(inside, anchor: anchor, page: page, model: model)
        }
        .onChange(of: page.url) { model.portraitCapture.leave(anchor: anchor) }
        .onDisappear { model.portraitCapture.leave(anchor: anchor) }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willResignActiveNotification)) { _ in
            model.portraitCapture.leave(anchor: anchor)
        }
    }

    private struct Anchor: NSViewRepresentable {
        let view: NSView
        func makeNSView(context: Context) -> NSView { view }
        func updateNSView(_ view: NSView, context: Context) {}
    }
}
