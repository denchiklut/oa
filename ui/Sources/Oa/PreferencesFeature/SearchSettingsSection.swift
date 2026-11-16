import DevKit
import SwiftUI

/// Arc's search settings for a profile: the default engine, Search Settings… for Chromium's page, and whether the
/// engine suggests as you type. They wait for the profile's engines to load.
struct SearchSettingsSection: View {
    let preferences: any BrowserContextPreferences
    let hasSpace: Bool
    let openSearchSettings: () -> Void

    var body: some View {
        PreferencesPaneSection {
            PreferenceRow {
                Text("Search engine")
            } control: {
                Picker("Search engine", selection: engine) {
                    ForEach(preferences.searchEngines) { Text($0.name).tag(Optional($0.keyword)) }
                }
                .preferencePopup()
                .disabled(preferences.searchEngines.isEmpty)
            }
            PreferenceRowDivider()
            PreferenceRow {
                Text("Manage search")
            } control: {
                Button("Search Settings…", action: openSearchSettings).disabled(!hasSpace)
            }
            PreferenceRowDivider()
            PreferenceRow {
                Text("Include search engine suggestions")
            } control: {
                Toggle(
                    "Include search engine suggestions",
                    isOn: Binding {
                        preferences.includesSearchSuggestions
                    } set: {
                        preferences.includesSearchSuggestions = $0
                    }
                )
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
            }
        }
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
