import DevKit
import SwiftUI

struct BrowserWindowView: View {
    let model: WindowModel
    @State private var address = ""
    @State private var editing = false
    @FocusState private var addressFocused: Bool

    var body: some View {
        HStack(spacing: 0) {
            SidebarView(model: model)
            Divider()
            VStack(spacing: 0) {
                toolbar
                Divider()
                if let page = model.page {
                    PageHostView(view: page.view)
                } else {
                    Color(nsColor: .windowBackgroundColor)
                }
            }
        }
        .onChange(of: model.page?.url) { _, url in
            if !editing || address.isEmpty { address = url?.absoluteString ?? "" }
        }
        .onChange(of: model.selectedTabID) { _, _ in
            address = model.page?.url?.absoluteString ?? ""
            if model.page?.url == nil { addressFocused = true }
        }
        .onChange(of: model.page?.id) { _, _ in
            DispatchQueue.main.async {
                guard let page = model.page else { return }
                if page.url == nil {
                    addressFocused = true
                } else {
                    addressFocused = false
                    page.activate()
                }
            }
        }
        .onChange(of: model.focusAddressField) { _, _ in
            addressFocused = true
            DispatchQueue.main.async { (NSApp.keyWindow?.firstResponder as? NSTextView)?.selectAll(nil) }
        }
        .onChange(of: addressFocused) { _, focused in
            editing = focused
            if !focused { address = model.page?.url?.absoluteString ?? "" }
        }
        .onAppear {
            address = model.page?.url?.absoluteString ?? ""
            if model.page == nil { addressFocused = true }
        }
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
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }
}

private struct PageHostView: NSViewRepresentable {
    let view: NSView

    func makeNSView(context: Context) -> NSView { Container() }

    func updateNSView(_ container: NSView, context: Context) {
        guard view.superview !== container else { return }
        container.subviews.forEach { $0.removeFromSuperview() }
        view.translatesAutoresizingMaskIntoConstraints = true
        view.frame = container.bounds
        view.autoresizingMask = [.width, .height]
        container.addSubview(view)
    }

    private final class Container: NSView {
        override var isFlipped: Bool { true }
    }
}
