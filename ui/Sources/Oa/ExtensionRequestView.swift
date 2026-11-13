import DevKit
import SwiftUI

/// Arc's consent panels as measured (arc-extensions.md §8b): 450 pt wide, centred over the dimmed window; Oa's icon
/// with the extension's and what it can do for an install, a puzzle piece for a removal; Return accepts, Esc cancels.
/// Drawn in the window as Oa's dialogs are, where Arc uses a child window.
struct ExtensionRequestView: View {
    let model: WindowModel
    let request: PageExtensionRequest

    var body: some View {
        ZStack {
            Backdrop(onClick: {}, opacity: 0.45)
            KeyTrap(onReturn: { answer(true) }, onEscape: { answer(false) })
            panel
                .padding(38)
                .frame(width: 450, alignment: .leading)
                .background(Color(nsColor: .windowBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .shadow(color: .black.opacity(0.35), radius: 24, y: 8)
        }
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 0) {
            icons.padding(.bottom, 18)
            Text(title)
                .font(.system(size: 18, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
            if request.kind == .install {
                details.padding(.top, 10)
            }
            HStack(spacing: 8) {
                Spacer()
                PanelButton(title: "Cancel", key: "ESC", prominent: false) { answer(false) }
                PanelButton(
                    title: request.kind == .install ? "Add Extension" : "Remove Extension", key: "⏎", prominent: true
                ) { answer(true) }
            }
            .padding(.top, request.kind == .install ? 16 : 40)
        }
    }

    @ViewBuilder private var icons: some View {
        if request.kind == .install {
            HStack(spacing: 18) {
                tile { Image(nsImage: NSApp.applicationIconImage).resizable().padding(6) }
                Image(systemName: "arrow.left")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.tertiary)
                tile {
                    if let icon = request.icon {
                        Image(nsImage: icon).resizable()
                    } else {
                        puzzlePiece
                    }
                }
            }
        } else {
            tile { puzzlePiece }
        }
    }

    private var puzzlePiece: some View {
        Image(systemName: "puzzlepiece.extension.fill").font(.system(size: 28))
    }

    private func tile(@ViewBuilder _ content: () -> some View) -> some View {
        content()
            .frame(width: 62, height: 62)
            .background(.primary.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder private var details: some View {
        if request.permissions.isEmpty {
            Text("This extension requires no special permissions.").font(.system(size: 14))
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("It can:")
                ForEach(request.permissions, id: \.self) { permission in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("•")
                        Text(permission).fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.leading, 6)
                }
            }
            .font(.system(size: 14))
        }
    }

    private var title: String {
        switch request.kind {
        case .install: "Add the “\(request.name)” extension to Oa?"
        case .uninstall: "Remove “\(request.name)” extension from Oa?"
        }
    }

    private func answer(_ accepted: Bool) {
        model.respond(to: request, accepted: accepted)
    }
}

/// Arc's panel button: its title, then the key that presses it.
private struct PanelButton: View {
    let title: String
    let key: String
    let prominent: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title).font(.system(size: 14, weight: .medium))
                Text(key)
                    .font(.system(size: 10, weight: .semibold))
                    .padding(.horizontal, 5)
                    .frame(height: 18)
                    .background(.primary.opacity(prominent ? 0 : 0.08), in: RoundedRectangle(cornerRadius: 4))
                    .overlay {
                        if prominent { RoundedRectangle(cornerRadius: 4).stroke(.white.opacity(0.6)) }
                    }
            }
            .foregroundStyle(prominent ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(
                prominent ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color(nsColor: .controlBackgroundColor)),
                in: RoundedRectangle(cornerRadius: 9)
            )
            .overlay {
                if !prominent { RoundedRectangle(cornerRadius: 9).stroke(.primary.opacity(0.15)) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
