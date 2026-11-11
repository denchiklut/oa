import AppKit
import SwiftUI

/// Arc's Settings ▸ General, with the one setting Oa has so far.
@MainActor
final class SettingsWindowController: NSWindowController {
    init() {
        let window = NSWindow(contentViewController: NSHostingController(rootView: GeneralSettingsView()))
        window.title = "General"
        window.styleMask = [.titled, .closable]
        window.center()
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }
}

struct GeneralSettingsView: View {
    @AppStorage(QuitWarning.key) private var warnsBeforeQuitting = QuitWarning.isOnByDefault

    var body: some View {
        Form {
            Toggle("Warn before quitting", isOn: $warnsBeforeQuitting)
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 80)
    }
}

/// Arc's key. On by default is LIKELY Arc's: it stores only changed settings, and an install was seen holding this
/// one off beside the auto-update setting, which ships on.
enum QuitWarning {
    static let key = "shouldWarnBeforeQuitting"
    static let isOnByDefault = true

    static var isOn: Bool {
        get { UserDefaults.standard.object(forKey: key) as? Bool ?? isOnByDefault }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}
