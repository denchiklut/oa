import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Arc's `KeyboardShortcutInputView`, the recorder under a row's key caps. A click makes it first responder, and
/// while it is, a local monitor takes the keys.
final class KeyboardShortcutInputView: NSView {
    var onRecordingChanged: (Bool) -> Void = { _ in }
    /// The modifiers held so far.
    var onBindingUpdated: (NSEvent.ModifierFlags) -> Void = { _ in }
    /// Nil unsets the action.
    var onBindingCommitted: (ARCKeyboardShortcut?) -> Void = { _ in }
    var onHoverChanged: (Bool) -> Void = { _ in }
    private var monitor: Any?
    private var resignObserver: NSObjectProtocol?

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) { window?.makeFirstResponder(self) }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(
            NSTrackingArea(
                rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { onHoverChanged(true) }
    override func mouseExited(with event: NSEvent) { onHoverChanged(false) }

    override func becomeFirstResponder() -> Bool {
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            self.map { $0.handle(event) } ?? event
        }
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: window, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.endRecording() }
        }
        onRecordingChanged(true)
        return true
    }

    override func resignFirstResponder() -> Bool {
        monitor.map(NSEvent.removeMonitor)
        monitor = nil
        resignObserver.map(NotificationCenter.default.removeObserver)
        resignObserver = nil
        onRecordingChanged(false)
        return true
    }

    private func endRecording() {
        if window?.firstResponder === self { window?.makeFirstResponder(nil) }
    }

    /// As Arc's monitor. A shortcut needs Control, Option or Command, or a function key. A plain key otherwise beeps
    /// and recording goes on; a shortcut a user may not set beeps and ends it. Tab and Escape end it with nothing
    /// changed, and Delete unsets.
    private func handle(_ event: NSEvent) -> NSEvent? {
        let modifiers = event.modifierFlags.intersection(ARCKeyboardShortcut.modifierMask)
        guard event.type == .keyDown else {
            onBindingUpdated(modifiers)
            return event
        }
        let isFunctionKey =
            event.specialKey.map {
                (NSEvent.SpecialKey.f1.rawValue...NSEvent.SpecialKey.f35.rawValue).contains($0.rawValue)
            } ?? false
        switch Int(event.keyCode) {
        case kVK_Tab where modifiers.isEmpty, kVK_Escape where modifiers.isEmpty:
            endRecording()
        case kVK_Delete where modifiers.isEmpty, kVK_ForwardDelete where modifiers.isEmpty:
            onBindingCommitted(nil)
            endRecording()
        default:
            guard !modifiers.subtracting(.shift).isEmpty || isFunctionKey,
                let shortcut = ARCKeyboardShortcut(event: event)
            else {
                NSSound.beep()
                break
            }
            if ARCKeyboardShortcut.shortcutsForbiddenForUsers.contains(shortcut) {
                NSSound.beep()
            } else {
                onBindingCommitted(shortcut)
            }
            endRecording()
        }
        return nil
    }
}

struct KeyboardShortcutInput: NSViewRepresentable {
    let onRecordingChanged: (Bool) -> Void
    let onBindingUpdated: (NSEvent.ModifierFlags) -> Void
    let onBindingCommitted: (ARCKeyboardShortcut?) -> Void
    let onHoverChanged: (Bool) -> Void

    func makeNSView(context: Context) -> KeyboardShortcutInputView { KeyboardShortcutInputView() }

    func updateNSView(_ view: KeyboardShortcutInputView, context: Context) {
        view.onRecordingChanged = onRecordingChanged
        view.onBindingUpdated = onBindingUpdated
        view.onBindingCommitted = onBindingCommitted
        view.onHoverChanged = onHoverChanged
    }
}
