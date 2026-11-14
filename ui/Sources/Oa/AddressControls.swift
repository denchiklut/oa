import AppKit
import DevKit
import SwiftUI

/// Arc's Site Controls button, which its permission prompt hangs from too, on websites and Arc's own pages. Oa's
/// own: disabled on other pages, which Arc's research didn't cover.
struct SiteControlsButton: View {
    let model: WindowModel
    let size: CGSize
    @Binding var showingSiteControls: Bool

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
            Color.clear.popover(isPresented: model.permissionPromptBinding(forPeek: false), arrowEdge: .bottom) {
                if let request = model.promptedPermissionRequest {
                    PermissionRequestView(model: model, request: request)
                }
            }
        }
    }
}

/// Arc's Copy Current URL button, without its toast.
struct CopyLinkButton: View {
    let model: WindowModel
    let size: CGFloat

    var body: some View {
        Button {
            guard let address = model.address else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(address.absoluteString, forType: .string)
        } label: {
            Image(systemName: "link")
                .font(.system(size: 13))
                .frame(width: size, height: size)
        }
        .buttonStyle(ChromeButtonStyle())
        .accessibilityLabel("Copy Current URL")
    }
}

extension WindowModel {
    /// As Arc's field: the host without a leading `www.`, and nothing else. Oa's own: the whole address of a page
    /// without a host.
    var addressLabel: String? {
        address.map { url in
            guard let host = url.host(), !host.isEmpty else { return url.absoluteString }
            return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        }
    }
}
