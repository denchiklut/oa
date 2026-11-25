import AppKit
import Observation
import SwiftUI

/// Stands for the engine's frontend: its panels, its ⋮ ▸ Dock side and its close button.
@MainActor
@Observable
final class StubPageDevTools: PageDevTools {
    /// The frontend's Dock side, which the engine keeps per profile; the stub keeps one.
    private static var dockSide = DevToolsDisplay.right

    /// As the engine's `can_dock`, decided as the frontend opens: a popup browser's doesn't dock.
    @ObservationIgnored var canDock: () -> Bool = { true }
    fileprivate var docks = true

    private(set) var display: DevToolsDisplay?
    fileprivate(set) var panel = "elements"
    fileprivate(set) var isInspecting = false
    @ObservationIgnored private lazy var hostingView: NSView = NSHostingView(rootView: StubDevToolsView(devTools: self))

    var view: NSView? { display == nil ? nil : hostingView }

    func setOpen(_ open: Bool) { open ? show("elements") : close() }

    func inspect() {
        show("elements")
        isInspecting = true
    }

    func toggleConsole() { toggle("console") }
    func toggleNetwork() { toggle("network") }

    func focus() { hostingView.window?.makeFirstResponder(hostingView) }

    fileprivate func dock(_ side: DevToolsDisplay) {
        Self.dockSide = side
        display = side
    }

    fileprivate func close() {
        display = nil
        isInspecting = false
    }

    fileprivate func show(_ panel: String) {
        self.panel = panel
        guard display == nil else { return }
        docks = canDock()
        display = docks ? Self.dockSide : .undocked
    }

    private func toggle(_ panel: String) {
        display != nil && self.panel == panel ? close() : show(panel)
    }
}

private struct StubDevToolsView: View {
    weak var devTools: StubPageDevTools?

    var body: some View {
        if let devTools {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 12) {
                    Image(systemName: "cursorarrow.rays")
                        .foregroundStyle(devTools.isInspecting ? Color.accentColor : .secondary)
                    ForEach(["elements", "console", "network"], id: \.self) { panel in
                        Button(panel.capitalized) { devTools.show(panel) }
                            .buttonStyle(.plain)
                            .fontWeight(devTools.panel == panel ? .semibold : .regular)
                            .fixedSize()
                    }
                    Spacer()
                    // As the frontend's: no Dock side and no close button when it can't dock.
                    if devTools.docks {
                        Button("Undock into separate window", systemImage: "macwindow") { devTools.dock(.undocked) }
                        Button("Dock to left", systemImage: "rectangle.lefthalf.filled") { devTools.dock(.left) }
                        Button("Dock to bottom", systemImage: "rectangle.bottomhalf.filled") { devTools.dock(.bottom) }
                        Button("Dock to right", systemImage: "rectangle.righthalf.filled") { devTools.dock(.right) }
                        Button("Close DevTools", systemImage: "xmark") { devTools.close() }
                    }
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .padding(8)
                Divider()
                Text("Stub DevTools: \(devTools.panel)")
                    .foregroundStyle(.secondary)
                    .padding(8)
                Spacer()
            }
            .font(.system(size: 11))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .textBackgroundColor))
        }
    }
}
