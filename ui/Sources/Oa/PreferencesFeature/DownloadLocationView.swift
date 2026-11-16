import AppKit
import DevKit
import SwiftUI

/// Arc's "Download location": the folder, Other… to choose one, and Ask every time, which has the engine show its
/// Save panel for each download. It reads the profile's preferences as the engine reports them, so it waits for the
/// profile to load and follows a change made on Chrome's settings page.
struct DownloadLocationView: View {
    private enum Choice { case folder, other, ask }

    let preferences: any BrowserContextPreferences

    var body: some View {
        PreferenceRow(height: 45) {
            Text("Download location")
        } control: {
            Picker("Download location", selection: choice) {
                Text(
                    preferences.downloadDirectory.map { FileManager.default.displayName(atPath: $0.path) }
                        ?? "Downloads"
                )
                .tag(Choice.folder)
                Text("Other…").tag(Choice.other)
                Divider()
                Text("Ask every time").tag(Choice.ask)
            }
            .preferencePopup()
            .disabled(preferences.downloadDirectory == nil)
        }
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
