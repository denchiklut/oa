import AppKit
import Observation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
@Observable
final class CapturedRegion {
    let original: CGImage
    var annotations: [CaptureAnnotation] = []
    var image: CGImage
    var savedFile: URL?

    init(image: CGImage) { original = image; self.image = image }

    func png(_ replacement: CGImage? = nil) throws -> Data {
        guard let data = NSBitmapImageRep(cgImage: replacement ?? image).representation(using: .png, properties: [:])
        else {
            throw CocoaError(.fileWriteUnknown)
        }
        return data
    }
}

struct CaptureActionMenu: View {
    let result: CapturedRegion
    let model: WindowModel
    let source: URL?
    let pageID: UUID
    let retake: () -> Void
    let edit: () -> Void

    private enum Action: String, CaseIterable {
        case library = "Save to Library", copy = "Copy", save = "Save…", message = "Send via iMessage…"
        case edit = "Edit", retake = "Retake", easel = "New Easel"

        var symbol: String {
            switch self {
            case .library: "circle"
            case .copy: "doc.on.doc"
            case .save: "square.and.arrow.down.fill"
            case .message: "message.fill"
            case .edit: "pencil.and.outline"
            case .retake: "arrow.counterclockwise"
            case .easel: "plus"
            }
        }
    }

    @State private var query = ""
    @State private var hovered: Action?
    @FocusState private var searching: Bool

    private var matches: [Action] {
        Action.allCases.filter { query.isEmpty || $0.rawValue.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(spacing: 4) {
            TextField("Send To…", text: $query)
                .textFieldStyle(.plain)
                .focused($searching)
                .onSubmit { if let action = matches.first { perform(action) } }
                .padding(.horizontal, 9).frame(height: 30)
                .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 6))
                .padding(.bottom, 5)
            ForEach(matches, id: \.self) { action in
                if query.isEmpty && (action == .edit || action == .easel) {
                    Divider().overlay(.white.opacity(0.09))
                }
                Button {
                    perform(action)
                } label: {
                    HStack(spacing: 8) {
                        Image(
                            systemName: action == .library && result.savedFile != nil
                                ? "checkmark.circle.fill" : action.symbol
                        )
                        .foregroundStyle(.white.opacity(0.45)).frame(width: 18)
                        Text(action.rawValue)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 8).frame(height: 33)
                    .background(
                        hovered == action ? Color(red: 0.25, green: 0.24, blue: 0.39) : .clear,
                        in: RoundedRectangle(cornerRadius: 6)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(action == .easel)
                .onHover { inside in
                    if inside { hovered = action } else if hovered == action { hovered = nil }
                }
            }
        }
        .font(.system(size: 14, weight: .medium))
        .padding(10)
        .frame(idealWidth: 270, maxWidth: .infinity, alignment: .leading)
        .background(Color(red: 0.125, green: 0.109, blue: 0.21), in: RoundedRectangle(cornerRadius: 8))
        .environment(\.colorScheme, .dark)
        .onAppear { searching = true }
    }

    private func perform(_ action: Action) {
        do {
            switch action {
            case .library:
                if let file = result.savedFile {
                    try model.captureLibrary.remove(file)
                    result.savedFile = nil
                } else {
                    result.savedFile = try model.captureLibrary.save(result.png(), from: source)
                }
            case .copy: model.copyCapture(try result.png(), for: pageID)
            case .save:
                guard let window = model.window else { return }
                let data = try result.png()
                let panel = NSSavePanel()
                panel.allowedContentTypes = [.png]
                panel.nameFieldStringValue = "Capture.png"
                panel.beginSheetModal(for: window) { response in
                    guard response == .OK, let file = panel.url else { return }
                    do { try data.write(to: file, options: .atomic) } catch { window.presentError(error) }
                }
            case .message:
                let items = [NSImage(cgImage: result.image, size: .zero)]
                guard let service = NSSharingService(named: .composeMessage), service.canPerform(withItems: items)
                else {
                    model.present(.capture("Messages is unavailable"), at: .windowContent(pageID))
                    return
                }
                service.perform(withItems: items)
            case .edit: edit()
            case .retake: retake()
            case .easel: break
            }
        } catch { model.window?.presentError(error) }
    }
}
