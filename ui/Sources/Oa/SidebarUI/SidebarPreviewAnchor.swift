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
    func tabPreviewAnchor(
        model: WindowModel, layout: WindowLayoutController, tab: SidebarTab, hovering: Bool, eligible: Bool
    ) -> some View {
        if model.sidebarContext == .global, GmailAccount(url: tab.url) != nil || RecentPagesSite(url: tab.url) != nil {
            let enabled =
                RecentPagesSite(url: tab.url).map(model.previewPreferences.isEnabled)
                ?? model.previewPreferences.gmailEnabled
            modifier(
                SidebarPreviewAnchor(
                    layout: layout, id: tab.id, hovering: hovering,
                    enabled: eligible && enabled && layout.allowsTabPreview))
        } else {
            self
        }
    }
}

extension WindowLayoutController {
    func tabPreviewFrame(anchor: CGRect, width: CGFloat, height: CGFloat, favorite: Bool, centered: Bool) -> CGRect {
        let origin =
            favorite
            ? CGPoint(x: anchor.maxX - 4, y: anchor.maxY - 4)
            : CGPoint(x: anchor.maxX + (centered ? 12 : 8), y: centered ? anchor.midY - height / 2 : anchor.minY)
        return CGRect(
            x: max(4, min(origin.x, size.width - width - 4)),
            y: max(4, min(origin.y, size.height - height - 4)), width: width, height: height)
    }
}

struct SidebarPreviewCreateButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 15, weight: .medium))
                .frame(width: 32, height: 32)
                .background(.background, in: Circle())
                .overlay { Circle().strokeBorder(.primary.opacity(0.12)) }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .help(title)
        .padding(10)
    }
}
