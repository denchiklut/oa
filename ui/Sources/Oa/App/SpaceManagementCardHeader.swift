import AppKit
import SwiftUI

struct SpaceManagementCardHeader: View {
    let model: WindowModel
    let space: SidebarSpace
    @Binding var isPickingIcon: Bool
    @Binding var isEditingName: Bool
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false
    @State private var isIconHovered = false
    @State private var isProfileHovered = false
    @State private var isProfileMenuOpen = false
    @FocusState private var isIconFocused: Bool

    private var isDark: Bool { colorScheme == .dark }
    private var hoverInk: Color { isDark ? .white : .black }
    private var hoveredText: Color {
        isDark ? .white.opacity(0.8) : Color(.sRGB, red: 14 / 255, green: 15 / 255, blue: 16 / 255, opacity: 0.9)
    }

    var body: some View {
        let highlighted = isHovered || isPickingIcon || isEditingName || isIconFocused
        let showsIcon = space.icon != nil || highlighted
        let row = RoundedRectangle(cornerRadius: 12, style: .circular)
        let rowFill =
            isDark
            ? Color(.sRGB, red: 0.980, green: 0.984, blue: 1, opacity: 0.10)
            : Color(.sRGB, red: 0.055, green: 0.059, blue: 0.063, opacity: 0.05)
        HStack(spacing: 5) {
            name
                .padding(.leading, showsIcon ? 28 : 0)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.1), value: showsIcon)
                .overlay(alignment: .leading) { iconButton(highlighted: highlighted) }
            profileMenu
            themeButton
        }
        .padding(.horizontal, 6)
        .frame(height: 36)
        .background(highlighted ? rowFill : .clear, in: row)
        .contentShape(row)
        .onHover { isHovered = $0 }
    }

    private var themeButton: some View {
        Button {
            model.presentSpaceStyleEditor(for: space.id, from: .library)
        } label: {
            Image(systemName: "paintbrush.pointed.fill")
                .font(.system(size: 12.5, weight: .regular))
                .offset(x: -0.5, y: -1)
                .foregroundStyle(hoverInk.opacity(0.3))
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Edit Space theme")
        .accessibilityLabel("Edit Space theme")
    }

    private func iconButton(highlighted: Bool) -> some View {
        let well = RoundedRectangle(cornerRadius: 4, style: .circular)
        return Button {
            isPickingIcon = true
        } label: {
            ZStack {
                well.fill(hoverInk.opacity(isIconHovered ? 0.1 : 0))
                if let icon = space.icon {
                    // As measured on Arc: in the card's `maxContrastColor`, like the sidebar's template icons.
                    SpaceIconGlyph(icon: icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(theme.maxContrast)
                }
                well.strokeBorder(hoverInk.opacity(highlighted ? 0.3 : 0), style: StrokeStyle(dash: [4, 2]))
            }
            .frame(width: 24, height: 24)
            .contentShape(well)
        }
        .buttonStyle(.plain)
        .focused($isIconFocused)
        .onHover { isIconHovered = $0 }
        .help("Edit Space icon")
        .accessibilityLabel("Edit Space icon")
        .popover(isPresented: $isPickingIcon, arrowEdge: .bottom) {
            SpaceIconPicker(selection: space.icon) { icon in
                model.setSpaceIcon(icon, for: space.id)
                isPickingIcon = false
            }
        }
    }

    @ViewBuilder private var name: some View {
        if isEditingName {
            SpaceNameField(name: space.name) { value in
                isEditingName = false
                guard let name = value?.trimmingCharacters(in: .whitespacesAndNewlines),
                    !name.isEmpty, model.state.space(space.id)?.name != name
                else { return }
                model.renameSpace(space.id, to: name)
            }
            .frame(height: 22)
            .frame(maxWidth: .infinity)
        } else {
            Button {
                isEditingName = true
            } label: {
                Text(space.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(hoverInk.opacity(0.45))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Rename Space")
        }
    }

    private var profileMenu: some View {
        let profile = model.profileName(space.profileID)
        return Menu {
            SpaceProfileMenuItems(model: model, space: space)
        } label: {
            HStack(spacing: 2) {
                Image(systemName: "person.crop.circle")
                    .foregroundStyle(Color(white: isDark ? 0.93 : 0.09))
                    .frame(width: 14, height: 14)
                Text(profile)
                    .lineLimit(1)
                    .frame(maxWidth: 96)
                    .foregroundStyle(isProfileHovered ? hoveredText : hoverInk.opacity(0.3))
            }
            .font(.system(size: 11, weight: .medium))
            .padding(.vertical, 4)
            .padding(.leading, 5)
            .padding(.trailing, 6)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Profile: \(profile)")
        }
        .menuStyle(.button)
        .buttonStyle(SpaceProfileChipStyle(isHovered: isProfileHovered, isMenuOpen: isProfileMenuOpen))
        .menuIndicator(.hidden)
        .fixedSize()
        .onHover { isProfileHovered = $0 }
        // The native menu starts tracking on mouse-down, before SwiftUI reports a press.
        .onReceive(NotificationCenter.default.publisher(for: NSMenu.didBeginTrackingNotification)) { _ in
            if isProfileHovered, model.window?.isKeyWindow == true { isProfileMenuOpen = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSMenu.didEndTrackingNotification)) { _ in
            isProfileMenuOpen = false
        }
        .animation(
            reduceMotion ? nil : .interpolatingSpring(mass: 0.25, stiffness: 75, damping: 35, initialVelocity: 30),
            value: isProfileHovered
        )
        .help("Change Profile")
    }
}

private struct SpaceProfileChipStyle: ButtonStyle {
    let isHovered: Bool
    let isMenuOpen: Bool
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        let shape = Capsule(style: .continuous)
        let fill = Color(white: colorScheme == .dark ? 0.11 : 0.973)
        let isPressed = configuration.isPressed || isMenuOpen
        let opacity = isPressed ? 0.8 : isHovered ? 1.0 : 0.3
        configuration.label
            .background {
                shape.fill(fill.opacity(opacity))
                    .shadow(color: .black.opacity(isHovered ? 0.1 : 0), radius: 8)
            }
            .contentShape(shape)
            .animation(
                reduceMotion ? nil : .interpolatingSpring(mass: 0.25, stiffness: 75, damping: 25, initialVelocity: 20),
                value: isPressed
            )
    }
}

private struct SpaceNameField: NSViewRepresentable {
    let name: String
    let finish: (String?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(finish: finish) }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(string: name)
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 13, weight: .semibold)
        field.cell?.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.setAccessibilityLabel("Space name")
        field.delegate = context.coordinator
        DispatchQueue.main.async { [weak field] in field?.selectText(nil) }
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {}

    static func dismantleNSView(_ field: NSTextField, coordinator: Coordinator) {
        field.delegate = nil
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        private var finish: ((String?) -> Void)?

        init(finish: @escaping (String?) -> Void) { self.finish = finish }

        func controlTextDidEndEditing(_ notification: Notification) {
            complete((notification.object as? NSTextField)?.stringValue)
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard selector == #selector(NSResponder.cancelOperation(_:)) else { return false }
            complete(nil)
            control.abortEditing()
            return true
        }

        private func complete(_ name: String?) {
            guard let finish else { return }
            self.finish = nil
            finish(name)
        }
    }
}

struct SpaceIconGlyph: View {
    let icon: String

    var body: some View {
        if icon.allSatisfy(\.isASCII) {
            Image(systemName: icon)
        } else {
            Text(icon)
        }
    }
}

struct SpaceIconPicker: View {
    let selection: String?
    let choose: (String?) -> Void
    @State private var category: Category

    private enum Category { case emoji, icon }

    init(selection: String?, choose: @escaping (String?) -> Void) {
        self.selection = selection
        self.choose = choose
        _category = State(initialValue: selection?.allSatisfy(\.isASCII) == false ? .emoji : .icon)
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Picker("Space icon type", selection: $category) {
                    Text("Emoji").tag(Category.emoji)
                    Text("Icon").tag(Category.icon)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Button {
                    choose(nil)
                } label: {
                    Image(systemName: "trash")
                }
                .disabled(selection == nil)
                .help("Remove Space icon")
                .accessibilityLabel("Remove Space icon")
            }
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(28), spacing: 4), count: 7), spacing: 4) {
                ForEach(category == .icon ? Self.symbols : Self.emoji, id: \.self) { icon in
                    Button {
                        choose(icon)
                    } label: {
                        SpaceIconGlyph(icon: icon)
                            .font(.system(size: 16, weight: .medium))
                            .frame(width: 28, height: 28)
                            .background(
                                icon == selection ? Color.primary.opacity(0.13) : .clear,
                                in: RoundedRectangle(cornerRadius: 5)
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        icon.replacingOccurrences(of: ".fill", with: "").replacingOccurrences(of: ".", with: " ")
                    )
                    .accessibilityAddTraits(icon == selection ? .isSelected : [])
                }
            }
        }
        .padding(12)
    }

    private static let symbols = [
        "star.fill", "heart.fill", "bolt.fill", "bookmark.fill", "flag.fill", "sparkles", "sun.max.fill",
        "moon.fill", "cloud.fill", "leaf.fill", "flame.fill", "drop.fill", "mountain.2.fill", "globe",
        "house.fill", "briefcase.fill", "folder.fill", "book.fill", "calendar", "tray.fill", "checkmark.circle.fill",
        "desktopcomputer", "terminal.fill", "hammer.fill", "gearshape.fill", "paintpalette.fill", "camera.fill",
        "headphones",
        "music.note", "film.fill", "gamecontroller.fill", "airplane", "bicycle", "cup.and.saucer.fill", "pawprint.fill",
    ]

    private static let emoji = [
        "😀", "😎", "🤓", "🥳", "🤖", "👋", "❤️",
        "⭐️", "✨", "⚡️", "🌈", "🔥", "☀️", "🌙",
        "🌱", "🌸", "🍀", "🐱", "🐶", "🦊", "🦋",
        "🏠", "🏙️", "🏕️", "🗺️", "✈️", "🚀", "🚲",
        "💼", "📚", "💻", "🎨", "🎮", "🎵", "☕️",
    ]
}
