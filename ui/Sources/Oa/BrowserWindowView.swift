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
        let locked = presentation == .locked
        let progress = layout.libraryProgress
        let section = model.library ?? model.lastLibrarySection
        let libraryWidth = layout.libraryWidth(for: section)
        let lead = locked ? layout.sidebarWidth : 10
        let hiddenOffset = -(layout.sidebarWidth + 10)
        ZStack(alignment: .topLeading) {
            WindowDragRegion()
            SidebarDocking(locked: locked) { floats in
                FloatingSidebarBackgroundView(
                    background: background, next: next, windowSize: layout.size, isFloating: !locked, isPanel: floats
                ) {
                    SidebarView(model: model, layout: layout)
                        .environment(\.sidebarToolTips, true)
                        .environment(\.colorScheme, appearance.colorScheme)
                }
                .modifier(SidebarHomeTransition(progress: floats ? 0 : min(progress, 1)))
                .offset(x: presentation == .hidden ? hiddenOffset : floats ? hiddenOffset * min(progress, 1) : 0)
                .allowsHitTesting(progress == 0)
                .zIndex(floats ? 3 : 0)
            }
            if progress > 0 {
                LibraryView(
                    model: model, layout: layout, section: section, width: libraryWidth, progress: progress,
                    pageInset: lead
                )
                .environment(\.sidebarToolTips, true)
                .environment(\.colorScheme, appearance.colorScheme)
                .offset(x: -libraryWidth * (1 - progress))
                .allowsHitTesting(model.library != nil)
                .zIndex(1)
            }
            // As Arc's `DimState`: under a Peek the card shrinks 9 pt at every edge as it fades.
            let cardSize = CGSize(width: layout.size.width - lead - 10, height: layout.size.height - 20)
            content
                .sidebarDragFrame { sidebarDrag.pageArea = $0 }
                .scaleEffect(
                    x: fadesCard ? 1 - 18 / max(cardSize.width, 18) : 1,
                    y: fadesCard ? 1 - 18 / max(cardSize.height, 18) : 1
                )
                // A newly selected tab starts at its own Peek scale.
                .animation(nil, value: model.selectedTabID)
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
                        x: (presentation == .hidden ? hiddenOffset : 0) + layout.sidebarWidth
                            + (locked ? 0 : WindowLayoutController.floatingInset) - 4
                    )
                    .zIndex(4)
            }
        }
        .onDrop(of: [.url], delegate: SidebarLinkDrop(model: model, drag: sidebarDrag))
        .coordinateSpace(.named(SidebarDrag.space))
        .overlay(alignment: .topLeading) {
            SidebarDragLayer(model: model, drag: sidebarDrag)
                .environment(\.colorScheme, appearance.colorScheme)
        }
        .overlay(alignment: .topLeading) {
            if let preview = layout.folderPreview, let folder = model.state.tree.folder(preview.id) {
                FolderPreviewView(model: model, layout: layout, folder: folder, anchor: preview.anchor)
                    .id(folder.id)
            }
        }
        .background { WindowSurface(background: background, next: next) }
        .overlay {
            // The Archive's Peek is over the whole window. A tab's is over its page and leaves the docked sidebar
            // clear; beside the Library it goes where the card goes, Oa's own: Arc's wasn't looked at there.
            if let peek = model.peek {
                let overPage = !model.showingArchive
                PeekView(
                    model: model, page: peek, swipe: layout.peekSwipe,
                    sidebarWidth: overPage && locked ? layout.sidebarWidth : 0
                )
                .offset(x: overPage ? (libraryWidth - lead) * progress : 0)
            }
        }
        .windowToast(of: model)
        .overlay {
            if let bar = model.commandBar {
                CommandBarView(model: model, bar: bar, themeFocus: theme.semanticColorPalette[colorScheme].focus.color)
                    .id(ObjectIdentifier(bar))
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
        .onChange(of: model.selectedTabID) { layout.dismissFolderPreview() }
        .onChange(of: model.page?.id) { _, _ in
            DispatchQueue.main.async {
                guard let page = model.page, model.dialog == nil, model.extensionRequest == nil,
                    model.commandBar == nil, layout.folderPreview == nil
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
        .environment(\.oaToolTipPalette, .space(theme.semanticColorPalette[colorScheme]))
        .ignoresSafeArea()
        .animation(WindowLayoutController.lockAnimation, value: locked)
    }

    /// As measured in Arc: under a Peek over the page, the opener's card shows at 30% over the window's theme.
    private var fadesCard: Bool { model.peek != nil && !model.showingArchive }

    /// As Arc: a split's panes take the page's place.
    @ViewBuilder private var content: some View {
        if model.splitViewPanes.count > 1 {
            SplitViewContentPanes(model: model)
        } else {
            card
        }
    }

    /// Arc's page as measured: a card flush with the sidebar and 10 pt in from the window's other edges, with 6 pt
    /// corners, no border and a soft shadow.
    private var card: some View {
        // As Arc: under a page the card is opaque white or black by the window's appearance, and with none it is
        // `emptyWindowContentBackgroundColor`, white at 0.666 or 0.1 over the Space's theme.
        let dark = colorScheme == .dark
        let fill =
            model.placeholder == nil && model.page == nil
            ? Color.white.opacity(dark ? 0.1 : 0.666) : dark ? Color.black : .white
        let developer = model.placeholder == nil && model.developerMode.isEnabled(for: model.page?.url)
        let regularToolbar = showsToolbar && !developer
        return VStack(spacing: 0) {
            if developer, let page = model.page, let tabID = model.selectedTabID {
                DeveloperToolbar(
                    model: model, tabID: tabID, page: page,
                    showSidebar: model.sidebarMode == .noChrome ? { layout.setSidebarMode(.anchored) } : nil
                ) { SplitViewMenuButton(model: model) }
                .id(page.id)
            } else if showsToolbar {
                // A toolbar for each page, so a tab switch shows the page's colour at once, as Arc's toolbar sets its
                // colour without animation when its page changes.
                PageToolbar(model: model, layout: layout)
                    .id(model.page?.id)
                    .transition(.identity)
                    .opacity(model.placeholder == nil ? 1 : 0)
            }
            Group {
                if let placeholder = model.placeholder {
                    PlaceholderView(image: placeholder)
                } else if let page = model.page {
                    PageContentView(model: model, page: page).pageRootBackground(page)
                } else {
                    Color.clear
                }
            }
            // Arc's page starts 32 pt down under its toolbar; Oa's line under the bar is left in the strip, so the
            // strip takes as much of the page as Arc's.
            .windowContentGrabber(
                model: model, hasContent: model.placeholder != nil || model.page != nil, enabled: !developer,
                barHeight: showsToolbar ? 32 : 0
            )
        }
        .findInPage(of: model, on: model.placeholder == nil ? model.page : nil, hasTopBar: developer || showsToolbar)
        .toast(of: model, on: model.page)
        .onChange(of: regularToolbar ? model.page?.id : nil, initial: true) { _, _ in
            model.trackToolbarPage(regularToolbar)
        }
        .onDisappear { model.trackToolbarPage(false) }
        // Faded, the fill would show through the page that covers it.
        .background(fadesCard ? .clear : fill)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        // As seen in Arc: a tab dragged over the page's middle outlines the page it would be shown in place of.
        .overlay {
            if model.proposedSplitViewDropTarget?.target == .replaceContent(0) {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(model.splitViewFocusColor(dark: colorScheme == .dark), lineWidth: 3)
            }
        }
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

/// Whether the sidebar is drawn as the floating panel, over the page: from the start of undocking to the end of
/// docking, as open-arch's `isPanel`. Read off the lock animation's own progress, so the panel stays over the page,
/// which is see-through when empty, until the page has slid out from under it, and a lock no animation ran for
/// still ends docked.
private struct SidebarDocking<Content: View>: View, Animatable {
    private let locked: Bool
    private let content: (_ isPanel: Bool) -> Content
    var animatableData: CGFloat

    init(locked: Bool, @ViewBuilder content: @escaping (_ isPanel: Bool) -> Content) {
        self.locked = locked
        self.content = content
        animatableData = locked ? 1 : 0
    }

    var body: some View { content(!locked || animatableData < 1) }
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

struct PlaceholderView: View {
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
    /// The host is in a window: only then can the engine give its page the keyboard.
    var movedToWindow: () -> Void = {}

    func makeNSView(context: Context) -> Container { Container() }

    /// A host updated with the view it already placed leaves it alone: another host may have taken it since, as
    /// the window's does on Expand, and SwiftUI still updates the Peek's host on its way out.
    func updateNSView(_ container: Container, context: Context) {
        container.movedToWindow = movedToWindow
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
        var movedToWindow: () -> Void = {}

        override var isFlipped: Bool { true }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window != nil { movedToWindow() }
        }

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
