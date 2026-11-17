import DevKit
import SwiftUI

/// Arc's Peek as measured: the page is 80% of the content area's width by the height minus 56, under a 33 pt
/// toolbar, centered 11 pt from the top; the sidebar stays live under it.
struct PeekView: View {
    let model: WindowModel
    let page: any Page
    let sidebarWidth: CGFloat
    /// As Arc: over a page the opener's card fades instead and nothing is dimmed. The Archive's Peek keeps a fifth of
    /// dim, Oa's own: Arc's wasn't measured.
    let overPage: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { geometry in
            let contentWidth = geometry.size.width - sidebarWidth
            let margin = contentWidth * 0.1
            let panelWidth = contentWidth - 2 * margin
            ZStack(alignment: .topLeading) {
                let dim = overPage ? .clear : NSColor.black.withAlphaComponent(0.2)
                HStack(spacing: 0) {
                    Backdrop(onClick: nil, color: dim).frame(width: sidebarWidth)
                    Backdrop(onClick: model.closePeek, color: dim)
                }
                panel
                    .frame(width: panelWidth, height: max(geometry.size.height - 23, 100))
                    .padding(.leading, sidebarWidth + margin)
                    .padding(.top, 11)
                controls
                    .padding(.leading, sidebarWidth + margin + panelWidth + min(30, margin / 2) - 17)
                    .padding(.top, 19)
            }
        }
        .onAppear { page.activate() }
        .onChange(of: page.id) { _, _ in page.activate() }
    }

    private var panel: some View {
        // As Arc's: the page's card, opaque white or black, with 8 pt corners and no divider under the toolbar.
        VStack(spacing: 0) {
            toolbar.frame(height: 33)
            PageContentView(page: page)
        }
        .background(colorScheme == .dark ? Color.black : .white)
        .overlay(alignment: .top) {
            if page.isLoading {
                ProgressView(value: page.loadProgress).progressViewStyle(.linear).frame(height: 2)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.35), radius: 24, y: 8)
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Button {
                page.goBack()
            } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(!page.canGoBack)
            Button {
                page.goForward()
            } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(!page.canGoForward)
            Button {
                if page.isLoading { page.stopLoading() } else { page.reload() }
            } label: {
                Image(systemName: page.isLoading ? "xmark" : "arrow.clockwise")
            }
            Spacer()
            address
                .popover(isPresented: model.permissionPromptBinding(forPeek: true), arrowEdge: .bottom) {
                    if let request = model.promptedPermissionRequest {
                        PermissionRequestView(model: model, request: request)
                    }
                }
            Spacer()
            Color.clear.frame(width: 78)
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 10)
    }

    private var address: Text {
        guard let url = page.url else { return Text("") }
        let host = url.host() ?? ""
        var rest = url.absoluteString
        if let scheme = url.scheme { rest = String(rest.dropFirst(scheme.count + 3)) }
        if rest.hasPrefix(host) { rest = String(rest.dropFirst(host.count)) }
        if rest == "/" { rest = "" }
        return Text(host).fontWeight(.semibold) + Text(rest).foregroundStyle(.secondary)
    }

    /// As measured in Arc: 34 pt discs, 43.5 pt apart, white with a blue glyph in light. The dark ones are Oa's own.
    private var controls: some View {
        VStack(spacing: 9.5) {
            Button {
                model.closePeek()
            } label: {
                Image(systemName: "xmark")
            }
            .help("Close Peek")
            Button {
                model.expandPeek()
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
            }
            .help("Expand Peek")
        }
        .buttonStyle(PeekControlStyle(dark: colorScheme == .dark))
    }
}

private struct PeekControlStyle: ButtonStyle {
    let dark: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(dark ? Color.white : Color(.displayP3, red: 0.192, green: 0.224, blue: 0.984))
            .frame(width: 34, height: 34)
            .background(
                Circle().fill(dark ? Color(white: 0.17) : .white).shadow(color: .black.opacity(0.15), radius: 4, y: 1)
            )
            .contentShape(Circle())
    }
}

/// An NSView, so it dims the engine's view too, which draws above SwiftUI's own layers.
struct Backdrop: NSViewRepresentable {
    let onClick: (() -> Void)?
    var color = NSColor.black.withAlphaComponent(0.2)

    func makeNSView(context: Context) -> DimView {
        let view = DimView()
        view.wantsLayer = true
        return view
    }

    func updateNSView(_ view: DimView, context: Context) {
        view.onClick = onClick
        view.layer?.backgroundColor = color.cgColor
    }

    final class DimView: NSView {
        var onClick: (() -> Void)?

        override func hitTest(_ point: NSPoint) -> NSView? {
            onClick == nil ? nil : super.hitTest(point)
        }

        override func mouseDown(with event: NSEvent) {
            onClick?()
        }
    }
}
