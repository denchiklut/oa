import SwiftUI

/// As Arc's `LinkRoutingEditor`: edits a copy of the routes, and ✕ or Escape hands it to the client with blank
/// routes dropped. Arc shows one URL per route, though a route can hold several.
struct AirTrafficControlSheet: View {
    let store: SidebarStore
    let profiles: [ProfileState]
    @State private var routing = StorableLinkRoutingState()
    @State private var hasLoadedInitialState = false
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedRule: UUID?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Air Traffic Control").font(.headline)
                Spacer()
                Button("New Route", action: addRule)
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
                        // Arc's empty state wasn't seen; its dialog holds this text, so it is shown here with no routes.
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
                .onChange(of: focusedRule) { _, id in
                    if let id { scroll.scrollTo(id) }
                }
            }
            Divider()
            HStack {
                Text("Default").bold()
                destination($routing.defaultDestination)
                Spacer()
            }
            .padding()
        }
        .frame(width: 508, height: 500)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            guard !hasLoadedInitialState else { return }
            routing = store.linkRouting.state
            hasLoadedInitialState = true
        }
        .onDisappear {
            routing.rules.removeAll { rule in
                rule.sourceComponents.allSatisfy {
                    guard case .urlMatch(_, let pattern) = $0.componentType else { return true }
                    return pattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                }
            }
            store.linkRouting.updateState(routing)
        }
    }

    private func ruleView(_ rule: Binding<LinkMatchingRule>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let component = rule.sourceComponents.first {
                HStack {
                    Label("URL", systemImage: "link")
                    Picker("Match", selection: style(of: component)) {
                        Text("Is equal to").tag(LinkSourceTextMatchingStyle.matches)
                        Text("Contains").tag(LinkSourceTextMatchingStyle.contains)
                    }
                    .labelsHidden()
                    .fixedSize()
                    TextField("example.com", text: pattern(of: component))
                        .accessibilityLabel("URL pattern")
                        .focused($focusedRule, equals: rule.wrappedValue.id)
                    Button {
                        let id = rule.wrappedValue.id
                        routing.rules.removeAll { $0.id == id }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove")
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
        focusedRule = rule.id
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

    /// As Arc's: every Space in sidebar order as "Space (Profile)", then Most Recent Space and Little Arc.
    private func destination(_ selection: Binding<LinkDestination>) -> some View {
        let little = LinkDestination.littleArc(.mostRecent)
        return Menu {
            Picker("Destination", selection: selection) {
                ForEach(store.state.spaces) { space in
                    Text(title(of: space)).tag(LinkDestination.space(.space(space.id)))
                }
                Divider()
                Text("Most Recent Space").tag(LinkDestination.space(.mostRecent))
                // As seen in Arc: no further choice, stored on the most recent Space.
                Text("Little Oa").tag(little)
            }
            .pickerStyle(.inline)
        } label: {
            if case .littleArc = selection.wrappedValue {
                Text("Little Oa")
            } else {
                Text(title(of: selection.wrappedValue.target))
            }
        }
        .frame(width: 200)
    }

    /// Blank for a Space that is gone, as Arc's.
    private func title(of destination: LinkDestination.ProfileDestination) -> String {
        switch destination {
        case .mostRecent, .profile: "Most Recent Space"
        case .space(let id): store.state.space(id).map(title(of:)) ?? ""
        }
    }

    private func title(of space: SidebarSpace) -> String {
        guard let profile = profiles.first(where: { $0.id == space.profileID }) else { return space.name }
        return "\(space.name) (\(profile.name))"
    }
}
