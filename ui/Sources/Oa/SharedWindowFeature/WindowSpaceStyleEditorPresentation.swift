import SwiftUI

/// Arc's `WindowSpaceStyleEditorPresentation`: the theme editor a window has open on one of its Spaces, which the
/// window draws that Space in until it closes.
struct WindowSpaceStyleEditorPresentation: Equatable {
    enum Origin { case sidebar, library }

    let spaceID: UUID
    let origin: Origin
    var editor: SpaceStyleEditor
}

struct WindowSpaceStyleEditorView: View {
    let model: WindowModel

    var body: some View {
        if let editor = model.spaceStyleEditor?.editor {
            SpaceStyleEditorView(
                editor: editor,
                presetPage: Binding {
                    model.spaceStyleEditorPresetPage
                } set: {
                    model.spaceStyleEditorPresetPage = $0
                },
                update: { model.updateSpaceStyleEditor($0) })
        }
    }
}
