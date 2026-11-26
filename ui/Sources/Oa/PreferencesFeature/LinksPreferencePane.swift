import SwiftUI

struct LinksPreferencePane: View {
    @Bindable var store: SidebarStore
    @Bindable var preferences: PreferencesState
    @AppStorage(LittleBrowserPreferences.globalHotkeyKey) private var globalHotkey = true
    @AppStorage(LittleBrowserPreferences.optionCommandClickKey) private var optionCommandClick = true
    @AppStorage(LittleBrowserPreferences.externalLinksKey) private var externalLinks = true
    @AppStorage(LittleBrowserPreferences.autoArchiveThresholdKey) private var autoArchive =
        AutoArchiveLittleArcThreshold.sixHours

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                LittleOaIllustration()
                VStack(alignment: .leading, spacing: 24) {
                    Text(
                        "Little Oa is a smaller, simpler Oa window. It’s perfect for quick lookups and reading funny tweets your friends send you."
                    )
                    .padding(.horizontal, 10)
                    PreferencesPaneSection {
                        linkSwitch(
                            "Open Little Oa when I press \(littleShortcut) in any app",
                            isOn: $globalHotkey)
                        PreferenceRowDivider()
                        linkSwitch("Open Little Oa when clicking on links with ⌥⌘ held", isOn: $optionCommandClick)
                        PreferenceRowDivider()
                        linkSwitch("Links from other apps open in Little Oa", isOn: $externalLinks)
                        PreferenceRowDivider()
                        PreferenceRow(height: 44) {
                            Text("Archive Little Oas after:")
                        } control: {
                            Picker("Archive Little Oas after", selection: $autoArchive) {
                                ForEach(AutoArchiveLittleArcThreshold.offered) { threshold in
                                    Text(threshold == .sixHours ? "\(threshold.title) (default)" : threshold.title)
                                        .tag(threshold)
                                }
                            }
                            .preferencePopup()
                        }
                    }
                    Divider()
                    Text(
                        "Peek is a way to preview a link without opening a new tab. It’s perfect for quickly looking at a link from an email, news article, or tweet."
                    )
                    .padding(.horizontal, 10)
                    PreferencesPaneSection {
                        linkSwitch(
                            "Open a Peek window when clicking on links with Shift held", isOn: $store.peekOnShiftClick)
                        PreferenceRowDivider()
                        linkSwitch(
                            "Open a Peek window when clicking on links to other sites",
                            note: "Note: This only affects Favorites and Pinned tabs", isOn: $store.peekFromPinnedTabs)
                    }
                    PreferencesPaneSection {
                        PreferenceRow {
                            Text("Choose where links open inside Oa.")
                        } control: {
                            Button("Air Traffic Control…") { preferences.showsAirTrafficControl = true }
                        }
                    }
                }
                .padding(.horizontal, 64)
                .padding(.vertical, 24)
            }
        }
        .sheet(isPresented: $preferences.showsAirTrafficControl) {
            AirTrafficControlSheet(store: store, profiles: preferences.profiles)
        }
    }

    /// As Arc's row, which names the shortcut New Little Arc Window has now.
    private var littleShortcut: String {
        store.keyBindings.state.shortcut(for: LittleBrowserPreferences.shortcutID)?.symbols.joined() ?? "⌥⌘N"
    }

    private func linkSwitch(_ title: String, note: String? = nil, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                if let note { Text(note).italic().foregroundStyle(.secondary) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .toggleStyle(.switch)
        .controlSize(.mini)
        .font(.body)
        .padding(.horizontal, 10)
        .frame(minHeight: note == nil ? 36 : 54)
    }
}

private struct LittleOaIllustration: View {
    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                HStack(spacing: 4) {
                    ForEach(0..<3) { _ in Circle().fill(.black.opacity(0.15)).frame(width: 7, height: 7) }
                    Text("Work").padding(.horizontal, 5).background(.black.opacity(0.06), in: Capsule())
                    Spacer()
                    Text("Open in Work  ⌘O")
                }
                Label("oa", systemImage: "lock.fill")
            }
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background(Color(white: 0.87))
            Color(red: 0.85, green: 0.80, blue: 0.92)
                .overlay {
                    Image(decorative: WindowTexture.image(.grain), scale: 2)
                        .resizable(resizingMode: .tile)
                        .opacity(0.35)
                }
        }
        .font(.system(size: 9, weight: .medium))
        .foregroundStyle(Color(white: 0.28))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .shadow(color: .black.opacity(0.24), radius: 8, y: 3)
        .padding(.horizontal, 60)
        .padding(.top, 47)
        .padding(.bottom, -6)
        .frame(height: 136)
        .background(Color(red: 0.73, green: 0.67, blue: 0.83))
        .clipShape(ScallopedEdge())
        .accessibilityHidden(true)
    }

    private struct ScallopedEdge: Shape {
        func path(in rect: CGRect) -> Path {
            Path { path in
                path.move(to: .zero)
                path.addLine(to: CGPoint(x: 0, y: rect.height - 2))
                for x in stride(from: CGFloat.zero, to: rect.width, by: 17) {
                    path.addQuadCurve(
                        to: CGPoint(x: x + 8.5, y: rect.height - 2),
                        control: CGPoint(x: x + 4.25, y: rect.height - 6))
                    path.addQuadCurve(
                        to: CGPoint(x: x + 17, y: rect.height - 2),
                        control: CGPoint(x: x + 12.75, y: rect.height + 2))
                }
                path.addLine(to: CGPoint(x: rect.width, y: 0))
                path.closeSubpath()
            }
        }
    }
}
