import SwiftUI

struct SidebarView: View {
    let model: WindowModel

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(model.tabs) { tab in
                        TabRow(tab: tab, selected: model.selectedTab === tab) {
                            model.select(tab)
                        } close: {
                            model.close(tab)
                        }
                    }
                }
                .padding(8)
            }
            Divider()
            Button {
                model.newTab()
            } label: {
                Label("New Tab", systemImage: "plus")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .frame(width: 220)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct TabRow: View {
    let tab: Tab
    let selected: Bool
    let select: () -> Void
    let close: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 6) {
            Text(tab.title)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
            if hovering || selected {
                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.primary.opacity(selected ? 0.12 : hovering ? 0.06 : 0))
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: select)
        .onHover { hovering = $0 }
    }
}
