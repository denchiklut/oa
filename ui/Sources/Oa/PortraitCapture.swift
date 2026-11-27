import AppKit
import DevKit
import SwiftUI
import UniformTypeIdentifiers

private enum PortraitBackground: String {
    case website, wallpaper, custom
}

private struct PortraitSettings: DynamicProperty {
    @AppStorage("portraitCaptureBackground") var background = PortraitBackground.website
    @AppStorage("portraitCaptureColorPercentage") var hue = 0.60
    @AppStorage("portraitCaptureHidesWatermark") var hidesWatermark = false
}

@MainActor
struct PortraitCapture {
    private static let insetFraction: CGFloat = 0.055
    private var contentFraction: CGFloat { 1 - 2 * Self.insetFraction }
    fileprivate var aspect: CGFloat {
        CGFloat(image.height) / CGFloat(image.width) * contentFraction + 2 * Self.insetFraction
    }

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

    fileprivate func artwork(width: CGFloat, settings: PortraitSettings) -> some View {
        let inset = width * Self.insetFraction
        let height = width * aspect
        return ZStack(alignment: .bottomTrailing) {
            Color(nsColor: websiteColor)
            if settings.background == .wallpaper, let wallpaper {
                Image(nsImage: wallpaper).resizable().scaledToFill().frame(width: width, height: height).clipped()
            } else if settings.background == .custom {
                Color(hue: settings.hue, saturation: 0.48, brightness: 0.89)
            }
            Image(decorative: image, scale: 1)
                .resizable()
                .clipShape(RoundedRectangle(cornerRadius: width * 0.009))
                .shadow(color: .black.opacity(0.28), radius: width * 0.01, y: width * 0.004)
                .padding(inset)
            if !settings.hidesWatermark {
                Text("Oa")
                    .font(.system(size: inset * 0.40, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, inset * 0.24)
                    .background(.black.opacity(0.55), in: Capsule())
                    .padding(.trailing, inset)
                    .padding(.bottom, inset * 0.18)
            }
        }
        .frame(width: width, height: height)
    }

    func png() -> Data? {
        // Keep every viewport pixel when adding Oa's frame.
        let renderer = ImageRenderer(
            content: artwork(width: CGFloat(image.width) / contentFraction, settings: PortraitSettings()))
        return renderer.cgImage.flatMap { NSBitmapImageRep(cgImage: $0).representation(using: .png, properties: [:]) }
    }
}

@MainActor
final class PortraitCaptureController: NSObject, NSPopoverDelegate {
    private var popover: NSPopover?
    private var request = UUID()

    func capture(page: any Page, in model: WindowModel, quick: Bool, anchorX: CGFloat? = nil) {
        popover?.close()
        let token = UUID()
        request = token
        let url = page.url
        page.snapshot { [weak self, weak page, weak model] snapshot in
            guard let self, request == token, let model, let page, model.frontPage?.id == page.id,
                page.url == url, page.view.window != nil
            else { return }
            guard let capture = PortraitCapture(snapshot: snapshot, page: page, colors: model.topBarColors) else {
                model.present(.portraitCapture("Couldn’t capture this page"), at: .windowContent(page.id))
                return
            }
            let copy = { [weak self, weak model, pageID = page.id] in
                self?.popover?.close()
                guard let model else { return }
                let copied = capture.copyImage()
                model.present(
                    .portraitCapture(copied ? "Capture copied" : "Couldn’t copy capture"), at: .windowContent(pageID))
            }
            if quick {
                copy()
                return
            }
            let editor = PortraitCaptureEditor(capture: capture, copy: copy) { [weak self, weak model] in
                self?.popover?.close()
                if let window = model?.window { capture.save(in: window) }
            }
            let controller = NSHostingController(rootView: editor)
            controller.sizingOptions = .preferredContentSize
            let popover = NSPopover()
            self.popover = popover
            popover.contentViewController = controller
            popover.behavior = .transient
            popover.delegate = self
            let view = page.view
            let x = anchorX.map { view.convert(NSPoint(x: $0, y: 0), from: nil).x } ?? view.bounds.midX
            let anchor = NSRect(
                x: min(max(0, x), view.bounds.maxX - 1), y: view.isFlipped ? view.bounds.minY : view.bounds.maxY - 1,
                width: 1, height: 1)
            popover.show(relativeTo: anchor, of: view, preferredEdge: view.isFlipped ? .maxY : .minY)
        }
    }

    func popoverDidClose(_ notification: Notification) {
        if notification.object as? NSPopover === popover { popover = nil }
    }
}

private extension PortraitCapture {
    func copyImage() -> Bool {
        guard let png = png() else { return false }
        NSPasteboard.general.clearContents()
        return NSPasteboard.general.setData(png, forType: .png)
    }

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
        VStack(alignment: .leading, spacing: 12) {
            capture.artwork(width: min(288, 190 / capture.aspect), settings: settings)
                .frame(maxWidth: .infinity)
                .accessibilityLabel("Capture preview")
            Picker(
                "Background",
                selection: Binding(
                    get: {
                        settings.background == .wallpaper && capture.wallpaper == nil ? .website : settings.background
                    }, set: { settings.background = $0 })
            ) {
                Text("Website Color").tag(PortraitBackground.website)
                if capture.wallpaper != nil {
                    Text("Desktop Wallpaper").tag(PortraitBackground.wallpaper)
                }
                Text("Custom Color").tag(PortraitBackground.custom)
            }
            if settings.background == .custom {
                Slider(value: settings.$hue, in: 0...1) { Text("Hue") }
            }
            Toggle(
                "Show Oa watermark",
                isOn: Binding(get: { !settings.hidesWatermark }, set: { settings.hidesWatermark = !$0 }))
            HStack {
                Spacer()
                Button("Save PNG…", action: save)
                Button("Copy Image", action: copy).keyboardShortcut(.defaultAction)
            }
        }
        .padding(14)
        .frame(width: 316)
    }
}
