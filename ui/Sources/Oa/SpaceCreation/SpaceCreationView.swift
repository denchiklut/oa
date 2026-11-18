import SwiftUI

struct SpaceCreationView: View {
    let model: WindowModel
    let creation: SpaceCreationState
    @State private var pickingIcon = false
    @FocusState private var nameFocused: Bool
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            SpaceCreationArtwork()
                .padding(.top, 12)
            Text("Create a Space")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(theme.foreground)
                .padding(.top, 10)
            Text("Separate your tabs for life, work, projects, and more.")
                .font(.system(size: 13))
                .foregroundStyle(theme.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
                .padding(.top, 4)
            VStack(spacing: 6) {
                card {
                    Button {
                        pickingIcon = true
                    } label: {
                        icon {
                            if let glyph = creation.icon {
                                SpaceIconGlyph(icon: glyph)
                            } else {
                                Image(systemName: "plus.square")
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .help("Choose an icon")
                    .popover(isPresented: $pickingIcon, arrowEdge: .bottom) {
                        SpaceIconPicker(selection: creation.icon) { icon in
                            model.updateSpaceCreation { $0.icon = icon }
                            pickingIcon = false
                        }
                    }
                    TextField("Space name…", text: title)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(theme.foreground)
                        .focused($nameFocused)
                        .onSubmit { model.triggerSpaceCreation() }
                }
                card {
                    icon { Image(systemName: "face.smiling.fill") }
                    Text("Profile")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(theme.foreground)
                    profilePicker
                    Spacer(minLength: 0)
                    Image(systemName: "info.circle")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(theme.foreground.opacity(0.8))
                        .help("Spaces in the same Profile share history, logins, and extensions.")
                }
                card {
                    icon { Image(systemName: "paintbrush.pointed") }
                    Text("Choose a Theme")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(theme.foreground)
                    Spacer(minLength: 0)
                }
            }
            .padding(.top, 20)
            Spacer(minLength: 16)
            Button {
                model.triggerSpaceCreation()
            } label: {
                Text("Create Space")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(creation.canCreate ? 1 : 0.35))
                    .frame(maxWidth: .infinity)
                    .frame(height: 30)
                    .background(
                        creation.canCreate ? Self.enabledColor : Self.disabledColor,
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!creation.canCreate)
            Button("Cancel") { model.cancelSpaceCreation() }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(theme.secondaryText)
                .keyboardShortcut(.cancelAction)
                .padding(.top, 8)
                .padding(.bottom, 8)
        }
        // As measured on Arc: the rows are 4 pt from the sidebar's leading edge and 8 pt from its trailing one.
        .padding(.leading, 4)
        .padding(.trailing, 8)
        .opacity(creation.phase == .editing ? 1 : 0)
        .animation(.easeOut(duration: 0.2), value: creation.phase)
        .allowsHitTesting(creation.phase == .editing)
        .onAppear { nameFocused = true }
    }

    /// Arc's Create Space button, as measured: #2E2DB1, and #29235D while disabled.
    private static let enabledColor = Color(red: 0x2E / 255, green: 0x2D / 255, blue: 0xB1 / 255)
    private static let disabledColor = Color(red: 0x29 / 255, green: 0x23 / 255, blue: 0x5D / 255)

    private var title: Binding<String> {
        Binding {
            creation.title
        } set: { title in
            model.updateSpaceCreation { $0.title = title }
        }
    }

    private var profilePicker: some View {
        Menu {
            ForEach(model.profiles) { profile in
                Toggle(
                    profile.name,
                    isOn: Binding {
                        profile.id == creation.profileID
                    } set: { _ in
                        model.updateSpaceCreation { $0.profileID = profile.id }
                    })
            }
            Divider()
            Button("New Profile…") { ProfileDialogUtils.createProfileForSpaceCreation(in: model) }
        } label: {
            HStack(spacing: 3) {
                Text(model.profileName(creation.profileID)).lineLimit(1).truncationMode(.tail)
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(theme.foreground)
            .padding(.horizontal, 7)
            .frame(height: 18)
            .background(theme.foreground.opacity(0.09), in: Capsule())
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .fixedSize()
    }

    private func icon(@ViewBuilder _ image: () -> some View) -> some View {
        image()
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(theme.foreground.opacity(0.6))
            .frame(width: 18)
    }

    private func card(@ViewBuilder content: () -> some View) -> some View {
        HStack(spacing: 8) { content() }
            .padding(.horizontal, 8)
            .frame(height: 30)
            .background(theme.foreground.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct SpaceCreationArtwork: View {
    var body: some View {
        ZStack {
            card(symbol: "leaf.fill", color: .green).rotationEffect(.degrees(-12)).offset(x: -14, y: 2)
            card(symbol: "basket.fill", color: .orange).rotationEffect(.degrees(12)).offset(x: 14, y: 2)
            card(symbol: "laptopcomputer", color: .blue)
        }
        .frame(height: 40)
        .accessibilityHidden(true)
    }

    private func card(symbol: String, color: Color) -> some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(.white)
            .frame(width: 29, height: 36)
            .overlay(Image(systemName: symbol).font(.system(size: 13)).foregroundStyle(color))
            .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
    }
}
