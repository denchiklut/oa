import AppKit
import DevKit
import SwiftUI

/// Arc's Settings, with the panes Oa has so far: General and Profiles.
@MainActor
final class SettingsWindowController: NSWindowController {
    init(engine: any BrowserApplication, store: SidebarStore) {
        let content = TabView {
            GeneralSettingsView().tabItem { Text("General") }
            ProfilesSettingsView(engine: engine, store: store).tabItem { Text("Profiles") }
        }
        .padding(12)
        .frame(width: 460, height: 200)
        let window = NSWindow(contentViewController: NSHostingController(rootView: content))
        window.title = "Settings"
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
    }
}

/// Arc's Profiles pane, with the one setting Oa has so far.
struct ProfilesSettingsView: View {
    let engine: any BrowserApplication
    let store: SidebarStore

    var body: some View {
        Form {
            ForEach(store.state.profiles) { profile in
                Section(profile.name) {
                    DownloadLocationPicker(preferences: engine.browserContext(id: profile.id).preferences)
                }
            }
        }
        .formStyle(.grouped)
    }
}

/// Arc's "Download location": the folder, Other… to choose one, and Ask every time, which has the engine show its
/// Save panel for each download. It reads the profile's preferences as the engine reports them, so it waits for the
/// profile to load and follows a change made on Chrome's settings page.
private struct DownloadLocationPicker: View {
    private enum Choice { case folder, other, ask }

    let preferences: any BrowserContextPreferences

    var body: some View {
        Picker("Download location", selection: choice) {
            Text(preferences.downloadDirectory.map { FileManager.default.displayName(atPath: $0.path) } ?? "Downloads")
                .tag(Choice.folder)
            Text("Other…").tag(Choice.other)
            Divider()
            Text("Ask every time").tag(Choice.ask)
        }
        .disabled(preferences.downloadDirectory == nil)
    }

    private var choice: Binding<Choice> {
        Binding {
            preferences.asksWhereToSaveDownloads ? .ask : .folder
        } set: { choice in
            switch choice {
            case .folder: preferences.asksWhereToSaveDownloads = false
            case .ask: preferences.asksWhereToSaveDownloads = true
            case .other: chooseFolder()
            }
        }
    }

    /// After the menu has closed: a panel run from inside its action never becomes key.
    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = preferences.downloadDirectory
        panel.prompt = "Select"
        DispatchQueue.main.async {
            guard let window = NSApplication.shared.keyWindow else { return }
            panel.beginSheetModal(for: window) { response in
                guard response == .OK, let chosen = panel.url else { return }
                preferences.downloadDirectory = chosen
                preferences.asksWhereToSaveDownloads = false
            }
        }
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
