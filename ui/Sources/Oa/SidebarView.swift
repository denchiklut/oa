import SwiftUI

struct SidebarView: View {
    let model: WindowModel

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(spacing: 2) {
                    rows(model.pinnedTabs)
                    if !model.pinnedTabs.isEmpty { Divider().padding(.vertical, 6) }
                    rows(model.unpinnedTabs)
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
            Divider()
            spaces
        }
        .frame(width: 220)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func rows(_ tabs: [SidebarTab]) -> some View {
        ForEach(tabs) { tab in
            TabRow(title: model.title(for: tab), selected: model.selectedTabID == tab.id) {
                model.select(tab.id)
            } close: {
                model.close(tab.id)
            }
        }
    }

    private var spaces: some View {
        HStack(spacing: 4) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(model.state.spaces) { space in
                        SpaceChip(name: space.name, selected: space.id == model.selectedSpaceID) {
                            model.selectSpace(space.id)
                        }
                        .contextMenu {
                            Button("Rename…") {
                                if let name = NamePrompt.run("Rename Space", name: space.name) {
                                    model.renameSpace(space.id, to: name)
                                }
                            }
                            Button("Delete") { model.deleteSpace(space.id) }
                                .disabled(model.state.spaces.count == 1)
                        }
                    }
                }
            }
            Button {
                if let name = NamePrompt.run("New Space") { model.addSpace(named: name) }
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.borderless)
            .help("New Space")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }
}

private struct SpaceChip: View {
    let name: String
    let selected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            Text(name)
                .font(.system(size: 12, weight: selected ? .semibold : .regular))
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(selected ? 0.12 : 0)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct TabRow: View {
    let title: String
    let selected: Bool
    let select: () -> Void
    let close: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
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
