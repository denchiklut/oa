import SwiftUI

/// As Arc's Advanced pane, with only the rows whose feature Oa has, each in Arc's section and order.
struct AdvancedPreferencePane: View {
    let openMoreSettings: () -> Void
    @AppStorage(TabReorderingHaptics.key) private var hapticsDisabled = false
    @AppStorage(RestoreWindowsPreference.key) private var restoresWindows = true
    @AppStorage(WindowContentGrabber.key) private var contentWindowDragging = true
    @AppStorage(ToolbarAddressLabel.fullURLPreferenceKey) private var showsFullURL = false
    @AppStorage(AutomaticPictureInPicture.key) private var autoPipDisabled = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                section {
                    row(
                        "Haptic feedback when reordering tabs", symbol: "hand.tap.fill", tile: .blue,
                        isOn: inverted($hapticsDisabled))
                }
                section {
                    row(
                        "When opening Oa, restore windows from previous session", symbol: "macwindow", tile: .green,
                        isOn: $restoresWindows
                    )
                    .accessibilityIdentifier("restoreWindowsPreference")
                    Divider()
                    row(
                        "Allow window dragging from the top of webpages", symbol: "rectangle.topthird.inset.filled",
                        tile: .green, isOn: $contentWindowDragging)
                    Divider()
                    row(
                        "Show full URL when Toolbar is enabled", symbol: "ellipsis.rectangle", tile: .red,
                        isOn: $showsFullURL)
                }
                section {
                    row(
                        "Enable Picture in Picture when you leave a video tab", symbol: "play.square", tile: .purple,
                        isOn: inverted($autoPipDisabled))
                }
                Button("More Settings…", action: openMoreSettings)
            }
            .padding(.horizontal, 64)
            .padding(.vertical, 20)
        }
    }

    private func section(@ViewBuilder rows: () -> some View) -> some View {
        PreferencesPaneSection(fill: Color(nsColor: .quinaryLabelColor).opacity(0.3)) {
            rows().padding(.horizontal, 10)
        }
    }

    private func row(_ title: String, symbol: String, tile: Color, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            HStack {
                Image(systemName: symbol)
                    .font(.system(size: 11))
                    .frame(width: 20, height: 20)
                    .foregroundStyle(.white)
                    .background(RoundedRectangle(cornerRadius: 4).fill(tile))
                Text(title).font(.system(size: 13)).opacity(0.85)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .toggleStyle(.switch)
        .controlSize(.mini)
        .padding(.vertical, 10)
    }

    /// Arc stores these switches as `…Disabled`, written false when turned on.
    private func inverted(_ disabled: Binding<Bool>) -> Binding<Bool> {
        Binding {
            !disabled.wrappedValue
        } set: {
            disabled.wrappedValue = !$0
        }
    }
}
