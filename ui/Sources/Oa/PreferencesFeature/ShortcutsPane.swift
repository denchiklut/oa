import AppKit
import SwiftUI

struct ShortcutsPane: View {
    let keyBindings: KeyBindingsClient
    @Bindable var state: PreferencesState
    let openExtensionShortcuts: () -> Void
    @State private var searchQuery = ""
    @State private var recordingIdentifier: String?
    @State private var heldModifiers: NSEvent.ModifierFlags = []
    @State private var hoveredBadge: String?
    @Environment(\.colorScheme) private var scheme

    private static let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Oa"

    private var selected: KeyBinding? {
        state.selectedKeyBindableActionIdentifier.flatMap { keyBindings.state.bindings[$0] }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 15) {
            list.frame(width: 341)
            detail.frame(width: 200, alignment: .leading)
        }
        .frame(height: 450)
        .padding(.leading, 64)
        .padding(.top, 85.5)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .overlay(alignment: .top) {
            EssentialShortcutsCallout(keyBindings: keyBindings).padding(.top, 20)
        }
        .overlayPreferenceValue(BadgeAnchors.self) { anchors in
            GeometryReader { proxy in
                if let id = hoveredBadge, let anchor = anchors[id], let binding = keyBindings.state.bindings[id] {
                    hoverCard(for: binding).position(x: proxy[anchor].midX, y: proxy[anchor].minY - 28)
                }
            }
        }
    }

    // MARK: The list

    private var list: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        let bindings = keyBindings.state.bindings.values.matching(searchQuery).sorted {
            $0.action.name < $1.action.name
        }
        let customized = bindings.filter { $0.source == .userDefined }
        return VStack(spacing: 0) {
            HStack(spacing: 4.5) {
                Image(systemName: "magnifyingglass").font(.system(size: 13)).foregroundStyle(tone(0.56, 0.44))
                TextField(
                    "", text: $searchQuery,
                    prompt: Text("Type a feature name or shortcut (like “Command E”)").foregroundStyle(tone(0.5, 0.65))
                )
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                if !searchQuery.isEmpty {
                    Button {
                        searchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 13)).foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 40.5)
            .background(scheme == .dark ? Color.white.opacity(0.10) : .clear)
            ScrollView {
                VStack(spacing: 0) {
                    section("Customized Shortcuts", customized, isFirst: true)
                    section(
                        "Default Shortcuts", bindings.filter { $0.source == .default }, isFirst: customized.isEmpty)
                }
            }
        }
        .background(scheme == .dark ? Color.white.opacity(0.01) : .white, in: shape)
        .clipShape(shape)
        .overlay(shape.strokeBorder(tone(0.86, 0.24), lineWidth: 1))
    }

    /// As measured in Arc: the title under the search field sits between two lines, a later one has none and
    /// stands closer to its rows.
    @ViewBuilder
    private func section(_ title: String, _ bindings: [KeyBinding], isFirst: Bool) -> some View {
        if !bindings.isEmpty {
            if isFirst { line }
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tone(0.5, 0.6))
                .padding(.leading, 16)
                .frame(maxWidth: .infinity, minHeight: 27, alignment: .leading)
            if isFirst { line }
            VStack(spacing: 0) {
                ForEach(bindings) { binding in
                    row(binding, isLast: binding.id == bindings.last?.id)
                }
            }
            .padding(.top, isFirst ? 10 : 4.5)
            .padding(.bottom, 20)
        }
    }

    private var line: some View { tone(0.93, 0.30).frame(height: 1) }

    private func row(_ binding: KeyBinding, isLast: Bool) -> some View {
        let isSelected = binding.id == state.selectedKeyBindableActionIdentifier
        let inConflict = !binding.conflictingActions.isEmpty
        return HStack(spacing: 10) {
            Button {
                NSApplication.shared.keyWindow?.makeFirstResponder(nil)
                state.selectedKeyBindableActionIdentifier = binding.id
            } label: {
                Text(Self.rowName(for: binding)).font(.system(size: 13)).lineLimit(1)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if inConflict {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Color(red: 1, green: 0.224, blue: 0.235))
                    .onHover { hoveredBadge = $0 ? binding.id : hoveredBadge == binding.id ? nil : hoveredBadge }
                    .anchorPreference(key: BadgeAnchors.self, value: .bounds) { [binding.id: $0] }
            }
            ShortcutKeyCaps(
                shortcut: binding.unvalidatedShortcut, isRecording: recordingIdentifier == binding.id
            ) { recording in
                heldModifiers = []
                if recording {
                    recordingIdentifier = binding.id
                    state.selectedKeyBindableActionIdentifier = binding.id
                } else if recordingIdentifier == binding.id {
                    recordingIdentifier = nil
                }
            } onBindingUpdated: {
                heldModifiers = $0
            } onBindingCommitted: {
                keyBindings.setShortcut($0, for: binding.id)
            }
        }
        .padding(.leading, 8)
        .padding(.trailing, 9)
        .frame(height: 40)
        .background(
            isSelected ? (inConflict ? conflictFill : selectionFill) : .clear,
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .padding(.horizontal, 16)
        .frame(height: 48)
        .overlay(alignment: .bottom) {
            if !isLast { tone(0.9, 0.25).frame(height: 1).padding(.leading, 24).padding(.trailing, 16) }
        }
        .contextMenu {
            Button("Remove Shortcut") { keyBindings.setShortcut(nil, for: binding.id) }
                .disabled(binding.unvalidatedShortcut == nil)
            Button("Reset Shortcut to Default") { keyBindings.resetToDefault(binding.id) }
                .disabled(binding.source == .default)
            if inConflict {
                Divider()
                removeConflictingButton(for: binding)
            }
        }
    }

    private var selectionFill: Color {
        scheme == .dark ? .blue.opacity(0.3) : Color(red: 0.918, green: 0.945, blue: 1)
    }

    private var conflictFill: Color {
        scheme == .dark ? .red.opacity(0.3) : Color(red: 1, green: 0.855, blue: 0.851)
    }

    private func removeConflictingButton(for binding: KeyBinding) -> some View {
        let actions = binding.conflictingActions
        return Button(actions.count == 1 ? "Remove Conflicting Shortcut" : "Remove Conflicting Shortcuts") {
            for action in actions { keyBindings.setShortcut(nil, for: action.identifier) }
        }
    }

    /// Arc's card over a conflict's badge, which comes with the pointer.
    private func hoverCard(for binding: KeyBinding) -> some View {
        let names = binding.conflictingActions.map(\.name).sorted()
        let others =
            switch names.count {
            case ...1: ""
            case 2: " and one other action"
            default: " and \(names.count - 1) other actions"
            }
        let shortcut = binding.unvalidatedShortcut?.symbols.joined() ?? ""
        return Text("\(shortcut) is already in use by “\(names.first ?? "")”\(others)")
            .font(.system(size: 12, weight: .semibold))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(width: 241)
            .background(
                Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .shadow(color: .black.opacity(0.2), radius: 8, y: 2)
            .allowsHitTesting(false)
    }

    // MARK: The detail side

    private var detail: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let binding = selected {
                let recording = recordingIdentifier == binding.id && !heldModifiers.isEmpty
                LargeKeyCaps(
                    symbols: recording
                        ? Array(ARCKeyboardShortcut(key: "", modifiers: heldModifiers).symbols.dropLast())
                        : binding.unvalidatedShortcut?.symbols ?? [],
                    inConflict: !binding.conflictingActions.isEmpty)
                Text(Self.rowName(for: binding)).font(.system(size: 14, weight: .semibold)).padding(.top, 23)
                caption(Self.description(for: binding.id)).padding(.top, 8)
                if binding.unvalidatedShortcut != nil {
                    line.padding(.top, 16)
                    Menu {
                        Picker(
                            "",
                            selection: Binding(
                                get: { binding.priority }, set: { keyBindings.setPriority($0, for: binding.id) })
                        ) {
                            ForEach(KeyBinding.Priority.allCases, id: \.self) { Text(Self.title(for: $0)).tag($0) }
                        }
                        .pickerStyle(.inline)
                        .labelsHidden()
                    } label: {
                        Text(Self.title(for: binding.priority))
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 9)
                    .padding(.trailing, 24)
                    .frame(width: 143.5, height: 24)
                    .background(tone(0.925, 0.28), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(alignment: .trailing) {
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 9, weight: .bold))
                            .padding(.trailing, 9)
                            .allowsHitTesting(false)
                    }
                    .padding(.top, 16)
                    caption(Self.subtitle(for: binding.priority)).padding(.top, 8)
                }
            } else {
                LargeKeyCaps(symbols: ["⌘", LargeKeyCaps.smile], inConflict: false)
                Text("Custom Shortcuts").font(.system(size: 14, weight: .semibold)).padding(.top, 23)
                caption(
                    """
                    Change shortcuts for your favorite actions, and even choose whether \(Self.appName) or a website \
                    takes priority.
                    """
                ).padding(.top, 8)
            }
            Spacer(minLength: 0)
            HStack(spacing: 4) {
                Group {
                    if let binding = selected {
                        Button("Reset Shortcut to Default") { keyBindings.resetToDefault(binding.id) }
                            .disabled(binding.source == .default)
                    } else {
                        resetAllButton
                    }
                }
                .buttonStyle(DetailButtonStyle())
                Menu {
                    Button("Remove Shortcut") { selected.map { keyBindings.setShortcut(nil, for: $0.id) } }
                        .disabled(selected?.unvalidatedShortcut == nil)
                    Divider()
                    if let binding = selected, !binding.conflictingActions.isEmpty {
                        removeConflictingButton(for: binding)
                    }
                    resetAllButton
                    Button("Extension Shortcuts…", action: openExtensionShortcuts)
                } label: {
                    Image(systemName: "ellipsis")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(width: 24, height: 24)
                .background(tone(0.925, 0.25), in: Circle())
                .accessibilityLabel("More shortcut options")
            }
        }
    }

    private var resetAllButton: some View {
        Button("Reset All Shortcuts") { keyBindings.resetToDefaults() }
            .disabled(keyBindings.state.userOverrides.isEmpty)
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(tone(0.56, 0.44))
            .fixedSize(horizontal: false, vertical: true)
    }

    private static func title(for priority: KeyBinding.Priority) -> String {
        switch priority {
        case .low: "Prefer Websites"
        case .promptAfterConsumedByWebView: "Use Both"
        case .overrideWebView: "Prefer \(appName)"
        }
    }

    private static func subtitle(for priority: KeyBinding.Priority) -> String {
        switch priority {
        case .low: "When shortcuts conflict, the website wins."
        case .promptAfterConsumedByWebView:
            """
            Press this shortcut once to use the website’s shortcut. Press it twice to use \(appName)’s shortcut.
            """
        case .overrideWebView: "When shortcuts conflict, \(appName) wins."
        }
    }

    private func tone(_ light: Double, _ dark: Double) -> Color { Color(white: scheme == .dark ? dark : light) }
}

private struct BadgeAnchors: PreferenceKey {
    static let defaultValue: [String: Anchor<CGRect>] = [:]
    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

/// Arc's buttons under the detail side: 24 pt tall and grey.
private struct DetailButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { Label(configuration: configuration) }

    private struct Label: View {
        let configuration: Configuration
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.colorScheme) private var scheme

        var body: some View {
            let dark = scheme == .dark
            configuration.label
                .font(.system(size: 13))
                .foregroundStyle(Color(white: dark ? (isEnabled ? 0.9 : 0.40) : (isEnabled ? 0.14 : 0.71)))
                .fixedSize()
                .padding(.horizontal, 12)
                .frame(height: 24)
                .background(
                    Color(white: dark ? (isEnabled ? 0.28 : 0.2) : (isEnabled ? 0.925 : 0.96)),
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                )
                .opacity(configuration.isPressed ? 0.7 : 1)
        }
    }
}

/// A row's key caps, "---" for none, with the recorder over them: grey at rest, a pale border under the pointer,
/// blue with a pale ring while the recorder has the keyboard.
private struct ShortcutKeyCaps: View {
    let shortcut: ARCKeyboardShortcut?
    let isRecording: Bool
    let onRecordingChanged: (Bool) -> Void
    let onBindingUpdated: (NSEvent.ModifierFlags) -> Void
    let onBindingCommitted: (ARCKeyboardShortcut?) -> Void
    @State private var isHovered = false
    @Environment(\.colorScheme) private var scheme

    private static let blue = Color(red: 0, green: 0.478, blue: 1)
    private static let paleBlue = Color(red: 0.78, green: 0.867, blue: 1)

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        Text(shortcut?.symbols.joined() ?? "---")
            .font(.system(size: 13))
            .foregroundStyle(
                isRecording
                    ? (shortcut == nil ? Color(red: 0.667, green: 0.8, blue: 1) : Self.blue)
                    : Color(white: 0.5)
            )
            .padding(.horizontal, 9)
            .frame(minWidth: 64, minHeight: 25)
            .background(.white, in: shape)
            .overlay(
                shape.strokeBorder(
                    isRecording ? Self.blue : isHovered ? Self.paleBlue : Color(white: scheme == .dark ? 0.26 : 0.93),
                    lineWidth: 1)
            )
            .overlay {
                if isRecording {
                    RoundedRectangle(cornerRadius: 12, style: .continuous).inset(by: -4).stroke(
                        Self.paleBlue, lineWidth: 1)
                }
            }
            .overlay {
                KeyboardShortcutInput(
                    onRecordingChanged: onRecordingChanged, onBindingUpdated: onBindingUpdated,
                    onBindingCommitted: onBindingCommitted, onHoverChanged: { isHovered = $0 })
            }
    }
}

/// The detail side's caps: one a symbol in a 201 pt row, 65 pt each until four have to fit, and two blank faded
/// ones for no shortcut. Blue, and red for a shortcut in conflict.
private struct LargeKeyCaps: View {
    /// Stands for the face Arc draws on the second cap while nothing is selected.
    static let smile = "smile"

    @Environment(\.colorScheme) private var scheme
    let symbols: [String]
    let inConflict: Bool

    var body: some View {
        let count = max(symbols.count, 2)
        let side = min(65, (201 - 3 * CGFloat(count - 1)) / CGFloat(count))
        HStack(spacing: 3) {
            ForEach(Array((symbols.isEmpty ? ["", ""] : symbols).enumerated()), id: \.offset) { cap($0.element, side) }
        }
        .opacity(symbols.isEmpty ? 0.4 : 1)
    }

    private func cap(_ symbol: String, _ side: CGFloat) -> some View {
        let scale = side / 65
        let border = inConflict ? Color(red: 0.945, green: 0.333, blue: 0.337) : Color(red: 0, green: 0.478, blue: 1)
        let rim, lip: Color
        let face: [Color]
        if inConflict {
            rim = Color(red: 0.96, green: 0.46, blue: 0.47)
            lip = Color(red: 0.88, green: 0.28, blue: 0.28)
            face = [Color(red: 1, green: 0.867, blue: 0.863), Color(red: 0.992, green: 0.816, blue: 0.816)]
        } else if scheme == .dark {
            rim = Color(red: 0.08, green: 0.43, blue: 0.88)
            lip = Color(red: 0.07, green: 0.39, blue: 0.8)
            face = [Color(red: 0.82, green: 0.88, blue: 0.98), Color(red: 0.74, green: 0.82, blue: 0.94)]
        } else {
            rim = Color(red: 0.239, green: 0.557, blue: 1)
            lip = Color(red: 0.216, green: 0.506, blue: 0.91)
            face = [Color(red: 0.843, green: 0.902, blue: 1), Color(red: 0.773, green: 0.855, blue: 0.98)]
        }
        let shape = RoundedRectangle(cornerRadius: 12 * scale, style: .continuous)
        return ZStack(alignment: .top) {
            shape.fill(lip)
            ZStack {
                shape.fill(rim)
                RoundedRectangle(cornerRadius: 9 * scale, style: .continuous)
                    .fill(LinearGradient(colors: face, startPoint: .top, endPoint: .bottom))
                    .overlay(
                        RoundedRectangle(cornerRadius: 9 * scale, style: .continuous)
                            .strokeBorder(.white.opacity(0.5), lineWidth: 1)
                    )
                    .padding([.top, .horizontal], 4.5 * scale)
                    .padding(.bottom, 1.5 * scale)
                if symbol == Self.smile {
                    Smile().stroke(border, style: StrokeStyle(lineWidth: 4 * scale, lineCap: .round)).frame(
                        width: 20 * scale, height: 22 * scale)
                } else {
                    Text(symbol)
                        .font(.system(size: (symbol.count > 1 ? 22 : 32) * scale, weight: .semibold, design: .rounded))
                        .foregroundStyle(border)
                }
            }
            .offset(y: 1.5 * scale)
            .padding(.bottom, 8 * scale)
            shape.strokeBorder(border, lineWidth: 1)
        }
        .frame(width: side, height: side + 0.5)
    }
}

private struct Smile: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        for x in [0.27, 0.73] {
            path.move(to: CGPoint(x: rect.width * x, y: 0))
            path.addLine(to: CGPoint(x: rect.width * x, y: rect.height * 0.40))
        }
        path.move(to: CGPoint(x: 0, y: rect.height * 0.83))
        path.addQuadCurve(
            to: CGPoint(x: rect.width, y: rect.height * 0.83),
            control: CGPoint(x: rect.width / 2, y: rect.height * 1.09)
        )
        return path
    }
}

extension Collection where Element == KeyBinding {
    /// As Arc's `bindings(matching:)`: a row matches by its name, or by its shortcut when the text reads as one,
    /// in words, in symbols or joined by "+" or "-". Modifiers the text doesn't name may be on the shortcut too.
    func matching(_ query: String) -> [KeyBinding] {
        let query = query.lowercased().trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return Array(self) }
        let parsed = Self.parseShortcut(query)
        return filter { binding in
            if binding.action.name.lowercased().contains(query) { return true }
            guard let parsed, let shortcut = binding.unvalidatedShortcut else { return false }
            return shortcut.modifiers.isSuperset(of: parsed.modifiers)
                && (parsed.key == nil || parsed.key == shortcut.keyEquivalent)
        }
    }

    private static func parseShortcut(_ query: String) -> (modifiers: NSEvent.ModifierFlags, key: String?)? {
        let modifierNames: [String: NSEvent.ModifierFlags] = [
            "command": .command, "cmd": .command, "⌘": .command, "control": .control, "ctrl": .control,
            "⌃": .control, "option": .option, "opt": .option, "alt": .option, "⌥": .option, "shift": .shift,
            "⇧": .shift,
        ]
        let keyNames = [
            "tab": "\t", "space": " ", "return": "\r", "enter": "\r", "escape": "\u{1B}", "esc": "\u{1B}",
            "delete": "\u{8}", "up": "\u{F700}", "down": "\u{F701}", "left": "\u{F702}", "right": "\u{F703}",
        ]
        var modifiers: NSEvent.ModifierFlags = []
        var key: String?
        var tokens = query.split(whereSeparator: { " -+".contains($0) }).map(String.init)
        // "⌘e" is its symbols and then the key.
        tokens = tokens.flatMap { token -> [String] in
            let symbols = token.prefix { modifierNames[String($0)] != nil }
            return symbols.map(String.init)
                + (symbols.count < token.count ? [String(token.dropFirst(symbols.count))] : [])
        }
        for token in tokens {
            if let modifier = modifierNames[token] {
                modifiers.insert(modifier)
            } else if key == nil, token.count == 1 || keyNames[token] != nil || token.wholeMatch(of: /f\d{1,2}/) != nil
            {
                let name =
                    keyNames[token]
                    ?? (token.count == 1 ? token : String(UnicodeScalar(0xF703 + (Int(token.dropFirst()) ?? 1))!))
                key = ARCKeyboardShortcut(key: name, modifiers: []).keyEquivalent
            } else {
                return nil
            }
        }
        return (modifiers, key)
    }
}
