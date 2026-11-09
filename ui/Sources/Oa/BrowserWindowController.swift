import AppKit
import DevKit
import SwiftUI

@MainActor
final class BrowserWindowController: NSWindowController, NSWindowDelegate, NSMenuItemValidation {
    let id = UUID()
    private let engine: any BrowserApplication
    private let model: WindowModel
    private let didClose: (BrowserWindowController) -> Void
    private var titleObservation: Task<Void, Never>?

    init(
        engine: any BrowserApplication, context: any BrowserContext,
        didClose: @escaping (BrowserWindowController) -> Void
    ) {
        self.engine = engine
        self.didClose = didClose
        model = WindowModel(windowID: id, context: context)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.contentMinSize = NSSize(width: 480, height: 320)
        super.init(window: window)
        let content = NSHostingController(rootView: BrowserWindowView(model: model))
        content.sizingOptions = []
        window.contentViewController = content
        window.setContentSize(NSSize(width: 1100, height: 760))
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func open(cascadingFrom previous: NSWindow?) {
        guard let window else { return }
        engine.attachWindow(window, id: id)
        model.openPage(URL(string: "https://www.wikipedia.org/")!)
        if let previous {
            window.setFrameTopLeftPoint(
                window.cascadeTopLeft(from: NSPoint(x: previous.frame.minX, y: previous.frame.maxY)))
        } else {
            window.center()
        }
        window.makeKeyAndOrderFront(nil)
        observeTitle()
    }

    func closePage() {
        model.closePage()
    }

    private func observeTitle() {
        let title = withObservationTracking {
            model.page?.title ?? ""
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeTitle() }
        }
        window?.title = title.isEmpty ? "Oa" : title
    }

    func windowDidBecomeKey(_ notification: Notification) {
        model.page?.activate()
    }

    func windowWillClose(_ notification: Notification) {
        titleObservation?.cancel()
        model.dropPage()
        engine.closeWindow(id: id)
        didClose(self)
    }

    @objc func goBack(_ sender: Any?) { model.page?.goBack() }
    @objc func goForward(_ sender: Any?) { model.page?.goForward() }
    @objc func reload(_ sender: Any?) { model.page?.reload() }
    @objc func stopLoading(_ sender: Any?) { model.page?.stopLoading() }
    @objc func openLocation(_ sender: Any?) { model.focusAddressField += 1 }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(goBack(_:)): model.page?.canGoBack ?? false
        case #selector(goForward(_:)): model.page?.canGoForward ?? false
        case #selector(stopLoading(_:)): model.page?.isLoading ?? false
        default: true
        }
    }
}
