import DevKit
import SwiftUI

struct DeveloperExtensionsPopover: View {
    let model: WindowModel
    let profileName: String
    let palette: WindowTheme.SemanticColorPalette
    let dismiss: () -> Void
    @Environment(\.windowColorScheme) private var scheme

    var body: some View {
        let actions = model.extensionActions
        let ink: Color = scheme == .dark ? .white : .black
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                Image(systemName: "face.smiling.fill")
                Text(profileName).lineLimit(1)
            }
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 6)
            .frame(height: 22)
            .background(scheme == .dark ? Color(white: 0.14) : Color(white: 0.95), in: Capsule())
            .padding(.leading, 8)
            .padding(.bottom, 6)

            if !actions.isEmpty {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(actions) { action in
                            extensionRow(action)
                        }
                    }
                }
                .frame(height: min(CGFloat(actions.count) * 40, 320))
                .scrollBounceBehavior(.basedOnSize)

                Rectangle().fill(palette.hover.color)
                    .frame(height: 1).padding(.horizontal, 4).padding(.vertical, 8)
                    .accessibilityHidden(true)
            }

            command("Add Extension…", perform: model.addExtension)
            command("Manage Extensions…", perform: model.manageExtensions)
        }
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(ink)
        .buttonStyle(.plain)
        .padding(8)
        .frame(width: 250)
        .presentationBackground(palette.backgroundExtra.color)
        .environment(\.colorScheme, scheme)
    }

    private func extensionRow(_ action: ExtensionAction) -> some View {
        let pinned = action.pinnedPosition != nil
        return HStack(spacing: 0) {
            Button {
                dismiss()
                model.runExtension(action.id)
            } label: {
                HStack(spacing: 10) {
                    ExtensionActionIcon(action: action, size: 24)
                    Text(action.name).lineLimit(1)
                }
                .padding(.leading, 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .accessibilityLabel(action.name)
            .overlay {
                SecondaryClick {
                    model.showExtensionMenu(for: action.id)
                    dismiss()
                }
            }
            Button {
                model.togglePin(of: action)
            } label: {
                Image(systemName: pinned ? "pin.fill" : "pin")
                    .opacity(pinned ? 0.6 : 0.4)
                    .frame(width: 32, height: 40)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("\(pinned ? "Unpin" : "Pin") \(action.name)")
        }
        .modifier(MenuRow(hoverFill: palette.hover.color))
    }

    private func command(_ title: String, perform: @escaping () -> Void) -> some View {
        Button {
            dismiss()
            perform()
        } label: {
            Text(title)
                .padding(.leading, 10)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .modifier(MenuRow(hoverFill: palette.hover.color))
    }

    private struct MenuRow: ViewModifier {
        let hoverFill: Color
        @State private var hovering = false

        func body(content: Content) -> some View {
            content
                .frame(height: 40)
                .background(hovering ? hoverFill : .clear, in: RoundedRectangle(cornerRadius: 8))
                .onHover { hovering = $0 }
        }
    }
}
