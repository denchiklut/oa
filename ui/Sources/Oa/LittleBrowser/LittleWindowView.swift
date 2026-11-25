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
                    content
                }
                .background { WindowSurface(background: background, next: nil) }
                .overlay(alignment: .topTrailing) {
                    if model.little?.showsMoveMenu == true {
                        LittleBrowserMoveMenu(model: model)
                            .environment(\.colorScheme, appearance.colorScheme)
                    }
                }
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

    private var content: some View {
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
        .overlay(alignment: .topLeading) {
            if let request = model.permissionRequest {
                LittlePermissionRequestView(model: model, request: request)
                    .id(ObjectIdentifier(request))
                    .padding(8)
            }
        }
        .overlay(alignment: .topTrailing) {
            if model.little?.showsTip == true {
                LittleBrowserTip { model.little?.showsTip = false }
                    .padding(8)
            }
        }
        .overlay(alignment: .top) {
            LoadingIndicator(isLoading: model.page?.isLoading == true)
        }
    }
}

struct LittleBrowserToolbar: View {
    let model: WindowModel
    @Environment(\.theme) private var theme

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
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 29.5, height: 31)
                }
                .buttonStyle(ChromeButtonStyle())
                .accessibilityLabel("Back")
                .padding(.leading, 13.5)
            }
            field
                .padding(.leading, canGoBack ? 0 : 13.5)
            moveButton
                .padding(.leading, 8.5)
                .padding(.trailing, 7.5)
        }
        .frame(height: 47)
        .background(WindowDragRegion())
    }

    private var field: some View {
        ZStack {
            // As Arc: the URL opens the command bar to edit it.
            Button {
                model.openCommandBar(.currentTab)
            } label: {
                HStack(spacing: 5) {
                    if let page = model.page, page.url?.scheme != nil {
                        Image(systemName: page.securityLevel == .secure ? "lock.fill" : "lock.slash.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(page.securityLevel == .secure ? theme.secondaryGlyph : .orange)
                    }
                    ToolbarAddressLabel(url: model.address, placeholder: "Search or Enter URL…")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 110)
            HStack(spacing: 0) {
                if model.little?.shouldShowProfileIndicators == true { profileChip }
                Spacer(minLength: 0)
                CopyLinkButton(model: model, size: 16)
                    .help("Copy URL")
                    .opacity(model.address == nil ? 0 : 1)
                    .padding(.trailing, 7)
            }
        }
        .frame(height: 31)
        .background(RoundedRectangle(cornerRadius: 5).fill(theme.fieldFill))
    }

    private var profileChip: some View {
        let profileID = model.space?.profileID
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
            HStack(spacing: 3) {
                Image(systemName: "person.crop.circle")
                    .font(.system(size: 12))
                    .frame(width: 14, height: 14)
                Text(profileID.map(model.profileName) ?? "")
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(theme.addressText)
            .padding(.horizontal, 9)
            .frame(height: 23)
            .background(RoundedRectangle(cornerRadius: 5).fill(theme.itemFill))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Change profile")
        .padding(.leading, 4)
    }

    private var moveButton: some View {
        HStack(spacing: 0) {
            Button {
                model.openInLittleDestination()
            } label: {
                HStack(spacing: 4) {
                    Text("Open in").foregroundStyle(theme.modalButtonGlyph.opacity(0.6))
                    Text(model.littleDestinationSpace?.name ?? "")
                        .fontWeight(.bold)
                        .foregroundStyle(theme.modalButtonGlyph)
                        .lineLimit(1)
                    Text("⌘O")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(theme.modalButtonGlyph.opacity(0.6))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(RoundedRectangle(cornerRadius: 4).fill(theme.modalButtonGlyph.opacity(0.1)))
                        .padding(.leading, 4)
                }
                .font(.system(size: 13, weight: .medium))
                .padding(.leading, 6)
                .padding(.trailing, 8)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
            }
            .disabled(model.page == nil)
            theme.modalButtonGlyph.opacity(0.15).frame(width: 1, height: 16)
            Button {
                model.little?.showsMoveMenu = true
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(theme.modalButtonGlyph.opacity(0.6))
                    .frame(width: 28.5)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
            .help("More Spaces")
        }
        .buttonStyle(.plain)
        .frame(height: 30)
        .background(RoundedRectangle(cornerRadius: 5).fill(theme.modalButtonFill))
        .opacity(model.littleDestinationSpace == nil ? 0 : 1)
    }
}

/// As seen in Arc: in the button's place.
struct LittleBrowserMoveMenu: View {
    let model: WindowModel
    @State private var search = ""
    @FocusState private var searching: Bool
    @Environment(\.theme) private var theme

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { close() }
            VStack(spacing: 0) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12))
                        .foregroundStyle(theme.modalButtonGlyph.opacity(0.6))
                    TextField("Search Spaces…", text: $search)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .focused($searching)
                        .onSubmit { if let first = spaces.first { model.moveLittlePage(toSpace: first.id) } }
                    Button(action: close) {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(theme.modalButtonGlyph.opacity(0.6))
                            .frame(width: 28.5, height: 30)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.leading, 8)
                .frame(height: 30)
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(spaces) { space in
                            Row(space: space, isTarget: space.id == model.little?.destinationSpaceID) {
                                model.moveLittlePage(toSpace: space.id)
                            }
                        }
                    }
                    .padding(2)
                }
                .frame(height: min(spaces.reduce(4) { $0 + Row.height(isTarget: $1.id == targetID) }, 320))
            }
            .frame(width: 248)
            .background(RoundedRectangle(cornerRadius: 5).fill(theme.modalButtonFill))
            .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
            .padding(.top, 8)
            .padding(.trailing, 7.5)
        }
        .onAppear { searching = true }
        .onExitCommand(perform: close)
    }

    private func close() { model.little?.showsMoveMenu = false }
    private var targetID: UUID? { model.little?.destinationSpaceID }

    /// As seen in Arc: the button's Space, then the others in the sidebar's order, of every profile.
    private var spaces: [SidebarSpace] {
        let all = model.state.spaces
        let target = all.filter { $0.id == model.little?.destinationSpaceID }
        let ordered = target + all.filter { $0.id != model.little?.destinationSpaceID }
        return search.isEmpty ? ordered : ordered.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    private struct Row: View {
        let space: SidebarSpace
        let isTarget: Bool
        let action: () -> Void
        @State private var hovering = false
        @Environment(\.theme) private var theme

        static func height(isTarget: Bool) -> CGFloat { isTarget ? 46 : 36 }

        var body: some View {
            Button(action: action) {
                HStack(spacing: 8) {
                    Group {
                        if let icon = space.icon {
                            SpaceIconGlyph(icon: icon)
                        } else {
                            Image(systemName: "circle.fill").font(.system(size: 6))
                        }
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(theme.modalButtonGlyph)
                    .frame(width: 24, height: 24)
                    .background(RoundedRectangle(cornerRadius: 5).fill(theme.modalButtonGlyph.opacity(0.12)))
                    Text(space.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(theme.modalButtonGlyph)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 8)
                .frame(height: Self.height(isTarget: isTarget))
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(theme.modalButtonGlyph.opacity(isTarget || hovering ? 0.1 : 0))
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
        }
    }
}

/// Arc's `PermissionRequestDialogView`, which only its Little window shows: a card under the bar that only its
/// buttons end.
struct LittlePermissionRequestView: View {
    let model: WindowModel
    let request: PagePermissionRequest

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(PermissionRequestView.question(for: request, site: "this website"))
                .font(.system(size: 13, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 4) {
                Image(systemName: "lock.fill").font(.system(size: 9))
                Text("Click the lock to change this any time").font(.system(size: 11))
            }
            .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Button("Not Now") { model.respond(to: request, with: .deny) }
                    .buttonStyle(Style(fill: 0.06))
                Button("Allow") { model.respond(to: request, with: .allow) }
                    .buttonStyle(Style(fill: 0.16))
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(minWidth: 232, maxWidth: 280, alignment: .leading)
        .modifier(
            PopoverBackgroundView(cornerRadius: 8, shadowColor: .black.opacity(0.25), shadowRadius: 12, shadowY: 4)
        )
        .onDisappear { model.permissionPromptClosed() }
    }

    private struct Style: ButtonStyle {
        let fill: Double

        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .font(.system(size: 13, weight: .semibold))
                .frame(maxWidth: .infinity, minHeight: 32)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.primary.opacity(configuration.isPressed ? fill + 0.08 : fill))
                )
                .contentShape(Rectangle())
        }
    }
}

struct LittleBrowserTip: View {
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                (Text("Links Open in ") + Text("Little Oa").italic())
                    .font(.system(size: 13, weight: .bold))
                Text("Click “Open in” to move this page in a full window, or ⌘W to close")
                    .font(.system(size: 12))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(width: 260, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(red: 0.2, green: 0.36, blue: 0.96)))
        .shadow(color: .black.opacity(0.2), radius: 8, y: 2)
    }
}
