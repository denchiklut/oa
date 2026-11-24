import AppKit
import DevKit
import Observation

@MainActor
@Observable
final class ChromiumPageDevTools: NSObject, PageDevTools, CorePageDevToolsDelegate {
    private(set) var display: DevToolsDisplay?
    @ObservationIgnored private let core: CorePageDevTools

    var view: NSView? { display == nil ? nil : core.view }

    init(core: CorePageDevTools) {
        self.core = core
        super.init()
        core.delegate = self
    }

    func setOpen(_ open: Bool) { open ? core.open() : core.close() }

    func inspect() { core.openInspectView() }

    func toggleConsole() { toggle(panel: "console", open: core.openConsoleView) }

    func toggleNetwork() { toggle(panel: "network", open: core.openNetworkView) }

    func focus() { core.focus() }

    /// As ADK's console and network closures: the current panel decides, once the frontend answers.
    private func toggle(panel: String, open: @escaping () -> Void) {
        guard display != nil else { return open() }
        core.currentPanel { [core] current in
            MainActor.assumeIsolated { current == panel ? core.close() : open() }
        }
    }

    func devTools(_ devTools: CorePageDevTools, displayAs display: Int) {
        let display: DevToolsDisplay =
            switch display {
            case 0: .undocked
            case 1: .left
            case 3: .bottom
            default: .right
            }
        if display != self.display { self.display = display }
    }

    func devToolsDidClose(_ devTools: CorePageDevTools) { display = nil }
}
