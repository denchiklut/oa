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
        .background(Color(nsColor: .windowBackgroundColor))
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
    let page: any Page

    var body: some View {
        if page.crash != nil {
            CrashedPageView(page: page)
        } else {
            PageHostView(view: page.view)
        }
    }
}
