import SwiftUI

struct AirTrafficControlSheet: View {
    @Bindable var store: SidebarStore
    let profiles: [ProfileState]
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedRoute: UUID?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Air Traffic Control").font(.headline)
                Spacer()
                Button("New Route") {
                    let route = LinkRouting.Route()
                    store.linkRouting.routes.append(route)
                    focusedRoute = route.id
                }
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                }
                .accessibilityLabel("Close")
                .keyboardShortcut(.cancelAction)
            }
            .padding()
            Divider()
            ScrollViewReader { scroll in
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if store.linkRouting.routes.isEmpty {
                            Text(
                                "Routes let you choose where specific sites open inside Oa. For example, you can route Spotify links to always open inside your Personal space."
                            )
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.top, 80)
                        }
                        ForEach($store.linkRouting.routes) { $route in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Label("URL", systemImage: "link")
                                    Picker("Match", selection: $route.match) {
                                        ForEach(LinkRouting.Route.Match.allCases, id: \.self) {
                                            Text($0.rawValue).tag($0)
                                        }
                                    }
                                    .labelsHidden()
                                    .fixedSize()
                                    TextField("example.com", text: $route.pattern)
                                        .accessibilityLabel("URL pattern")
                                        .focused($focusedRoute, equals: route.id)
                                    Button {
                                        let id = route.id
                                        store.linkRouting.routes.removeAll { $0.id == id }
                                    } label: {
                                        Image(systemName: "minus.circle")
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("Remove Route")
                                }
                                HStack {
                                    Label("Open in", systemImage: "arrow.turn.down.right")
                                    destination($route.spaceID)
                                }
                            }.id(route.id)
                        }
                    }
                    .padding(24)
                }
                .onChange(of: focusedRoute) { _, id in
                    if let id { scroll.scrollTo(id) }
                }
            }
            Divider()
            HStack {
                Text("Default").bold()
                destination($store.linkRouting.defaultSpaceID)
                Spacer()
            }.padding()
        }
        .frame(width: 506, height: 450)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func destination(_ selection: Binding<UUID?>) -> some View {
        Menu {
            Picker("Destination", selection: selection) {
                Text("Most Recent Space").tag(UUID?.none)
                ForEach(store.state.spaces) { space in
                    Text(title(of: space)).tag(Optional(space.id))
                }
            }
            .pickerStyle(.inline)
            Divider()
            Button("Little Oa") {}.disabled(true)
        } label: {
            Text(selection.wrappedValue.flatMap { store.state.space($0) }.map(title(of:)) ?? "Most Recent Space")
        }
        .frame(width: 200)
    }

    private func title(of space: SidebarSpace) -> String {
        guard let profile = profiles.first(where: { $0.id == space.profileID }) else { return space.name }
        return "\(space.name) (\(profile.name))"
    }
}
