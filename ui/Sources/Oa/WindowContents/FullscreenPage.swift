import AppKit
import DevKit
import SwiftUI

@MainActor
final class FullscreenPage {
    let page: any Page
    private weak var host: PageHostView.Container?
    private let surface = NSView()
    private var hint: NSHostingView<FullscreenExitHint>?
    private var hintTimer: Task<Void, Never>?
    private var origin: String?

    init?(page: any Page, in content: NSView, origin: String) {
        guard let host = page.view.superview as? PageHostView.Container else { return nil }
        self.page = page
        self.host = host
        surface.frame = content.bounds
        surface.autoresizingMask = [.width, .height]
        content.addSubview(surface)
        surface.addSubview(page.view)
        page.view.autoresizingMask = [.width, .height]
        page.view.frame = surface.bounds
        page.activate()
        showHint(for: origin)
    }

    func showHint(for origin: String) {
        guard self.origin != origin else { return }
        self.origin = origin
        hintTimer?.cancel()
        hint?.removeFromSuperview()
        let hint = NSHostingView(rootView: FullscreenExitHint(origin: origin))
        self.hint = hint
        hint.translatesAutoresizingMaskIntoConstraints = false
        surface.addSubview(hint)
        NSLayoutConstraint.activate([
            hint.topAnchor.constraint(equalTo: surface.safeAreaLayoutGuide.topAnchor, constant: 20),
            hint.centerXAnchor.constraint(equalTo: surface.centerXAnchor),
            hint.widthAnchor.constraint(lessThanOrEqualTo: surface.widthAnchor, constant: -40),
        ])
        hintTimer = Task { [weak hint] in
            do { try await Task.sleep(for: .seconds(4)) } catch { return }
            hint?.removeFromSuperview()
        }
    }

    func dismiss(refocus: Bool) {
        hintTimer?.cancel()
        // A tab switch or an expanded Peek can give the view a new host while fullscreen is closing.
        if page.view.superview === surface, let host, host.hosted === page.view {
            host.addSubview(page.view)
            host.fit()
            if refocus { page.activate() }
        }
        surface.removeFromSuperview()
    }
}

private struct FullscreenExitHint: View {
    let origin: String

    var body: some View {
        Text("\(origin) · Press Esc to exit full screen")
            .lineLimit(1)
            .truncationMode(.middle)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(.black.opacity(0.85), in: Capsule())
            .allowsHitTesting(false)
    }
}
