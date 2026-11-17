import DevKit
import SwiftUI

struct BrowserWindowView: View {
    let model: WindowModel
    let layout: WindowLayoutController
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(PageToolbar.key) private var showsToolbar = false

    var body: some View {
        // As Arc: a theme with a light and a dark side shows the one the window's appearance asks for, and the
        // chrome over it takes that side's own appearance.
        let theme = WindowTheme.default
        let background = theme.background[colorScheme]
        let appearance = background.contentOverBackgroundAppearance
        // As measured in Arc: hidden, the sidebar's column is past the window's edge by its width and 10 pt more,
        // and the card is 10 pt in from every edge.
        let hidden = model.sidebarMode == .noChrome && model.library == nil
        ZStack(alignment: .topLeading) {
            WindowDragRegion()
            SidebarView(model: model, layout: layout)
                .environment(\.colorScheme, appearance.colorScheme)
                .offset(x: hidden ? -(SidebarView.width + 10) : 0)
            card
                .padding([.top, .trailing, .bottom], 10)
                .padding(.leading, hidden ? 10 : model.library != nil ? LibraryView.width : SidebarView.width)
        }
        .background { WindowSurface(background: background) }
        .overlay {
            if let peek = model.peek {
                PeekView(model: model, page: peek, sidebarWidth: sidebarWidth)
            }
        }
        .overlay {
            if let bar = model.commandBar {
                CommandBarView(model: model, bar: bar).id(ObjectIdentifier(bar))
            }
        }
        // As Arc: over the command bar, which ⌘T opens behind a dialog.
        .overlay {
            if let dialog = model.dialog {
                DialogView(model: model, dialog: dialog).id(ObjectIdentifier(dialog))
            }
        }
        .overlay {
            if let request = model.extensionRequest {
                ExtensionRequestView(model: model, request: request).id(ObjectIdentifier(request))
            }
        }
        .onChange(of: model.page?.id) { _, _ in
            DispatchQueue.main.async {
                guard let page = model.page, model.dialog == nil, model.extensionRequest == nil,
                    model.commandBar == nil
                else { return }
                (model.peek ?? page).activate()
            }
        }
        .onChange(of: model.dialog == nil && model.extensionRequest == nil) { _, none in
            if none, model.commandBar == nil { model.frontPage?.activate() }
        }
        .environment(
            \.theme, Theme(palette: theme.semanticColorPalette[appearance.colorScheme], appearance: appearance)
        )
        .ignoresSafeArea()
    }

    /// Arc's page as measured: a card flush with the sidebar and 10 pt in from the window's other edges, with 6 pt
    /// corners, no border and a soft shadow.
    private var card: some View {
        VStack(spacing: 0) {
            if showsToolbar {
                PageToolbar(model: model)
                    .environment(\.theme, .toolbar)
                    .opacity(model.placeholder == nil ? 1 : 0)
            }
            if let placeholder = model.placeholder {
                PlaceholderView(image: placeholder)
            } else if let page = model.page {
                PageContentView(page: page)
            } else {
                Color(nsColor: .windowBackgroundColor)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        // What casts the shadow sits a point inside the card, so it never tints the card's edge.
        .background {
            RoundedRectangle(cornerRadius: 5)
                .fill(Color(nsColor: .windowBackgroundColor))
                .padding(1)
                .shadow(color: .black.opacity(0.3), radius: 4, y: 1)
        }
        // Oa's own place, in the margin over the card: Arc's with the sidebar showing wasn't measured.
        .overlay(alignment: .top) {
            LoadingIndicator(isLoading: model.page?.isLoading == true).offset(y: -7)
        }
    }

    private var sidebarWidth: CGFloat {
        if model.showingArchive { return 0 }
        if model.library != nil { return LibraryView.width }
        return model.sidebarMode == .anchored ? SidebarView.width : 0
    }
}

private struct PlaceholderView: View {
    /// Measured in Arc: a placeholder keeps about 57% of its page's contrast.
    static let snapshotOpacity = 0.57

    let image: NSImage

    var body: some View {
        Color(nsColor: .windowBackgroundColor)
            .overlay(alignment: .top) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .opacity(Self.snapshotOpacity)
            }
            .clipped()
    }
}

struct PageHostView: NSViewRepresentable {
    let view: NSView

    func makeNSView(context: Context) -> Container { Container() }

    /// A host updated with the view it already placed leaves it alone: another host may have taken it since, as
    /// the window's does on Expand, and SwiftUI still updates the Peek's host on its way out.
    func updateNSView(_ container: Container, context: Context) {
        guard container.hosted !== view else { return }
        container.hosted = view
        container.subviews.forEach { $0.removeFromSuperview() }
        view.removeFromSuperview()
        view.translatesAutoresizingMaskIntoConstraints = true
        view.frame = container.bounds
        view.autoresizingMask = [.width, .height]
        container.addSubview(view)
    }

    final class Container: NSView {
        weak var hosted: NSView?

        override var isFlipped: Bool { true }

        override func layout() {
            super.layout()
            subviews.forEach { $0.frame = bounds }
        }
    }
}
