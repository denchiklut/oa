import AppKit
import DevKit
import SwiftUI

/// Arc's Site Controls button, which its permission prompt hangs from too, on websites and Arc's own pages. Oa's
/// own: disabled on other pages, which Arc's research didn't cover.
struct SiteControlsButton: View {
    let model: WindowModel
    let size: CGSize
    @Binding var showingSiteControls: Bool
    /// One button of the window hangs the permission prompt: Arc's split has two, and its prompt goes with the
    /// first one to close.
    var hostsPermissionPrompt = true

    var body: some View {
        let page = model.page
        Button {
            showingSiteControls = true
        } label: {
            Image(systemName: "slider.horizontal.2.square")
                .font(.system(size: 16))
                .frame(width: size.width, height: size.height)
        }
        .buttonStyle(ChromeButtonStyle())
        .accessibilityLabel("Site Control Center")
        .disabled(!["http", "https", "chrome"].contains(page?.url?.scheme))
        // As Arc: another tab or another site closes it, a navigation within the site doesn't. Where Arc draws
        // the site's edge is unknown; the host is Oa's own.
        .onChange(of: [page?.id.uuidString, page?.url?.host()]) { showingSiteControls = false }
        .popover(isPresented: $showingSiteControls, arrowEdge: .bottom) {
            SiteControlsView(
                model: model, isSecure: page?.securityLevel == .secure, isInternal: page?.url?.scheme == "chrome"
            ) {
                showingSiteControls = false
            }
        }
        .background {
            if hostsPermissionPrompt {
                Color.clear.popover(
                    isPresented: model.permissionPromptBinding(inPeekToolbar: false), arrowEdge: .bottom
                ) {
                    if let request = model.promptedPermissionRequest {
                        PermissionRequestView(model: model, request: request)
                    }
                }
            }
        }
    }
}

/// Arc's Copy Current URL button.
struct CopyLinkButton: View {
    let model: WindowModel
    let size: CGFloat

    var body: some View {
        Button {
            model.copyCurrentURLs()
        } label: {
            Image(systemName: "link")
                .font(.system(size: 13))
                .frame(width: size, height: size)
        }
        .buttonStyle(ChromeButtonStyle())
        .accessibilityLabel("Copy Current URL")
    }
}

/// Where Arc places pinned extensions when the top toolbar is hidden (`WindowState+CommandBarPlaceholder` and
/// `WindowState+AppTray`): inside the URL pill while all of them fit beside a 100 pt host, else moved together into a
/// row above Favorites; without Favorites, the URL pill keeps as many trailing pins as fit (at least one).
enum PinnedExtensionLayout {
    /// 28 pt per button + 1 pt gap + 100 pt host room + 20 pt field insets + 16 pt sidebar padding.
    static func fitsInAddressField(count: Int, sidebarWidth: CGFloat) -> Bool {
        guard count > 0 else { return true }
        return CGFloat(count) * 28 + CGFloat(max(0, count - 1)) + 136 <= sidebarWidth
    }

    static func addressFieldActions(
        _ pinned: [ExtensionAction], sidebarWidth: CGFloat, hasFavorites: Bool, staticButtons: Int
    ) -> [ExtensionAction] {
        guard !pinned.isEmpty else { return [] }
        if hasFavorites {
            return fitsInAddressField(count: pinned.count, sidebarWidth: sidebarWidth) ? pinned : []
        }
        let room = sidebarWidth - 100 - CGFloat(staticButtons) * 28
        let cap = max(1, Int(floor(room / 28)))
        return Array(pinned.suffix(cap))
    }

    static func trayActions(
        _ pinned: [ExtensionAction], sidebarWidth: CGFloat, hasFavorites: Bool
    ) -> [ExtensionAction] {
        guard hasFavorites, !pinned.isEmpty, !fitsInAddressField(count: pinned.count, sidebarWidth: sidebarWidth) else {
            return []
        }
        return pinned
    }
}

/// An extension's 16 pt action icon, dimmed when disabled on the current page.
struct ExtensionActionIcon: View {
    let action: ExtensionAction

    var body: some View {
        Group {
            if let icon = action.icon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 16, height: 16)
            } else {
                Image(systemName: "puzzlepiece.extension.fill")
                    .font(.system(size: 13))
            }
        }
        .opacity(action.isEnabled ? 1 : 0.4)
    }
}

/// A pinned extension button for the sidebar URL pill or top toolbar: left-click runs the action, secondary click opens
/// Chrome's native extension menu.
struct PinnedExtensionButton: View {
    let model: WindowModel
    let action: ExtensionAction
    let size: CGSize
    let cornerRadius: CGFloat
    @State private var hovering = false
    @Environment(\.theme) private var theme

    var body: some View {
        let ink: Color = theme.isDark ? .white : .black
        Button {
            model.runExtension(action.id)
        } label: {
            ExtensionActionIcon(action: action)
                .frame(width: size.width, height: size.height)
                .background(
                    ink.opacity(hovering ? (theme.isDark ? 0.09 : 0.05) : 0),
                    in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.14), value: hovering)
        .overlay { SecondaryClick { model.showExtensionMenu(for: action.id) } }
        .help(action.tooltip.isEmpty ? action.name : action.tooltip)
        .accessibilityLabel(action.name)
    }
}

/// Takes the secondary click over a view and nothing else; the engine draws the menu, which SwiftUI's own can't.
struct SecondaryClick: NSViewRepresentable {
    let action: () -> Void

    func makeNSView(context: Context) -> ClickView { ClickView() }

    func updateNSView(_ view: ClickView, context: Context) { view.action = action }

    final class ClickView: NSView {
        var action: () -> Void = {}

        override func hitTest(_ point: NSPoint) -> NSView? {
            let event = NSApp.currentEvent
            let secondary =
                event?.type == .rightMouseDown
                || (event?.type == .leftMouseDown && event?.modifierFlags.contains(.control) == true)
            return secondary ? super.hitTest(point) : nil
        }

        override func rightMouseDown(with event: NSEvent) { action() }
        override func mouseDown(with event: NSEvent) { action() }
    }
}

struct ToolbarAddressLabel: View {
    static let fullURLPreferenceKey = "toolbarShowFullURLsEnabledPreference"

    let url: URL?
    var placeholder = ""
    var hostWeight = Font.Weight.medium
    var color: Color?
    @AppStorage(ToolbarAddressLabel.fullURLPreferenceKey) private var showsFullURL = false
    @Environment(\.theme) private var theme

    var body: some View {
        let (host, remainder) = addressParts
        let addressText = color ?? theme.addressText
        let hostColor = url == nil ? theme.secondaryText : addressText
        // Arc gives the host more weight and the rest five sixths of its opacity.
        let hostText = Text(host).font(.system(size: 13, weight: hostWeight)).foregroundStyle(hostColor)
        let remainderText = Text(remainder).font(.system(size: 13)).foregroundStyle(addressText.opacity(5.0 / 6))
        Text("\(hostText)\(remainderText)").lineLimit(1)
    }

    private var addressParts: (String, String) {
        guard let url else { return (placeholder, "") }
        guard showsFullURL, let components = URLComponents(url: url, resolvingAgainstBaseURL: true),
            let host = components.encodedHost, !host.isEmpty
        else { return (WindowModel.addressLabel(url), "") }

        // Arc omits HTTPS and shows the HTTP scheme on local pages.
        let scheme = components.scheme.map { $0.lowercased() == "https" ? "" : "\($0)://" } ?? ""
        let port = components.port.map { ":\($0)" } ?? ""
        let query = components.percentEncodedQuery.map { "?\($0)" } ?? ""
        let fragment = components.percentEncodedFragment.map { "#\($0)" } ?? ""
        return (scheme + host + port, components.percentEncodedPath + query + fragment)
    }
}

extension WindowModel {
    /// As Arc's field: the host without a leading `www.`, and nothing else. Oa's own: the whole address of a page
    /// without a host.
    var addressLabel: String? { address.map(Self.addressLabel) }

    /// What the field shows on a Space's page: its selected tab's, the window's Space's with its Peek.
    func addressLabel(in spaceID: UUID) -> String? {
        if spaceID == selectedSpaceID, spaceCreation == nil { return addressLabel }
        return selectedTabIDs[spaceID].flatMap { addressLabel(of: $0) }
    }

    /// `whole`, as seen on a stacked split's panes: the address after its scheme.
    func addressLabel(of tabID: UUID, whole: Bool = false) -> String? {
        guard let url = pages[tabID]?.url ?? state.tree.tab(tabID)?.url else { return nil }
        guard whole, let scheme = url.scheme else { return Self.addressLabel(url) }
        return String(url.absoluteString.dropFirst(scheme.count + 3))
    }

    fileprivate static func addressLabel(_ url: URL) -> String {
        guard let host = url.host(), !host.isEmpty else { return url.absoluteString }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}
