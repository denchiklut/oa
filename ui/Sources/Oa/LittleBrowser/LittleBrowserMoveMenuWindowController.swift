import AppKit
import SwiftUI

/// Arc's `LittleBrowserMoveMenuWindowController`: the Open in list is a clear window of its own, as big as the Little
/// window and over it, that has the keyboard while it is open and goes when it loses it.
@MainActor
final class LittleBrowserMoveMenuWindowController {
    private var window: MoveMenuWindow?
    private var observers: [NSObjectProtocol] = []

    func show(over parent: NSWindow, model: WindowModel) {
        guard window == nil else { return }
        let window = MoveMenuWindow(
            contentRect: parent.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.onCancel = { [weak model] in model?.little?.showsMoveMenu = false }
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.animationBehavior = .none
        window.appearance = parent.appearance
        window.contentView = NSHostingView(rootView: MoveMenuContent(model: model))
        window.setFrame(parent.frame, display: false)
        parent.addChildWindow(window, ordered: .above)
        window.makeKey()
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: NSWindow.didResizeNotification, object: parent, queue: .main) {
                [weak window, weak parent] _ in
                MainActor.assumeIsolated {
                    if let parent { window?.setFrame(parent.frame, display: true) }
                }
            },
            center.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main) {
                [weak model] _ in
                MainActor.assumeIsolated { model?.little?.showsMoveMenu = false }
            },
        ]
        self.window = window
    }

    func close() {
        guard let window else { return }
        self.window = nil
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        let parent = window.parent
        let wasKey = window.isKeyWindow
        parent?.removeChildWindow(window)
        window.orderOut(nil)
        if wasKey { parent?.makeKey() }
    }

    private final class MoveMenuWindow: NSWindow {
        var onCancel: () -> Void = {}

        override var canBecomeKey: Bool { true }
        override var canBecomeMain: Bool { false }

        override func performClose(_ sender: Any?) { parent?.performClose(sender) }
        override func cancelOperation(_ sender: Any?) { onCancel() }
    }
}

/// The Little window's palette and appearance, which the list is drawn in as the bar is.
private struct MoveMenuContent: View {
    let model: WindowModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let theme = WindowTheme.default
        let appearance = theme.background[colorScheme].contentOverBackgroundAppearance
        if model.little?.showsMoveMenu == true {
            LittleBrowserMoveMenu(model: model)
                .environment(
                    \.theme, Theme(palette: theme.semanticColorPalette[appearance.colorScheme], appearance: appearance)
                )
                .environment(\.colorScheme, appearance.colorScheme)
                .ignoresSafeArea()
        }
    }
}

/// Arc's `LittleBrowserMoveMenuView`, expanded: over the button, a little wider above and to its right. As seen in
/// Arc, one row is lit at a time: the button's Space at first, then the last one the pointer or an arrow key
/// reached, and the first match once the search changes.
private struct LittleBrowserMoveMenu: View {
    let model: WindowModel
    @State private var search = ""
    @State private var lit: UUID?
    @State private var isExpanded = false
    @State private var isCloseHovered = false
    @FocusState private var searching: Bool
    @Environment(\.theme) private var theme

    private static let rowHeight: CGFloat = 46

    private func ink(_ light: Double, _ dark: Double) -> Color {
        theme.isDark ? .white.opacity(dark) : .black.opacity(light)
    }

    var body: some View {
        let button = model.littleMoveButtonFrame
        let litID = lit ?? spaces.first?.id
        GeometryReader { window in
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(ink(0.3, 0.3))
                        .padding(.trailing, 8)
                    TextField("", text: $search, prompt: Text("Search Spaces…").foregroundStyle(ink(0.5, 0.55)))
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(ink(0.85, 0.85))
                        .focused($searching)
                        .onSubmit { litID.map(model.moveLittlePage) }
                        .onKeyPress(.downArrow) { light(1) }
                        .onKeyPress(.upArrow) { light(-1) }
                    ink(0.1, 0.1).frame(width: 1, height: 18).opacity(isCloseHovered ? 0 : 1)
                    Button(action: close) {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(ink(0.3, 0.33))
                            .rotationEffect(.radians(isExpanded ? .pi : 0))
                            .frame(width: 28.5)
                            .frame(maxHeight: .infinity)
                            .background(ink(0.04, 0.07).opacity(isCloseHovered ? 1 : 0))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .onHover { isCloseHovered = $0 }
                }
                .padding(.leading, 16)
                .frame(height: Self.rowHeight)
                if spaces.isEmpty {
                    Text("No results")
                        .font(.system(size: 13))
                        .foregroundStyle(ink(0.3, 0.3))
                        .frame(maxWidth: .infinity)
                        .frame(height: 64)
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(spaces) { space in
                                Row(
                                    space: space, color: model.theme(of: space).primaryColorPalette.shaded.color,
                                    isLit: space.id == litID,
                                    hover: { lit = space.id }
                                ) {
                                    model.moveLittlePage(toSpace: space.id)
                                }
                            }
                        }
                    }
                    .frame(height: min(CGFloat(spaces.count) * Self.rowHeight, 350))
                }
            }
            // Oa's own floor: Arc's width was only seen under a long Space name.
            .frame(width: max(button.width - 4, 244))
            .background(theme.modalButtonFill)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(ink(0.06, 0.1), lineWidth: 0.5)
            )
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(theme.modalButtonFill)
                    .shadow(color: .black.opacity(0.35), radius: 8, y: 4)
            )
            .padding(.top, button.minY - 4)
            .padding(.trailing, window.size.width - button.maxX - 4)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        }
        // Once the window has the keyboard: a field focused as it appears doesn't take it.
        .task { searching = true }
        .onAppear {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.63)) { isExpanded = true }
        }
        .onChange(of: search) { _, _ in lit = nil }
        .onExitCommand(perform: close)
    }

    private func close() { model.little?.showsMoveMenu = false }

    private func light(_ step: Int) -> KeyPress.Result {
        let ids = spaces.map(\.id)
        guard let index = (lit ?? ids.first).flatMap(ids.firstIndex) else { return .handled }
        lit = ids[min(max(index + step, 0), ids.count - 1)]
        return .handled
    }

    /// As seen in Arc: the button's Space, then the others in the sidebar's order, of every profile.
    private var spaces: [SidebarSpace] {
        let all = model.state.spaces
        let target = all.filter { $0.id == model.little?.destinationSpaceID }
        let ordered = target + all.filter { $0.id != model.little?.destinationSpaceID }
        return search.isEmpty ? ordered : ordered.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    /// As seen in Arc: the icon is the Space's colour under a white glyph in a dark list, and a pale wash of it
    /// under a glyph in the colour in a light one.
    private struct Row: View {
        let space: SidebarSpace
        let color: Color
        let isLit: Bool
        let hover: () -> Void
        let action: () -> Void
        @Environment(\.theme) private var theme

        var body: some View {
            Button(action: action) {
                HStack(spacing: 10) {
                    Group {
                        if let icon = space.icon {
                            SpaceIconGlyph(icon: icon)
                        } else {
                            Image(systemName: "circle.fill").font(.system(size: 6))
                        }
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(theme.isDark ? .white : color)
                    .frame(width: 26, height: 26)
                    .background(RoundedRectangle(cornerRadius: 4).fill(color.opacity(theme.isDark ? 1 : 0.1)))
                    Text(space.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(theme.isDark ? .white.opacity(0.8) : .black.opacity(0.85))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 10)
                .frame(height: LittleBrowserMoveMenu.rowHeight)
                .background((theme.isDark ? Color.white.opacity(0.07) : .black.opacity(0.04)).opacity(isLit ? 1 : 0))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { if $0 { hover() } }
        }
    }
}
