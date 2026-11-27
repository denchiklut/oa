import DevKit
import SwiftUI

struct DeveloperToolbar<Trailing: View>: View {
    let model: WindowModel
    let tabID: UUID
    let page: any Page
    var showSidebar: (() -> Void)?
    @ViewBuilder let trailing: Trailing
    @State private var showingSiteControls = false
    @State private var showingExtensions = false
    @Environment(\.windowColorScheme) private var scheme
    @AppStorage(PageToolbar.key) private var ordinaryToolbarShown = false

    var body: some View {
        let palette = (model.space.map(model.theme(of:)) ?? .default).semanticColorPalette[scheme]
        // Calibrated against Arc's orange dark toolbar and its default light toolbar.
        let fill = scheme == .dark ? palette.focus.over(.black) : palette.maxContrastColor.opacity(0.02).over(.white)
        let chrome = Theme(toolbarOver: fill.nsColor)
        let accent = palette.maxContrastColor.color
        HStack(spacing: 2) {
            if let showSidebar {
                tool("Show Sidebar", "sidebar.left", action: showSidebar)
                    .labelStyle(.iconOnly)
            }
            tool("Site Settings", page.securityLevel == .secure ? "lock.fill" : "info.circle") {
                showingSiteControls = true
            }
            .labelStyle(.iconOnly)
            .onChange(of: page.url?.host()) { showingSiteControls = false }
            .onChange(of: model.frontPage?.id) {
                if model.frontPage?.id != page.id { showingSiteControls = false }
            }
            .popover(isPresented: $showingSiteControls, arrowEdge: .bottom) {
                SiteControlsView(
                    model: model, isSecure: page.securityLevel == .secure, isInternal: page.url?.scheme == "chrome"
                ) {
                    showingSiteControls = false
                }
            }
            .background {
                if ordinaryToolbarShown && page.id == model.frontPage?.id {
                    Color.clear.popover(
                        isPresented: model.permissionPromptBinding(inPeekToolbar: false), arrowEdge: .bottom
                    ) {
                        if let request = model.promptedPermissionRequest {
                            PermissionRequestView(model: model, request: request)
                        }
                    }
                }
            }
            Button {
                model.select(tabID)
                model.openCommandBar(.currentTab)
            } label: {
                Text(page.url?.absoluteString ?? "")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(chrome.foreground)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(minWidth: 44, maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Edit URL")
            .accessibilityValue(page.url?.absoluteString ?? "")
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 2) {
                    tool("Copy Link", "link") { model.copyURL(of: tabID) }
                    divider
                    PortraitCaptureButton(model: model, page: page, tabID: tabID)
                    Button {
                        model.select(tabID)
                        model.startRegionCapture(on: page)
                    } label: {
                        Image(systemName: "camera").frame(width: 28, height: 28).contentShape(Rectangle())
                    }
                    .accessibilityLabel("Capture a portion of this page")
                    .oaToolTip(
                        "Capture a portion of this page", shortcut: model.keyBindings.state.shortcut(for: "capturePage")
                    )
                    .environment(\.oaToolTipPalette, .developerToolbar(palette))
                    divider
                    inspectorActions
                    divider
                }
                .fixedSize()
                .labelStyle(.iconOnly)
                Menu {
                    tool("Copy Link", "link") { model.copyURL(of: tabID) }
                    Divider()
                    tool("Capture in Portrait Mode", "camera.macro") {
                        model.portraitCapture.capture(page: page, in: model, quick: false)
                    }
                    tool("Capture a portion of this page", "camera") { model.startRegionCapture(on: page) }
                    Divider()
                    inspectorActions
                } label: {
                    Image(systemName: "ellipsis").frame(width: 28, height: 28)
                }
                .menuStyle(.button)
                .menuIndicator(.hidden)
                .accessibilityLabel("Developer Tools")
            }
            tool("Extensions Menu", "puzzlepiece.extension") { showingExtensions = true }
                .labelStyle(.iconOnly)
                .popover(isPresented: $showingExtensions, arrowEdge: .bottom) {
                    DeveloperExtensionsPopover(
                        model: model, profileName: model.profileName(page.profileID), palette: palette
                    ) {
                        showingExtensions = false
                    }
                }
            trailing.environment(\.theme, chrome)
        }
        .task(id: page.id) { model.enteredDeveloperMode(for: tabID) }
        .buttonStyle(.plain)
        .foregroundStyle(accent)
        .padding(.horizontal, 5)
        .frame(height: 40)
        .background {
            Canvas { context, size in
                var stripes = Path()
                for x in stride(from: -size.height, through: size.width + 12, by: 45) {
                    stripes.move(to: CGPoint(x: x, y: 0))
                    stripes.addLine(to: CGPoint(x: x + size.height, y: size.height))
                }
                context.stroke(stripes, with: .color(accent.opacity(scheme == .dark ? 0.02 : 0.015)), lineWidth: 15)
            }
            .background(fill.color)
        }
    }

    private var divider: some View {
        Rectangle().fill(.foreground.opacity(0.15)).frame(width: 1, height: 20).padding(.horizontal, 2)
            .accessibilityHidden(true)
    }

    @ViewBuilder private var inspectorActions: some View {
        tool("Toggle Console", "terminal") { page.devTools.toggleConsole() }
        tool("Toggle Network Panel", "network") { page.devTools.toggleNetwork() }
        tool("Inspect Element", "scope") { page.devTools.inspect() }
    }

    private func tool(_ title: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button {
            model.select(tabID)
            action()
        } label: {
            Label {
                Text(title)
            } icon: {
                Image(systemName: symbol)
                    .font(.system(size: 14))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
        }
        .accessibilityLabel(title)
        .oaToolTip(title)
    }
}
