import DevKit
import SwiftUI

struct DeveloperToolbar<Trailing: View>: View {
    let model: WindowModel
    let tabID: UUID
    let page: any Page
    var showSidebar: (() -> Void)?
    @ViewBuilder let trailing: Trailing
    @State private var showingExtensions = false
    @Environment(\.windowColorScheme) private var scheme
    @AppStorage(PageToolbar.key) private var ordinaryToolbarShown = false

    var body: some View {
        let palette = (model.space.map(model.theme(of:)) ?? .default).primaryColorPalette
        let accent = scheme == .dark ? palette.tintedLight.color : palette.shaded.color
        HStack(spacing: 2) {
            if let showSidebar {
                tool("Show Sidebar", "sidebar.left", action: showSidebar)
                    .labelStyle(.iconOnly)
            }
            tool("Site Settings", page.securityLevel == .secure ? "lock.fill" : "info.circle") {
                model.openAllSiteSettings()
            }
            .labelStyle(.iconOnly)
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
                    .foregroundStyle(Color.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(minWidth: 44, maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Edit URL")
            .accessibilityValue(page.url?.absoluteString ?? "")
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 2) {
                    inspectorActions
                        .labelStyle(.iconOnly)
                }
                Menu {
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
                    ExtensionsSection(model: model) { showingExtensions = false }
                        .padding(10).frame(width: 236)
                }
            trailing
        }
        .buttonStyle(.plain)
        .foregroundStyle(accent)
        .padding(.horizontal, 5)
        .frame(height: 40)
        .background {
            Canvas { context, size in
                var stripes = Path()
                for x in stride(from: -size.height, to: size.width, by: 32) {
                    stripes.move(to: CGPoint(x: x, y: 0))
                    stripes.addLine(to: CGPoint(x: x + size.height, y: size.height))
                }
                context.stroke(stripes, with: .color(accent.opacity(0.035)), lineWidth: 14)
            }
            .background(accent.opacity(0.03))
            .background(scheme == .dark ? Color.black : .white)
        }
    }

    @ViewBuilder private var inspectorActions: some View {
        tool("Copy Link", "link") { model.copyURL(of: tabID) }
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
        .help(title)
    }
}
