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
        // As measured in Arc: hidden, the sidebar is past the window's edge by its width and 10 pt more, and the card
        // is 10 pt in from every edge, a floating sidebar over it. The Library comes in from the left on the pager's
        // progress, the card starts where it ends, keeping its width, and what the progress does to the sidebar is
        // `SidebarHomeTransition`.
        let presentation = layout.sidebarPresentation
        let floats = layout.sidebarIsPanel
        let progress = layout.libraryProgress
        let section = model.library ?? model.lastLibrarySection
        let libraryWidth = layout.libraryWidth(for: section)
        let lead = presentation == .locked ? layout.sidebarWidth : 10
        let sidebarOffset =
            presentation == .hidden
            ? -(layout.sidebarWidth + 10) : floats ? -(layout.sidebarWidth + 10) * min(progress, 1) : 0
        ZStack(alignment: .topLeading) {
            WindowDragRegion()
            FloatingSidebarBackgroundView(background: background, windowSize: layout.size, isFloating: floats) {
                SidebarView(model: model, layout: layout)
                    .environment(\.colorScheme, appearance.colorScheme)
            }
            .modifier(SidebarHomeTransition(progress: floats ? 0 : min(progress, 1)))
            .offset(x: sidebarOffset)
            .allowsHitTesting(progress == 0)
            .zIndex(floats ? 3 : 0)
            if progress > 0 {
                LibraryView(
                    model: model, section: section, width: libraryWidth, progress: progress, pageInset: lead
                )
                .environment(\.colorScheme, appearance.colorScheme)
                .offset(x: -libraryWidth * (1 - progress))
                .allowsHitTesting(model.library != nil)
                .zIndex(1)
            }
            card
                .padding([.top, .trailing, .bottom], 10)
                .padding(.leading, lead)
                .offset(x: (libraryWidth - lead) * progress)
                .zIndex(2)
            // Mounted with the sidebar hidden too: a drag that hides the sidebar ends on it.
            if progress == 0 {
                SidebarResizeRegion(layout: layout)
                    .frame(width: 8)
                    .padding(.vertical, 11)
                    .offset(
                        x: sidebarOffset + layout.sidebarWidth + (floats ? WindowLayoutController.floatingInset : 0) - 4
                    )
                    .zIndex(4)
            }
        }
        .background { WindowSurface(background: background) }
        .overlay {
            // The Archive's Peek is over the whole window. A tab's is over its page and leaves the docked sidebar
            // clear; beside the Library it goes where the card goes, Oa's own: Arc's wasn't looked at there.
            if let peek = model.peek {
                let overPage = !model.showingArchive
                PeekView(
                    model: model, page: peek,
                    sidebarWidth: overPage && presentation == .locked ? layout.sidebarWidth : 0
                )
                .offset(x: overPage ? (libraryWidth - lead) * progress : 0)
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
}

/// Arc's docked sidebar while the Library comes over it: it stays where it is, shrinking by a tenth toward a point
/// 26 pt to its right, and fades. Gone 8% of the way in, as measured; Arc's code reads halfway.
private struct SidebarHomeTransition: ViewModifier {
    let progress: CGFloat

    func body(content: Content) -> some View {
        let scale = 1 - 0.1 * progress
        content
            .scaleEffect(scale)
            .offset(x: 26 * progress * scale)
            .opacity(max(0, 1 - progress / 0.08))
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
