import SwiftUI

/// Arc's `PreviewSettingsDialog`, presented from Settings ▸ General ▸ Previews Settings….
struct PreviewSettingsDialog: View {
    @Bindable var settings: PreviewSettings
    let done: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Show Oa Previews:")
                    .font(.system(size: 13, weight: .semibold))
                Text(
                    "Save a click! Hover your mouse over a Folder, Pinned, or Favorited tab to quickly preview what you need from that site."
                )
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 10) {
                Toggle("Oa Folders", isOn: $settings.folderEnabled)
                Toggle("Google Calendar", isOn: $settings.calendarEnabled)
                Toggle("Google Mail", isOn: $settings.gmailEnabled)
                Toggle("Recent pages on Linear, Notion, and Figma", isOn: $settings.recentPagesEnabled)
                Toggle("Notion Calendar", isOn: $settings.notionCalendarEnabled)
            }
            .toggleStyle(.checkbox)
            .font(.system(size: 13))
            HStack {
                Spacer()
                Button("Done", action: done)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 4)
        }
        .padding(20)
        .frame(width: 390)
    }
}
