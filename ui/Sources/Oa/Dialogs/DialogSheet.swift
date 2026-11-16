import AppKit
import SwiftUI

/// Arc's dialogs: a sheet on a window, drawn by the dialog's own view. Escape and Return reach the cancel and
/// primary buttons.
@MainActor
enum DialogSheet {
    static func present(on parent: NSWindow, @ViewBuilder content: (_ dismiss: @escaping () -> Void) -> some View) {
        let sheet = NSWindow(
            contentRect: .zero, styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        sheet.titlebarAppearsTransparent = true
        sheet.backgroundColor = NSColor(DialogColor.sheet)
        let dismiss = { [weak parent, weak sheet] in
            guard let sheet else { return }
            parent?.endSheet(sheet)
        }
        sheet.contentViewController = NSHostingController(rootView: content(dismiss).ignoresSafeArea())
        parent.beginSheet(sheet)
    }
}

/// Arc's dialog colours as measured in light; the dark ones are Oa's own, Arc's dark dialogs weren't captured.
enum DialogColor {
    static let sheet = dynamic(0xFBFCFF, .windowBackgroundColor)
    static let title = dynamic(0x212429, .labelColor)
    static let body = dynamic(0x565C72, .secondaryLabelColor)
    static let note = dynamic(0x858999, .tertiaryLabelColor)
    static let error = dynamic(0xF14B2D, .systemRed)
    static let field = dynamic(0xFFFFFF, .textBackgroundColor)
    static let fieldBorder = dynamic(0xE4E5EA, .separatorColor)
    static let primary = Color(nsColor: NSColor(hex: 0x4357F4))
    static let destructive = Color(nsColor: NSColor(hex: 0xEA6039))
    static let secondary = dynamic(0xFFFFFF, .controlColor)
    static let secondaryText = dynamic(0x1E1E1E, .labelColor)
    static let secondaryBorder = dynamic(0xDCDCDC, .separatorColor)
    static let hint = dynamic(0xEAEAEA, .quaternaryLabelColor)
    static let hintText = dynamic(0x858585, .secondaryLabelColor)
    /// Arc's `ProfilePicker` chip: measured in light, and in dark the values of its asset catalog.
    static let picker = dynamic(0xEBEDFE, NSColor(srgbRed: 0.192, green: 0.224, blue: 0.984, alpha: 0.898))
    static let pickerText = dynamic(0x505872, NSColor(srgbRed: 0.892, green: 0.885, blue: 0.933, alpha: 1))

    private static func dynamic(_ light: UInt32, _ dark: NSColor) -> Color {
        Color(
            nsColor: NSColor(name: nil) { appearance in
                appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : NSColor(hex: light)
            })
    }
}

extension NSColor {
    fileprivate convenience init(hex: UInt32) {
        self.init(
            srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}
