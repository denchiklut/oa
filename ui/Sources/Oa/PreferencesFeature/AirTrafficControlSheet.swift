import SwiftUI

/// As Arc's `LinkRoutingEditor`: edits a copy of the routes and hands it to the client when the dialog closes.
struct AirTrafficControlSheet: View {
    let store: SidebarStore
    let profiles: [ProfileState]
    @State private var routing = StorableLinkRoutingState()
    @State private var hasLoadedInitialState = false
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedComponent: UUID?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Air Traffic Control").font(.headline)
                Spacer()
                Button("New Route", action: addRule)
            }
            .padding()
            Divider()
            ScrollViewReader { scroll in
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if routing.rules.isEmpty {
                            Text(
                                "Routes let you choose where specific sites open inside Oa. For example, you can route Spotify links to always open inside your Personal space."
                            )
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 80)
                        }
                        ForEach($routing.rules) { $rule in
                            ruleView($rule).id(rule.id)
                        }
                    }
                    .padding(24)
                }
                .onChange(of: focusedComponent) { _, id in
                    if let id { withAnimation { scroll.scrollTo(id) } }
                }
            }
            Divider()
            HStack {
                Text("Default").bold()
                destination($routing.defaultDestination)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 506, height: 450)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            guard !hasLoadedInitialState else { return }
            routing = store.linkRouting.state
            hasLoadedInitialState = true
        }
        .onDisappear { store.linkRouting.updateState(routing) }
    }

    private func ruleView(_ rule: Binding<LinkMatchingRule>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(rule.sourceComponents) { $component in
                HStack {
                    Label("URL", systemImage: "link")
                    Picker("Match", selection: style(of: $component)) {
                        Text("Is equal to").tag(LinkSourceTextMatchingStyle.matches)
                        Text("Contains").tag(LinkSourceTextMatchingStyle.contains)
                    }
                    .labelsHidden()
                    .fixedSize()
                    TextField("example.com", text: pattern(of: $component))
                        .accessibilityLabel("URL pattern")
                        .focused($focusedComponent, equals: component.id)
                    Button {
                        let id = component.id
                        rule.wrappedValue.sourceComponents.removeAll { $0.id == id }
                        if rule.wrappedValue.sourceComponents.isEmpty {
                            routing.rules.removeAll { $0.id == rule.wrappedValue.id }
                        }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove")
                    if component.id == rule.wrappedValue.sourceComponents.last?.id {
                        Button {
                            let component = LinkSourceComponent()
                            rule.wrappedValue.sourceComponents.append(component)
                            focusedComponent = component.id
                        } label: {
                            Image(systemName: "plus.circle.fill")
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Add URL")
                    }
                }
            }
            HStack {
                Label("Open in", systemImage: "arrow.turn.down.right")
                destination(rule.destination)
            }
        }
    }

    private func addRule() {
        let rule = LinkMatchingRule()
        routing.rules.append(rule)
        focusedComponent = rule.sourceComponents.first?.id
    }

    private func style(of component: Binding<LinkSourceComponent>) -> Binding<LinkSourceTextMatchingStyle> {
        Binding {
            guard case .urlMatch(let style, _) = component.wrappedValue.componentType else { return .contains }
            return style
        } set: { style in
            guard case .urlMatch(_, let pattern) = component.wrappedValue.componentType else { return }
            component.wrappedValue.componentType = .urlMatch(style, pattern)
        }
    }

    private func pattern(of component: Binding<LinkSourceComponent>) -> Binding<String> {
        Binding {
            guard case .urlMatch(_, let pattern) = component.wrappedValue.componentType else { return "" }
            return pattern
        } set: { pattern in
            guard case .urlMatch(let style, _) = component.wrappedValue.componentType else { return }
            component.wrappedValue.componentType = .urlMatch(style, pattern)
        }
    }

    private func destination(_ selection: Binding<LinkDestination>) -> some View {
        let target = Binding {
            selection.wrappedValue.target
        } set: {
            selection.wrappedValue = .space($0)
        }
        return Menu {
            Picker("Destination", selection: target) {
                Text("Most Recent Space").tag(LinkDestination.ProfileDestination.mostRecent)
                ForEach(store.state.spaces) { space in
                    Text(title(of: space)).tag(LinkDestination.ProfileDestination.space(space.id))
                }
                if profiles.count > 1 {
                    ForEach(profiles) { profile in
                        Text(profile.name).tag(LinkDestination.ProfileDestination.profile(profile.id))
                    }
                }
            }
            .pickerStyle(.inline)
            Divider()
            Button("Little Oa") {}.disabled(true)
        } label: {
            Text(title(of: selection.wrappedValue.target))
        }
        .frame(width: 200)
    }

    private func title(of destination: LinkDestination.ProfileDestination) -> String {
        switch destination {
        case .mostRecent: "Most Recent Space"
        case .space(let id): store.state.space(id).map(title(of:)) ?? "Most Recent Space"
        case .profile(let id): profiles.first { $0.id == id }?.name ?? "Most Recent Space"
        }
    }

    private func title(of space: SidebarSpace) -> String {
        guard profiles.count > 1, let profile = profiles.first(where: { $0.id == space.profileID }) else {
            return space.name
        }
        return "\(space.name) (\(profile.name))"
    }
}
