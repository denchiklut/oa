import SwiftUI

struct SidebarPreviewAnchor: ViewModifier {
    let layout: WindowLayoutController
    let id: UUID
    let hovering: Bool
    let enabled: Bool
    @Environment(\.sidebarDrag) private var drag
    @State private var frame = CGRect.zero

    private var ownsPreview: Bool {
        layout.sidebarPreview?.id == id && layout.sidebarPreview?.anchor == frame
    }

    func body(content: Content) -> some View {
        let available = enabled && drag?.entry == nil && drag?.isLinkDrag != true
        content
            .sidebarDragFrame { rect in
                if rect != frame, ownsPreview { layout.dismissSidebarPreview() }
                frame = rect
            }
            .task(id: hovering && available) {
                guard hovering && available else { return }
                // Oa uses the same deliberate hover for a folder, pinned row and Favorite.
                try? await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled, !frame.isEmpty else { return }
                layout.showSidebarPreview(id, at: frame)
            }
            .onChange(of: hovering) { if !hovering && ownsPreview { layout.leaveSidebarPreview(id) } }
            .onChange(of: available) { if !available && ownsPreview { layout.dismissSidebarPreview() } }
            .onDisappear { if ownsPreview { layout.dismissSidebarPreview() } }
    }
}

extension View {
    @ViewBuilder
    func recentPagesPreviewAnchor(
        model: WindowModel, layout: WindowLayoutController, tab: SidebarTab, hovering: Bool, eligible: Bool
    ) -> some View {
        if let site = RecentPagesSite(url: tab.url), model.sidebarContext == .global {
            modifier(
                SidebarPreviewAnchor(
                    layout: layout, id: tab.id, hovering: hovering,
                    enabled: eligible && model.previewPreferences.isEnabled(site) && layout.allowsTabPreview))
        } else {
            self
        }
    }
}
