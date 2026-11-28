import SwiftUI

struct DeleteLiveFolderDialog: View {
    let title: String
    let cancel: () -> Void
    let delete: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.theme) private var theme

    var body: some View {
        let dark = colorScheme == .dark
        VStack(alignment: .leading, spacing: 0) {
            FolderIcon(state: .collapsed, customIcon: "github", theme: theme)
                .frame(width: FolderIcon.size.width, height: FolderIcon.size.height)
                .scaleEffect(2.8)
                .frame(width: 62, height: 62)
                .accessibilityHidden(true)
            DialogText(
                title: "Delete your \(title) Live Folder?",
                message: "You can restore this folder at any time by right-clicking the sidebar."
            )
            .padding(.top, 17)
            .padding(.trailing, 10)
            HStack(spacing: 8) {
                Spacer()
                DialogButtonView(
                    title: "Cancel", kind: .cancel,
                    fillColor: dark ? Color(red: 0.19, green: 0.19, blue: 0.37) : nil,
                    borderColor: dark ? Color(red: 0.37, green: 0.36, blue: 0.64) : nil, action: cancel)
                DialogButtonView(
                    title: "Delete Folder", kind: .destructive,
                    fillColor: dark ? Color(red: 0.96, green: 0.23, blue: 0.10) : nil, action: delete)
            }
            .padding(.top, 36)
        }
        .padding(.leading, 38)
        .padding(.trailing, 28)
        .padding(.top, 37)
        .padding(.bottom, 27)
        .frame(width: 450)
        .background(DialogColor.sheet)
    }
}
