import DevKit
import SwiftUI

/// In place of the engine's view while the page's renderer is gone, as Arc draws its own; the words are Oa's own.
struct CrashedPageView: View {
    let page: any Page

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.secondary)
            Text(message)
                .font(.system(size: 15, weight: .medium))
            Button("Reload") { page.reload() }
                .keyboardShortcut(.defaultAction)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // As Arc: white in either appearance. Its words stay light-appearance grey, Oa's own: Arc's turn white in a
        // dark window and vanish.
        .background(.white)
        .environment(\.colorScheme, .light)
    }

    private var message: String {
        switch page.crash {
        case .outOfMemory: "This page ran out of memory"
        case .killed: "This page was closed by the system"
        default: "This page crashed"
        }
    }
}

struct PageContentView: View {
    let model: WindowModel
    let page: any Page
    var movedToWindow: () -> Void = {}

    var body: some View {
        WebContentSplitView(page: page) {
            if page.crash != nil {
                CrashedPageView(page: page)
            } else {
                PageHostView(view: page.view, movedToWindow: movedToWindow)
                    .overlay(alignment: .bottomLeading) {
                        if let link = page.hoveredLink {
                            LinkPreview(url: link, allowsPeek: model.canShiftClickToPeek(link, from: page.id))
                        }
                    }
            }
        }
    }
}

extension View {
    /// As Arc's card: a layer of the page's root background colour under it, none until the page reports one.
    func pageRootBackground(_ page: any Page) -> some View {
        background {
            if let color = page.rootBackgroundColor { Color(nsColor: color) }
        }
    }
}
