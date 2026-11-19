import DevKit
import SwiftUI

struct BrowserWindowView: View {
    let model: WindowModel
    let layout: WindowLayoutController
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(PageToolbar.key) private var showsToolbar = false
    @State private var sidebarDrag = SidebarDrag()

    var body: some View {
        let backdrop = layout.backgroundThemes
        // As Arc: chrome follows the committed Space while the background follows the pager.
        let theme = layout.chromeTheme
        let background = backdrop.base.background[colorScheme]
        let next = backdrop.blend.map { (background: $0.theme.background[colorScheme], progress: Double($0.progress)) }
        let appearance = theme.background[colorScheme].contentOverBackgroundAppearance
        // As measured in Arc: hidden, the sidebar is past the window's edge by its width and 10 pt more, and the card
        // is 10 pt in from every edge, a floating sidebar over it. The Library comes in from the left on the pager's
        // progress, the card starts where it ends, keeping its width, and what the progress does to the sidebar is
        // `SidebarHomeTransition`.
        let presentation = layout.sidebarPresentation
        let floats = layout.sidebarIsPanel
        let floatingShape = floats && presentation != .locked
        let progress = layout.libraryProgress
        let section = model.library ?? model.lastLibrarySection
        let libraryWidth = layout.libraryWidth(for: section)
        let lead = presentation == .locked ? layout.sidebarWidth : 10
        let sidebarOffset =
            presentation == .hidden
            ? -(layout.sidebarWidth + 10) : floats ? -(layout.sidebarWidth + 10) * min(progress, 1) : 0
        ZStack(alignment: .topLeading) {
            WindowDragRegion()
            FloatingSidebarBackgroundView(
                background: background, next: next, windowSize: layout.size, isFloating: floatingShape,
                isPanel: floats
            ) {
                SidebarView(model: model, layout: layout)
                    .environment(\.colorScheme, appearance.colorScheme)
            }
            .modifier(SidebarHomeTransition(progress: floats ? 0 : min(progress, 1)))
            .offset(x: sidebarOffset)
            .allowsHitTesting(progress == 0)
            .zIndex(floats ? 3 : 0)
            if progress > 0 {
                let libraryAppearance = layout.libraryTheme.background[colorScheme].contentOverBackgroundAppearance
                LibraryView(
                    model: model, layout: layout, section: section, width: libraryWidth, progress: progress,
                    pageInset: lead
                )
                .environment(\.colorScheme, libraryAppearance.colorScheme)
                .environment(
                    \.theme,
                    Theme(
                        palette: layout.libraryTheme.semanticColorPalette[libraryAppearance.colorScheme],
                        appearance: libraryAppearance)
                )
                .offset(x: -libraryWidth * (1 - progress))
                .allowsHitTesting(model.library != nil)
                .zIndex(1)
            }
            // As Arc's `DimState`: under a Peek the card shrinks 9 pt at every edge as it fades.
            let cardSize = CGSize(width: layout.size.width - lead - 10, height: layout.size.height - 20)
            card
                .scaleEffect(
                    x: fadesCard ? 1 - 18 / max(cardSize.width, 18) : 1,
                    y: fadesCard ? 1 - 18 / max(cardSize.height, 18) : 1
                )
                .animation(.easeInOut(duration: 0.12), value: fadesCard)
                .opacity(fadesCard ? 0.3 : 1)
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
                        x: sidebarOffset + layout.sidebarWidth
                            + (floatingShape ? WindowLayoutController.floatingInset : 0) - 4
                    )
                    .zIndex(4)
            }
        }
        .coordinateSpace(.named(SidebarDrag.space))
        .overlay(alignment: .topLeading) {
            SidebarDragLayer(model: model, drag: sidebarDrag)
                .environment(\.colorScheme, appearance.colorScheme)
        }
        .background { WindowSurface(background: background, next: next) }
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
        .environment(\.windowColorScheme, colorScheme)
        .environment(\.sidebarDrag, sidebarDrag)
        .ignoresSafeArea()
    }

    /// As measured in Arc: under a Peek over the page, the opener's card shows at 30% over the window's theme.
    private var fadesCard: Bool { model.peek != nil && !model.showingArchive }

    /// Arc's page as measured: a card flush with the sidebar and 10 pt in from the window's other edges, with 6 pt
    /// corners, no border and a soft shadow.
    private var card: some View {
        // As Arc: under a page the card is opaque white or black by the window's appearance, and with none it is
        // `emptyWindowContentBackgroundColor`, white at 0.666 or 0.1 over the Space's theme.
        let dark = colorScheme == .dark
        // The Create a Space panel's empty card is a light window's, blended in with its theme.
        let light = layout.spaceCreationThemeWeight
        let fill =
            model.placeholder == nil && model.page == nil
            ? Color.white.opacity(dark ? 0.1 + (0.666 - 0.1) * light : 0.666) : dark ? Color.black : .white
        return VStack(spacing: 0) {
            if showsToolbar {
                PageToolbar(model: model)
                    .environment(\.theme, .toolbar)
                    .opacity(model.placeholder == nil ? 1 : 0)
            }
            if let placeholder = model.placeholder {
                PlaceholderView(image: placeholder)
            } else if let page = model.page {
                PageContentView(page: page).pageRootBackground(page)
            } else {
                Color.clear
            }
        }
        // Faded, the fill would show through the page that covers it.
        .background(fadesCard ? .clear : fill)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        // What casts the shadow sits a point inside the card, so it never tints the card's edge, and is cut out
        // under it, as Arc's shadow is as strong under the see-through empty card as under a page.
        .background {
            RoundedRectangle(cornerRadius: 5)
                .padding(1)
                .shadow(color: .black.opacity(0.3), radius: 4, y: 1)
                .mask {
                    Rectangle()
                        .padding(-20)
                        .overlay { RoundedRectangle(cornerRadius: 6).blendMode(.destinationOut) }
                        .compositingGroup()
                }
        }
        // Oa's own place, in the margin over the card: Arc's with the sidebar showing wasn't measured.
        .overlay(alignment: .top) {
            LoadingIndicator(isLoading: model.page?.isLoading == true).offset(y: -7)
        }
    }
}

/// Arc's docked sidebar while the Library comes over it: it stays where it is, shrinking by a tenth toward a point
/// 26 pt to its right, and fades, gone halfway in.
private struct SidebarHomeTransition: ViewModifier {
    let progress: CGFloat

    func body(content: Content) -> some View {
        let scale = 1 - 0.1 * progress
        content
            .scaleEffect(scale)
            .offset(x: 26 * progress * scale)
            .opacity(max(0, 1 - 2 * progress))
    }
}

private struct PlaceholderView: View {
    /// Measured in Arc: a placeholder keeps about 57% of its page's contrast.
    static let snapshotOpacity = 0.57

    let image: NSImage

    var body: some View {
        Color.clear
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
        container.addSubview(view)
        container.fit()
    }

    final class Container: NSView {
        weak var hosted: NSView?

        override var isFlipped: Bool { true }

        override func resizeSubviews(withOldSize oldSize: NSSize) { fit() }

        /// SwiftUI sizes a new container after its first update, and Chromium drops the saved frame of a page
        /// resized while hidden, showing its background until it draws again. So the page keeps its size until
        /// the container has one.
        func fit() {
            guard !bounds.isEmpty else { return }
            subviews.forEach { $0.frame = bounds }
        }
    }
}
