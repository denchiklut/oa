import AppKit
import DevKit
import SwiftUI

/// Arc's Profiles pane, with the settings Oa has so far.
struct ProfilePreferencePane: View {
    let engine: any BrowserApplication
    let store: SidebarStore
    let openWindow: (UUID) -> WindowModel?

    var body: some View {
        Form {
            ForEach(store.state.profiles) { profile in
                Section(profile.name) {
                    let preferences = engine.browserContext(id: profile.id).preferences
                    SearchSettings(
                        preferences: preferences,
                        hasSpace: store.state.spaces.contains { $0.profileID == profile.id }
                    ) { openSearchSettings(in: profile.id) }
                    DownloadLocationPicker(preferences: preferences)
                }
            }
        }
        .formStyle(.grouped)
    }

    /// Arc opens it as a tab of some window; Oa's own: the first window showing a Space of the profile, or a new
    /// window on one when none does, so the page edits that profile's engines. A profile with no Space has no
    /// window to open it in.
    private func openSearchSettings(in profileID: UUID) {
        guard let url = URL(string: "chrome://settings/searchEngines"),
            let window = store.windows.first(where: { $0.space?.profileID == profileID })
                ?? store.state.spaces.first(where: { $0.profileID == profileID }).flatMap({ openWindow($0.id) })
        else { return }
        window.bringToFront()
        window.newTab(url)
    }
}

/// Arc's search settings for a profile: the default engine, Search Settings… for Chromium's page, and whether the
/// engine suggests as you type. They wait for the profile's engines to load.
private struct SearchSettings: View {
    let preferences: any BrowserContextPreferences
    let hasSpace: Bool
    let openSearchSettings: () -> Void

    var body: some View {
        Picker("Search engine", selection: engine) {
            ForEach(preferences.searchEngines) { Text($0.name).tag(Optional($0.keyword)) }
        }
        .disabled(preferences.searchEngines.isEmpty)
        LabeledContent("Manage search") {
            Button("Search Settings…", action: openSearchSettings).disabled(!hasSpace)
        }
        Toggle(
            "Include search engine suggestions",
            isOn: Binding {
                preferences.includesSearchSuggestions
            } set: {
                preferences.includesSearchSuggestions = $0
            })
    }

    private var engine: Binding<String?> {
        Binding {
            preferences.defaultSearchEngine?.keyword
        } set: { keyword in
            if let engine = preferences.searchEngines.first(where: { $0.keyword == keyword }) {
                preferences.setDefaultSearchEngine(engine)
            }
        }
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
