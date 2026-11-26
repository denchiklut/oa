import DevKit
import SwiftUI

/// Arc's header: the window buttons 13 pt in, centred in a 40 pt row 4 pt below the window's top, then the sidebar
/// toggle at x 77 and back, forward and reload ending 6 pt from the sidebar's edge, 32 pt buttons on the same line,
/// over the URL field. With the toolbar shown the last three are on the page, and the header ends 36 pt down. Oa's
/// own: a sidebar too narrow for all of them drops those three; what Arc's header drops is unknown.
struct SidebarHeader: View {
    let model: WindowModel
    let layout: WindowLayoutController
    @AppStorage(PageToolbar.key) private var showsToolbar = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Button {
                    layout.toggleSidebar()
                } label: {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 16))
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(ChromeButtonStyle())
                .accessibilityLabel(layout.sidebarPresentation == .locked ? "Hide sidebar" : "Lock sidebar")
                Spacer(minLength: 0)
                if !showsToolbar, layout.sidebarWidth >= 215 {
                    NavigationButtons(page: model.frontPage, size: CGSize(width: 32, height: 32), spacing: 2)
                }
            }
            .padding(.leading, 77)
            .padding(.trailing, 6)
            .padding(.top, 7.5)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .frame(height: showsToolbar ? 36 : 46, alignment: .top)
            .background(WindowDragRegion())
            // As Arc: the Create a Space panel takes the URL field's place. While the panel comes or goes the field
            // goes with the Space's page, taking no room, so neither the page nor the panel moves.
            let shift = layout.addressFieldShift
            if !showsToolbar, model.spaceCreation == nil || shift != nil {
                let fade = layout.spaceCreationFade
                SidebarAddressField(model: model, layout: layout)
                    .padding(.horizontal, 8)
                    .offset(x: shift ?? 0)
                    .opacity(fade.map { $0.panel == nil ? 1 - $0.pages : $0.pages } ?? 1)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .frame(height: shift == nil ? nil : 0, alignment: .top)
                    .allowsHitTesting(shift == nil)
            }
        }
        .overlay(alignment: .topLeading) {
            WindowStandardButtonsView()
                .padding(.leading, 13)
                .padding(.top, 17)
        }
    }
}

/// Arc's URL field as measured: 36 pt tall, 8 pt in from the sidebar's edges, showing the page's host; pinned
/// extensions that fit beside the host, copy link and Site Controls at its end while the pointer is in the sidebar,
/// or while Site Controls or a permission prompt hangs from it.
struct SidebarAddressField: View {
    static let height: CGFloat = 36

    let model: WindowModel
    let layout: WindowLayoutController
    @State private var showingSiteControls = false
    @State private var trailingWidth: CGFloat = 0
    @Environment(\.theme) private var theme
    @Environment(\.sidebarRevealsControls) private var revealed

    var body: some View {
        let hasPage = model.address != nil && model.emptySplitViewPaneIndex == nil
        let controlsVisible =
            hasPage
            && (revealed || showingSiteControls || model.permissionPromptBinding(inPeekToolbar: false).wrappedValue)
        let pinned =
            hasPage
            ? PinnedExtensionLayout.addressFieldActions(
                model.pinnedExtensionActions, sidebarWidth: layout.sidebarWidth,
                hasFavorites: model.sidebarContext == .global && !model.favorites.isEmpty, staticButtons: 2)
            : []
        // As Arc: the URL opens the command bar to edit it, rather than being edited in place.
        Button {
            model.openCommandBar(.currentTab)
        } label: {
            // While the Create a Space panel is in, the field shows its Space's, whose page it goes with. As seen
            // in Arc: the prompt while a split's empty pane waits for the command bar.
            AddressFieldLabel(
                label: model.emptySplitViewPaneIndex == nil ? model.addressLabel(in: model.selectedSpaceID) : nil
            )
            .font(.system(size: 13, weight: .medium))
            .lineLimit(1)
            .foregroundStyle(theme.tertiaryText)
            .frame(height: Self.height)
            .mask {
                GeometryReader { geometry in
                    if controlsVisible, trailingWidth > 0, geometry.size.width > 0 {
                        let width = geometry.size.width
                        let end = max(0, (width - trailingWidth - 2) / width)
                        let start = max(0, (width - trailingWidth - 18) / width)
                        LinearGradient(
                            stops: [
                                .init(color: .black, location: 0),
                                .init(color: .black, location: start),
                                .init(color: .clear, location: end),
                                .init(color: .clear, location: 1),
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    } else {
                        Color.black
                    }
                }
            }
            .background(theme.fieldFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .trailing) {
            if hasPage {
                // As Arc's `CommandBarPlaceholderButtonsView`: 28 pt buttons, radius 9.
                HStack(spacing: 0) {
                    ForEach(pinned) { action in
                        PinnedExtensionButton(
                            model: model, action: action, size: CGSize(width: 28, height: 28), cornerRadius: 9)
                    }
                    CopyLinkButton(model: model, size: 28)
                    if model.presentedTabIDs.count > 1 {
                        // As seen in Arc: in a split, Share Split View… takes Site Controls' place, which the
                        // focused pane's bar has. Oa has no sharing, so it is off; the permission prompt still
                        // hangs from here, as Arc's does.
                        Button {
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 14))
                                .frame(width: 28, height: 28)
                        }
                        .buttonStyle(ChromeButtonStyle())
                        .accessibilityLabel("Share Split View…")
                        .disabled(true)
                        .background {
                            Color.clear.popover(
                                isPresented: model.permissionPromptBinding(inPeekToolbar: false), arrowEdge: .bottom
                            ) {
                                if let request = model.promptedPermissionRequest {
                                    PermissionRequestView(model: model, request: request)
                                }
                            }
                        }
                    } else {
                        SiteControlsButton(
                            model: model, size: CGSize(width: 28, height: 28),
                            showingSiteControls: $showingSiteControls)
                    }
                }
                .padding(.trailing, 4)
                .onGeometryChange(for: CGFloat.self) {
                    $0.size.width
                } action: {
                    trailingWidth = $0
                }
                .opacity(controlsVisible ? 1 : 0)
                .allowsHitTesting(controlsVisible)
                .transition(.opacity.animation(AddressFieldLabel.swap))
            }
        }
        .onChange(of: showingSiteControls || model.permissionPromptBinding(inPeekToolbar: false).wrappedValue) {
            layout.setHold(.popover, $1)
        }
    }
}

/// The host or the search prompt. Oa's own, by the author's decision, after open-arch: any change, a tab's or a
/// Space's, cross-fades in place, the new text sliding in from where the old one started.
struct AddressFieldLabel: View {
    static let swap = Animation.easeOut(duration: 0.1)

    /// How far the prompt's text sits right of the host's: the magnifier's 6 pt inset, 24 pt and 3 pt gap, less 12.
    private static let promptShift: CGFloat = 21

    let label: String?
    @Environment(\.theme) private var theme

    var body: some View {
        ZStack(alignment: .leading) {
            if let label {
                Text(label)
                    .foregroundStyle(theme.addressText)
                    .padding(.leading, 12)
                    .id(label)
                    .transition(Self.swap(from: Self.promptShift))
            } else {
                HStack(spacing: 3) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(theme.promptGlyph)
                        .frame(width: 24, height: 24)
                        .padding(.leading, 6)
                    Text("Search or Enter URL…")
                }
                .transition(Self.swap(from: -Self.promptShift))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(Self.swap, value: label)
    }

    private static func swap(from offset: CGFloat) -> AnyTransition {
        .asymmetric(insertion: .opacity.combined(with: .offset(x: offset)), removal: .opacity)
    }
}

struct NavigationButtons: View {
    let page: (any Page)?
    let size: CGSize
    let spacing: CGFloat
    var showsReload = true

    var body: some View {
        HStack(spacing: spacing) {
            button("arrow.left", 17, "Go back") { page?.goBack() }
                .disabled(!(page?.canGoBack ?? false))
            button("arrow.right", 17, "Go forward") { page?.goForward() }
                .disabled(!(page?.canGoForward ?? false))
            if showsReload {
                button(page?.isLoading == true ? "xmark" : "arrow.clockwise", 16, "Reload this page") {
                    if page?.isLoading == true { page?.stopLoading() } else { page?.reload() }
                }
                .disabled(page == nil)
            }
        }
        .buttonStyle(ChromeButtonStyle())
    }

    private func button(
        _ symbol: String, _ points: CGFloat, _ label: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: points))
                .frame(width: size.width, height: size.height)
        }
        .accessibilityLabel(label)
    }
}

/// The theme's icon colours and nothing else: Arc showed no hover fill on its header controls.
struct ChromeButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Glyph(label: configuration.label)
    }

    private struct Glyph: View {
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.theme) private var theme
        let label: Configuration.Label

        var body: some View {
            label
                .foregroundStyle(isEnabled ? theme.icon : theme.disabledIcon)
                .contentShape(Rectangle())
        }
    }
}
