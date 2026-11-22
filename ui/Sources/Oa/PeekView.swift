import DevKit
import SwiftUI

/// Arc's Peek as measured: 80% of the content area's width by the height minus 23, centered 11 pt from the top; the
/// sidebar stays live under it.
struct PeekView: View {
    let model: WindowModel
    let page: any Page
    let sidebarWidth: CGFloat
    @AppStorage(PageToolbar.key) private var showsToolbar = false

    var body: some View {
        GeometryReader { geometry in
            let contentWidth = geometry.size.width - sidebarWidth
            let margin = contentWidth * 0.1
            let panelWidth = contentWidth - 2 * margin
            ZStack(alignment: .topLeading) {
                // As Arc: nothing is dimmed, over a page or over the Library; the opener's card fades instead.
                HStack(spacing: 0) {
                    Backdrop(onClick: nil, color: .clear).frame(width: sidebarWidth)
                    Backdrop(onClick: model.closePeek, color: .clear)
                }
                panel
                    .frame(width: panelWidth, height: max(geometry.size.height - 23, 100))
                    .padding(.leading, sidebarWidth + margin)
                    .padding(.top, 11)
                controls
                    .padding(.leading, sidebarWidth + margin + panelWidth + 13)
                    .padding(.top, 11 + 7.5)
            }
        }
        .onAppear { page.activate() }
        .onChange(of: page.id) { _, _ in page.activate() }
        .onChange(of: showsToolbar ? page.id : nil, initial: true) { _, _ in
            model.trackPeekToolbarPage(showsToolbar ? page : nil)
        }
        .onDisappear { model.trackPeekToolbarPage(nil) }
    }

    /// Arc's `ModalV2HostView` card. Its toolbar needs View ▸ Show Toolbar.
    private var panel: some View {
        VStack(spacing: 0) {
            if showsToolbar {
                PeekToolbar(model: model, page: page)
                    .frame(height: 31.5)
                    .id(page.id)
                    .transition(.identity)
            }
            PageContentView(page: page).toast(of: model, on: page)
        }
        .pageRootBackground(page)
        .background(ARCUIColor.gray1)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.3), radius: 4, y: 1)
        .overlay(alignment: .top) {
            LoadingIndicator(isLoading: page.isLoading).offset(y: -7)
        }
    }

    /// As measured in Arc: 13 pt right of the panel at a 43.5 pt pitch.
    private var controls: some View {
        VStack(spacing: 10) {
            ModalButton(symbol: "xmark", size: 12, help: "Close Peek", action: model.closePeek)
            ModalButton(
                symbol: "arrow.up.left.and.arrow.down.right", size: 14.5, help: "Expand Peek", action: model.expandPeek)
            // Arc's third control, by its `ModalParentSplitState`: Create Split View on a lone tab, Add to Split View
            // on a split with room.
            if model.canAddPeekToSplitView {
                let inSplit = model.presentedTabIDs.count > 1
                ModalButton(
                    symbol: inSplit ? "square.split.1x2" : "square.split.2x1", size: 14,
                    help: inSplit ? "Add to Split View" : "Create Split View", action: model.addPeekToSplitView)
            }
        }
    }
}

/// The Peek's toolbar. In Arc a Peek's page sits in an ordinary window content controller, whose top bar is the
/// window's own `TopBarPanelContainerView`, so it takes its page's colour, starts and fades as the window's toolbar
/// does.
private struct PeekToolbar: View {
    let model: WindowModel
    let page: any Page
    @State private var initialColor: NSColor

    init(model: WindowModel, page: any Page) {
        self.model = model
        self.page = page
        _initialColor = State(initialValue: model.topBarColors.startingColor(for: page))
    }

    var body: some View {
        let color = model.topBarColors.appliedColor(for: page) ?? initialColor
        let theme = Theme(toolbarOver: color)
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
            ToolbarAddressLabel(url: page.url)
                .popover(isPresented: model.permissionPromptBinding(inPeekToolbar: true), arrowEdge: .bottom) {
                    if let request = model.promptedPermissionRequest {
                        PermissionRequestView(model: model, request: request)
                    }
                }
            Spacer()
            Color.clear.frame(width: 78)
        }
        .buttonStyle(ChromeButtonStyle())
        .padding(.horizontal, 10)
        .frame(maxHeight: .infinity)
        .environment(\.theme, theme)
        .background(Color(nsColor: color))
        .animation(.easeInOut(duration: 0.18), value: color)
    }
}

/// Arc's `ModalButtonStyle`.
private struct ModalButton: View {
    let symbol: String
    let size: CGFloat
    let help: String
    let action: () -> Void
    @Environment(\.theme) private var theme
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(theme.modalButtonGlyph)
                .frame(width: 18.5, height: 17.5)
                .padding(8)
                .background {
                    Capsule(style: .continuous)
                        .fill(theme.modalButtonFill)
                        .shadow(color: .black.opacity(hovering ? 0.3 : 0.2), radius: hovering ? 6 : 4, y: 1)
                }
                .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .offset(y: hovering ? -1 : 0)
        .animation(.spring(response: 0.15, dampingFraction: 0.95), value: hovering)
        .onHover { hovering = $0 }
        .help(help)
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
