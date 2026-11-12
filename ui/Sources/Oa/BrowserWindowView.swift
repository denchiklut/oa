import DevKit
import SwiftUI

struct BrowserWindowView: View {
    let model: WindowModel
    @State private var address = ""
    @State private var editing = false
    @State private var showingSiteControls = false
    @FocusState private var addressFocused: Bool

    var body: some View {
        HStack(spacing: 0) {
            SidebarView(model: model)
            Divider()
            VStack(spacing: 0) {
                if let placeholder = model.placeholder {
                    toolbar.hidden()
                    Divider()
                    PlaceholderView(image: placeholder)
                } else {
                    toolbar
                    Divider()
                    if let page = model.page {
                        PageContentView(page: page)
                    } else {
                        Color(nsColor: .windowBackgroundColor)
                    }
                }
            }
        }
        .overlay {
            if let peek = model.peek {
                PeekView(model: model, page: peek, sidebarWidth: sidebarWidth)
            }
        }
        .overlay {
            if let dialog = model.dialog {
                DialogView(model: model, dialog: dialog).id(ObjectIdentifier(dialog))
            }
        }
        .onChange(of: model.address) { _, url in
            if !editing || address.isEmpty { address = url?.absoluteString ?? "" }
        }
        .onChange(of: model.selectedTabID) { _, _ in
            address = model.address?.absoluteString ?? ""
            if model.address == nil { addressFocused = true }
        }
        .onChange(of: model.page?.id) { _, _ in
            DispatchQueue.main.async {
                guard let page = model.page else { return }
                if page.url == nil {
                    addressFocused = true
                } else if model.dialog == nil {
                    addressFocused = false
                    (model.peek ?? page).activate()
                }
            }
        }
        .onChange(of: model.dialog == nil) { _, none in
            if none { model.frontPage?.activate() }
        }
        .onChange(of: model.focusAddressField) { _, _ in
            addressFocused = true
            DispatchQueue.main.async { (NSApp.keyWindow?.firstResponder as? NSTextView)?.selectAll(nil) }
        }
        .onChange(of: addressFocused) { _, focused in
            editing = focused
            if !focused { address = model.address?.absoluteString ?? "" }
        }
        .onAppear {
            address = model.address?.absoluteString ?? ""
            if model.page == nil { addressFocused = true }
        }
    }

    private var sidebarWidth: CGFloat {
        model.showingArchive ? 0 : model.showingDownloads ? LibraryView.width : SidebarView.width
    }

    private var toolbar: some View {
        let page = model.page
        return HStack(spacing: 8) {
            Button {
                page?.goBack()
            } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(!(page?.canGoBack ?? false))
            Button {
                page?.goForward()
            } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(!(page?.canGoForward ?? false))
            Button {
                if page?.isLoading == true { page?.stopLoading() } else { page?.reload() }
            } label: {
                Image(systemName: page?.isLoading == true ? "xmark" : "arrow.clockwise")
            }
            .disabled(page == nil)
            TextField("Search or enter website name", text: $address)
                .textFieldStyle(.roundedBorder)
                .focused($addressFocused)
                .onSubmit {
                    model.navigate(to: address)
                    addressFocused = false
                }
                .overlay(alignment: .bottom) {
                    if let page, page.isLoading {
                        ProgressView(value: page.loadProgress)
                            .progressViewStyle(.linear)
                            .frame(height: 2)
                            .padding(.horizontal, 2)
                    }
                }
            // Arc's Site Controls button, which its permission prompt hangs from too. Oa's own: nothing to control
            // on a page that isn't a website.
            Button {
                showingSiteControls = true
            } label: {
                Image(systemName: "slider.horizontal.3")
            }
            .disabled(!["http", "https"].contains(page?.url?.scheme))
            // As Arc: another tab or another site closes it, a navigation within the site doesn't. Where Arc draws
            // the site's edge is unknown; the host is Oa's own.
            .onChange(of: [page?.id.uuidString, page?.url?.host()]) { showingSiteControls = false }
            .popover(isPresented: $showingSiteControls, arrowEdge: .bottom) {
                SiteControlsView(model: model, isSecure: page?.securityLevel == .secure) {
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
        .buttonStyle(.borderless)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }
}

private struct PlaceholderView: View {
    /// Measured in Arc: a placeholder keeps about 57% of its page's contrast.
    static let snapshotOpacity = 0.57

    let image: NSImage

    var body: some View {
        Color(nsColor: .windowBackgroundColor)
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

    func makeNSView(context: Context) -> Container { Container() }

    /// A host updated with the view it already placed leaves it alone: another host may have taken it since, as
    /// the window's does on Expand, and SwiftUI still updates the Peek's host on its way out.
    func updateNSView(_ container: Container, context: Context) {
        guard container.hosted !== view else { return }
        container.hosted = view
        container.subviews.forEach { $0.removeFromSuperview() }
        view.removeFromSuperview()
        view.translatesAutoresizingMaskIntoConstraints = true
        view.frame = container.bounds
        view.autoresizingMask = [.width, .height]
        container.addSubview(view)
    }

    final class Container: NSView {
        weak var hosted: NSView?

        override var isFlipped: Bool { true }

        override func layout() {
            super.layout()
            subviews.forEach { $0.frame = bounds }
        }
    }
}
