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
