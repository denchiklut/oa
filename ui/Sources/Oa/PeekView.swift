import DevKit
import SwiftUI

/// Arc's Peek as measured: the page is 80% of the content area's width by the height minus 56, under a 33 pt
/// toolbar, centered 11 pt from the top, over a fifth of dim; the sidebar stays live under it.
struct PeekView: View {
    let model: WindowModel
    let page: any Page
    let sidebarWidth: CGFloat

    var body: some View {
        GeometryReader { geometry in
            let contentWidth = geometry.size.width - sidebarWidth
            let margin = contentWidth * 0.1
            let panelWidth = contentWidth - 2 * margin
            ZStack(alignment: .topLeading) {
                HStack(spacing: 0) {
                    Backdrop(onClick: nil).frame(width: sidebarWidth)
                    Backdrop(onClick: model.closePeek)
                }
                panel
                    .frame(width: panelWidth, height: max(geometry.size.height - 23, 100))
                    .padding(.leading, sidebarWidth + margin)
                    .padding(.top, 11)
                controls
                    .padding(.leading, sidebarWidth + margin + panelWidth + min(30, margin / 2) - 14)
                    .padding(.top, 22)
            }
        }
        .onAppear { page.activate() }
        .onChange(of: page.id) { _, _ in page.activate() }
    }

    private var panel: some View {
        VStack(spacing: 0) {
            toolbar.frame(height: 33)
            Divider()
            PageContentView(page: page)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .top) {
            if page.isLoading {
                ProgressView(value: page.loadProgress).progressViewStyle(.linear).frame(height: 2)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
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

    private var controls: some View {
        VStack(spacing: 16) {
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
        .buttonStyle(.plain)
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(.white)
        .frame(width: 28)
    }
}

/// An NSView, so it dims the engine's view too, which draws above SwiftUI's own layers.
private struct Backdrop: NSViewRepresentable {
    let onClick: (() -> Void)?

    func makeNSView(context: Context) -> DimView {
        let view = DimView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.2).cgColor
        return view
    }

    func updateNSView(_ view: DimView, context: Context) {
        view.onClick = onClick
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
