import DevKit
import SwiftUI

/// Every Little window draws the default theme, as Arc's, whose hidden Space has none.
struct LittleWindowView: View {
    let model: WindowModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let theme = WindowTheme.default
        let background = theme.background[colorScheme]
        let appearance = background.contentOverBackgroundAppearance
        let focus = theme.semanticColorPalette[colorScheme].focus.color
        Group {
            if model.little?.isPresented == true {
                VStack(spacing: 0) {
                    LittleBrowserToolbar(model: model)
                        .environment(\.colorScheme, appearance.colorScheme)
                    content(palette: theme.semanticColorPalette[appearance.colorScheme])
                }
                .background { WindowSurface(background: background, next: nil) }
                .windowToast(of: model)
                .overlay {
                    if let bar = model.commandBar {
                        CommandBarView(model: model, bar: bar, themeFocus: focus, presentation: .littleWindow)
                            .id(ObjectIdentifier(bar))
                    }
                }
            } else if let bar = model.commandBar {
                CommandBarView(model: model, bar: bar, themeFocus: focus, presentation: .littleBar)
                    .id(ObjectIdentifier(bar))
            }
        }
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
                if model.dialog == nil, model.extensionRequest == nil, model.commandBar == nil {
                    model.page?.activate()
                }
            }
        }
        .onChange(of: model.dialog == nil && model.extensionRequest == nil) { _, none in
            if none, model.commandBar == nil { model.frontPage?.activate() }
        }
        .environment(
            \.theme, Theme(palette: theme.semanticColorPalette[appearance.colorScheme], appearance: appearance)
        )
        .environment(\.windowColorScheme, colorScheme)
        .ignoresSafeArea()
    }

    private func content(palette: WindowTheme.SemanticColorPalette) -> some View {
        Group {
            if let page = model.page {
                Group {
                    if page.crash != nil {
                        CrashedPageView(page: page)
                    } else {
                        PageHostView(view: page.view)
                    }
                }
                .pageRootBackground(page)
            } else {
                Color.clear
            }
        }
        .overlay(alignment: .bottom) {
            // As seen in Arc: the cards follow the window's appearance, not the page's.
            LittleBrowserDownloadsTray(model: model).environment(\.colorScheme, colorScheme)
        }
        .findInPage(of: model, on: model.page, hasTopBar: false)
        .toast(of: model, on: model.page)
        // As Arc's cards: they grow from 0.8 out of the window's edge and fade, in a tenth of a second.
        .overlay(alignment: .topLeading) {
            if let request = model.permissionRequest {
                LittlePermissionRequestView(model: model, request: request, palette: palette)
                    .id(ObjectIdentifier(request))
                    .padding(8)
                    .transition(.scale(scale: 0.8, anchor: .leading).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.1), value: model.permissionRequest == nil)
        .overlay(alignment: .topTrailing) {
            if model.little?.showsTip == true {
                LittleBrowserTip { model.little?.showsTip = false }
                    .padding(8)
                    .transition(.scale(scale: 0.8, anchor: .trailing).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.1), value: model.little?.showsTip)
        .overlay(alignment: .top) {
            LoadingIndicator(isLoading: model.page?.isLoading == true)
        }
    }
}

struct LittleBrowserToolbar: View {
    let model: WindowModel
    @State private var hoveredSegment: Segment?
    @Environment(\.theme) private var theme

    private enum Segment { case move, menu }

    /// As measured on Arc's bar: its greys are plain black or white, whatever the palette.
    private func ink(_ light: Double, _ dark: Double) -> Color {
        theme.isDark ? .white.opacity(dark) : .black.opacity(light)
    }

    var body: some View {
        let canGoBack = model.page?.canGoBack == true
        HStack(spacing: 0) {
            // As seen in Arc: the green button moves the page out, as Open in does.
            WindowStandardButtonsView(zoomAction: { model.openInLittleDestination() })
                .padding(.leading, 10)
            if canGoBack {
                Button {
                    model.page?.goBack()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(ink(0.3, 0.3))
                        .frame(width: 29.5, height: 31)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")
                .padding(.leading, 9.5)
            }
            field
                .padding(.leading, canGoBack ? 4 : 13.5)
            moveButton
                .fixedSize()
                .layoutPriority(1)
                .padding(.leading, 8.5)
                .padding(.trailing, 7.5)
                .offset(y: -0.5)
        }
        .frame(height: 47)
        .background(WindowDragRegion())
    }

    /// As seen in Arc: the host sits midway between the chip and Copy URL, and both give way in a narrow window.
    private var field: some View {
        HStack(spacing: 0) {
            if model.little?.shouldShowProfileIndicators == true { profileChip }
            // As Arc: the URL opens the command bar to edit it.
            Button {
                model.openCommandBar(.currentTab)
            } label: {
                HStack(spacing: 5) {
                    if let page = model.page, page.url?.scheme != nil {
                        if page.securityLevel == .secure {
                            Image(systemName: "lock.fill").font(.system(size: 10)).foregroundStyle(ink(0.5, 0.5))
                        } else {
                            Image(systemName: "lock.slash.fill")
                                .font(.system(size: 13))
                                .foregroundStyle(
                                    Color(.displayP3, red: 0xD8 / 255, green: 0x48 / 255, blue: 0x06 / 255))
                        }
                    }
                    ToolbarAddressLabel(
                        url: model.address, placeholder: "Search or Enter URL…", hostWeight: .regular,
                        color: ink(0.85, 0.8))
                }
                .padding(.horizontal, 6)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button {
                model.copyCurrentURLs()
            } label: {
                Image(systemName: "link")
                    .font(.system(size: 13))
                    .foregroundStyle(ink(0.3, 0.32))
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Copy Current URL")
            .help("Copy URL")
            .opacity(model.address == nil ? 0 : 1)
            .padding(.trailing, 7)
        }
        .frame(height: 31)
        .background(RoundedRectangle(cornerRadius: 5).fill(ink(0.05, 0.1)))
    }

    private var profileChip: some View {
        let profileID = model.little?.profile
        return Menu {
            ForEach(model.littleProfiles) { profile in
                Toggle(
                    profile.name,
                    isOn: Binding {
                        profile.id == profileID
                    } set: { _ in
                        if profile.id != profileID { ProfileDialogUtils.confirmLittleSwitch(to: profile.id, in: model) }
                    })
            }
        } label: {
            HStack(spacing: 3.5) {
                // Oa's own glyph: Arc draws the profile's icon here, and Oa's profiles have none yet.
                Image(systemName: "person.fill")
                    .font(.system(size: 8))
                    .frame(width: 14, height: 14)
                    .background(Circle().fill(ink(0.1, 0.1)))
                Text(profileID.map(model.profileName) ?? "")
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(ink(0.85, 0.8))
            .padding(.leading, 6.5)
            .padding(.trailing, 8)
            .frame(height: 22)
            .background(Capsule().fill(theme.isDark ? .black.opacity(0.19) : .white.opacity(0.27)))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .help("Change profile")
        .padding(.leading, 7.5)
    }

    /// As seen in Arc: only the Space's name takes a colour, its own Space's in a light bar.
    private var destinationInk: Color {
        guard !theme.isDark, let space = model.littleDestinationSpace else { return theme.modalButtonGlyph }
        return model.theme(of: space).primaryColorPalette.shadedDark.color
    }

    private var moveButton: some View {
        HStack(spacing: 0) {
            Button {
                model.openInLittleDestination()
            } label: {
                HStack(spacing: 4) {
                    Text("Open in").foregroundStyle(ink(0.5, 0.5))
                    Text(model.littleDestinationSpace?.name ?? "")
                        .foregroundStyle(destinationInk)
                        .lineLimit(1)
                    Text("⌘O")
                        .foregroundStyle(ink(0.54, 0.53))
                        .padding(.horizontal, 3.75)
                        .frame(height: 17)
                        .background(RoundedRectangle(cornerRadius: 3).fill(ink(0.08, 0.07)))
                        .padding(.leading, 2.5)
                }
                .font(.system(size: 13, weight: .medium))
                .padding(.horizontal, 6)
                .frame(maxHeight: .infinity)
                .background(ink(0.07, 0.07).opacity(hoveredSegment == .move ? 1 : 0))
                .contentShape(Rectangle())
            }
            .disabled(model.page == nil)
            .onHover { hoveredSegment = $0 ? .move : hoveredSegment == .move ? nil : hoveredSegment }
            ink(0.1, 0.1).frame(width: 1, height: 18).opacity(hoveredSegment == nil ? 1 : 0)
            Button {
                model.little?.showsMoveMenu = true
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(hoveredSegment == .menu ? ink(0.4, 0.33) : ink(0.3, 0.25))
                    .frame(width: 28.5)
                    .frame(maxHeight: .infinity)
                    .background(ink(0.07, 0.07).opacity(hoveredSegment == .menu ? 1 : 0))
                    .contentShape(Rectangle())
            }
            .help("More Spaces")
            .onHover { hoveredSegment = $0 ? .menu : hoveredSegment == .menu ? nil : hoveredSegment }
        }
        .buttonStyle(.plain)
        .frame(height: 30)
        .background(theme.modalButtonFill)
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(ink(0.06, 0.1), lineWidth: 0.5))
        .opacity(model.littleDestinationSpace == nil ? 0 : 1)
        .onGeometryChange(for: CGRect.self) {
            $0.frame(in: .global)
        } action: {
            model.littleMoveButtonFrame = $0
        }
    }
}

/// Arc's `PermissionRequestDialogView`, which only its Little window shows: a card under the bar, in the window's
/// palette, that only its buttons end.
struct LittlePermissionRequestView: View {
    let model: WindowModel
    let request: PagePermissionRequest
    let palette: WindowTheme.SemanticColorPalette

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: request.kinds.first?.symbol ?? "hand.raised.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(palette.maxContrastColor.color)
                    .frame(width: 24, height: 24)
                    .background(RoundedRectangle(cornerRadius: 4).fill(palette.background.color))
                Text(PermissionRequestView.question(for: request, site: "this website"))
                    .font(.system(size: 13, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("Click the \(Image(systemName: "lock.fill")) to change this any time").font(.system(size: 11))
            HStack(spacing: 8) {
                Button("Not Now") { model.respond(to: request, with: .deny) }
                    .buttonStyle(Style(fill: palette.backgroundExtra.color))
                Button("Allow") { model.respond(to: request, with: .allow) }
                    .buttonStyle(Style(fill: palette.focus.color))
            }
        }
        .foregroundStyle(.white)
        .padding(16)
        .frame(width: 232, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(palette.backgroundExtra.color)
                .shadow(color: .black.opacity(0.2), radius: 5, y: 3)
        )
        .padding(4)
        .onDisappear { model.permissionPromptClosed() }
    }

    /// As seen in Arc: each button stands on a line a point below it.
    private struct Style: ButtonStyle {
        let fill: Color

        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .font(.system(size: 13, weight: .semibold))
                .frame(maxWidth: .infinity, minHeight: 32)
                .background(RoundedRectangle(cornerRadius: 4).fill(fill))
                .background(RoundedRectangle(cornerRadius: 4).fill(.white.opacity(0.13)).offset(y: 1))
                .opacity(configuration.isPressed ? 0.8 : 1)
                .contentShape(Rectangle())
        }
    }
}

/// Arc's `LittleBrowserNUXView`, in its `BrandBlue` whatever the appearance.
struct LittleBrowserTip: View {
    let dismiss: () -> Void
    @State private var isCloseHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            (Text("Links Open in ") + Text("Little Oa").font(.system(size: 13, weight: .bold)).italic())
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
            WrappedLabel(maxWidth: 260) {
                Text("Click “Open in” to move this page in a full window, or ⌘W to close")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .padding([.leading, .vertical], 10)
        .padding(.trailing, 27)
        .overlay(alignment: .topTrailing) {
            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(.white.opacity(0.4))
                    .frame(width: 27, height: 27)
                    .background(
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(.white.opacity(isCloseHovered ? 0.15 : 0))
                            .padding(4)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { isCloseHovered = $0 }
            .accessibilityLabel("Close")
        }
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(.displayP3, red: 0.192, green: 0.224, blue: 0.984))
                .shadow(color: .black.opacity(0.3), radius: 5, y: 1)
        )
    }
}

/// As an AppKit label with a preferred maximum width: as wide as its longest line once wrapped there.
private struct WrappedLabel: Layout {
    let maxWidth: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        subviews.first?.sizeThatFits(ProposedViewSize(width: maxWidth, height: nil)) ?? .zero
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: ProposedViewSize(bounds.size))
    }
}
