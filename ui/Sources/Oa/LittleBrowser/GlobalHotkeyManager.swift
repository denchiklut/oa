import AppKit
import Carbon.HIToolbox

/// Arc's `GlobalHotkeyManager`: the New Little Arc Window shortcut as a Carbon hot key, which fires while another app
/// is in front. Registered while its switch is on, and again whenever the shortcut changes.
@MainActor
final class GlobalHotkeyManager {
    private let keyBindings: KeyBindingsClient
    private let action: () -> Void
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var registered: ARCKeyboardShortcut?
    private var defaultsObserver: (any NSObjectProtocol)?

    init(keyBindings: KeyBindingsClient, action: @escaping () -> Void) {
        self.keyBindings = keyBindings
        self.action = action
        var pressed = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, context in
                guard let context else { return noErr }
                let manager = Unmanaged<GlobalHotkeyManager>.fromOpaque(context).takeUnretainedValue()
                MainActor.assumeIsolated { manager.action() }
                return noErr
            }, 1, &pressed, Unmanaged.passUnretained(self).toOpaque(), &handler)
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.update() }
        }
        observeShortcut()
    }

    private func observeShortcut() {
        withObservationTracking {
            _ = keyBindings.state.shortcut(for: LittleBrowserPreferences.shortcutID)
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeShortcut() }
        }
        update()
    }

    private func update() {
        let wanted =
            UserDefaults.standard.bool(forKey: LittleBrowserPreferences.globalHotkeyKey)
            ? keyBindings.state.shortcut(for: LittleBrowserPreferences.shortcutID) : nil
        guard wanted != registered else { return }
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = nil
        registered = wanted
        guard let wanted, let code = KeyCode.code(for: wanted.menuKeyEquivalent) else { return }
        let carbon: [(NSEvent.ModifierFlags, Int)] = [
            (.command, cmdKey), (.option, optionKey), (.control, controlKey), (.shift, shiftKey),
        ]
        let modifiers = carbon.filter { wanted.modifiers.contains($0.0) }.reduce(0) { $0 | $1.1 }
        let status = RegisterEventHotKey(
            UInt32(code), UInt32(modifiers), EventHotKeyID(signature: 0x4F41_4C42, id: 1),
            GetApplicationEventTarget(), 0, &hotKey)
        if status != noErr { NSLog("Oa: Failed to register hotkey.") }
    }
}
