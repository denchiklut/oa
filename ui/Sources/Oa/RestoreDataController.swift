import AppKit
import SwiftUI

/// Help ▸ Restore Data…: the dated copies newest first, what the chosen one holds, and Restore after a
/// confirmation. Arc asks nothing; its undo is the copy of the current state the restore keeps.
@MainActor
final class RestoreDataController: NSWindowController {
    private let store: SidebarStore
    private let relaunch: () -> Void

    init(store: SidebarStore, relaunch: @escaping () -> Void) {
        self.store = store
        self.relaunch = relaunch
        let window = NSWindow(
            contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Restore Data"
        window.isReleasedWhenClosed = false
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    /// Reads every copy anew each time, so the list shows the folder as it is.
    func show() {
        guard let window else { return }
        let entries = store.backups.map { backup in
            RestoreDataEntry(backup: backup, state: Result { try store.read(backup) })
        }
        let view = RestoreDataView(entries: entries) { [weak self] in
            self?.confirm($0)
        } cancel: { [weak self] in
            self?.close()
        }
        let wasVisible = window.isVisible
        window.contentViewController = NSHostingController(rootView: view)
        if !wasVisible { window.center() }
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
    }

    private func confirm(_ entry: RestoreDataEntry) {
        guard let restored = try? entry.state.get() else { return }
        let alert = NSAlert()
        alert.messageText = "Restore the sidebar from \(entry.when)?"
        alert.informativeText =
            "Oa quits and comes back with that sidebar, \(restored.summary). Your current sidebar, "
            + "\(store.state.summary), is kept as a backup you can restore the same way."
        alert.addButton(withTitle: "Restore")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            try store.restore(entry.backup)
            relaunch()
        } catch {
            NSAlert(error: error).runModal()
        }
    }
}

struct RestoreDataEntry: Identifiable {
    let backup: SidebarBackup
    let state: Result<SidebarState, Error>

    var id: URL { backup.url }
    var when: String { backup.date.formatted(date: .abbreviated, time: .standard) }

    var label: String {
        switch state {
        case .success(let state): "\(when) · \(state.summary)"
        case .failure: "\(when) · can't be read"
        }
    }
}

private struct RestoreDataView: View {
    let entries: [RestoreDataEntry]
    let restore: (RestoreDataEntry) -> Void
    let cancel: () -> Void
    @State private var selectedID: URL?

    private var selected: RestoreDataEntry? { entries.first { $0.id == selectedID } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Backup:", selection: $selectedID) {
                Text(entries.isEmpty ? "No backups yet" : "Choose a backup").tag(nil as URL?)
                ForEach(entries) { Text($0.label).tag(Optional($0.id)) }
            }
            .disabled(entries.isEmpty)
            if let selected {
                switch selected.state {
                case .success(let state):
                    Text("Backup can be restored").foregroundStyle(.green)
                    ScrollView {
                        Text(preview(of: state))
                            .font(.system(size: 11))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                    }
                    .frame(height: 300)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.04)))
                case .failure:
                    Text("This backup can't be read").foregroundStyle(.red)
                }
            }
            HStack {
                Spacer()
                Button("Cancel", action: cancel).keyboardShortcut(.cancelAction)
                Button("Restore") { if let selected { restore(selected) } }
                    .keyboardShortcut(.defaultAction)
                    .disabled((try? selected?.state.get()) == nil)
            }
        }
        .padding(20)
        .frame(width: 520)
    }

    private func preview(of state: SidebarState) -> String {
        var lines: [String] = []
        for space in state.spaces {
            lines.append(space.name)
            lines += state.tabs(in: space.id, pinned: true).map { "    Pinned Tab: \($0.displayTitle)" }
            lines += state.tabs(in: space.id, pinned: false).map { "    Tab: \($0.displayTitle)" }
            lines.append("")
        }
        lines.append("Archive: \(count(state.archive.count, "tab"))")
        return lines.joined(separator: "\n")
    }
}

func count(_ number: Int, _ noun: String) -> String { "\(number) \(noun)\(number == 1 ? "" : "s")" }

extension SidebarState {
    var summary: String { "\(count(tabCount, "tab")) in \(count(spaces.count, "Space"))" }
}
