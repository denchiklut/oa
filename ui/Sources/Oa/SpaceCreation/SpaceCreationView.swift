import SwiftUI

/// Arc's `SpaceCreationView`, as measured on Arc: 36 pt cards 14 pt in from the sidebar's edges and 8 pt apart, the
/// name field lighter than the other two, Create Space and Cancel at the bottom. After Create Space it plays Arc's
/// splash: the form fades, the header artwork drops, doubles and flips into a 🙌 card, a glow pulses, the card fades,
/// and the Space is made, 2.18 s after the click.
struct SpaceCreationView: View {
    /// Where the header artwork rests, as measured on Arc, and its height.
    private static let artworkTop: CGFloat = 36
    private static let artworkHeight: CGFloat = 40

    let model: WindowModel
    let creation: SpaceCreationState
    @State private var pickingIcon = false
    @State private var lifted = false
    @State private var glowing = false
    @State private var cardFaded = false
    @FocusState private var nameFocused: Bool
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let editing = creation.phase == .editing
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // As measured on Arc: the card ends centred across the sidebar, 12 pt below the panel's middle.
                let rest = Self.artworkTop + Self.artworkHeight / 2
                SpaceCreationArtwork(flip: lifted ? 1 : 0, glowing: glowing)
                    .frame(height: Self.artworkHeight)
                    .scaleEffect(lifted ? 2 : 1)
                    .offset(y: lifted ? geometry.size.height / 2 + 12 - rest : 0)
                    .opacity(cardFaded ? 0 : 1)
                    .zIndex(1)
                    .padding(.top, Self.artworkTop)
                form
                    .opacity(editing ? 1 : 0)
                    .animation(.easeInOut(duration: 0.25).delay(0.05), value: editing)
            }
        }
        .padding(.horizontal, 14)
        .allowsHitTesting(editing)
        .onAppear { nameFocused = true }
        // As measured on Arc, from the click: the artwork moves from 0.3 s, the glow at 1.33 s, the card fades from
        // 1.775 s, and the Space is made at 2.18 s.
        .task(id: editing) {
            guard !editing else { return }
            let clicked = ContinuousClock.now
            withAnimation(.spring(response: 0.8, dampingFraction: 1).delay(0.3)) { lifted = true }
            try? await Task.sleep(until: clicked + .milliseconds(1330))
            glowing = true
            try? await Task.sleep(until: clicked + .milliseconds(1775))
            withAnimation(.easeInOut(duration: 0.4)) { cardFaded = true }
            try? await Task.sleep(until: clicked + .milliseconds(2180))
            model.completeSpaceCreation()
        }
    }

    private var form: some View {
        VStack(spacing: 0) {
            Text("Create a Space")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(theme.foreground)
                .padding(.top, 18)
            Text("Separate your tabs for life, work, projects, and more.")
                .font(.system(size: 13))
                .lineSpacing(1.5)
                .foregroundStyle(theme.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.top, 11)
            VStack(spacing: 8) {
                card(fill: colorScheme == .dark ? .white.opacity(0.08) : .white.opacity(0.55)) {
                    Button {
                        pickingIcon = true
                    } label: {
                        icon {
                            if let glyph = creation.icon {
                                SpaceIconGlyph(icon: glyph)
                            } else {
                                Image(systemName: "plus.square.dashed")
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $pickingIcon, arrowEdge: .bottom) {
                        SpaceIconPicker(selection: creation.icon) { icon in
                            model.updateSpaceCreation { $0.icon = icon }
                            pickingIcon = false
                        }
                    }
                    TextField("Space name…", text: title)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(theme.foreground)
                        .focused($nameFocused)
                }
                card {
                    icon { Image(systemName: "face.smiling") }
                    Text("Profile")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(theme.foreground)
                        .fixedSize()
                    profilePicker.layoutPriority(1)
                    Spacer(minLength: 0)
                    Image(systemName: "info.circle")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(theme.foreground.opacity(0.8))
                        .help("You can use a Profile to give this Space its own logins, history, and browsing data.")
                }
                card {
                    icon { Image(systemName: "paintbrush.pointed.fill") }
                    Text("Choose a Theme")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(theme.foreground)
                    Spacer(minLength: 0)
                }
            }
            .padding(.top, 31)
            Spacer(minLength: 16)
            Button {
                model.triggerSpaceCreation()
            } label: {
                Text("Create Space")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(creation.canCreate ? 1 : 0.35))
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                    .background(
                        Self.createColor.opacity(creation.canCreate ? 1 : 0.4),
                        in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!creation.canCreate)
            Button("Cancel") { model.cancelSpaceCreation() }
                .buttonStyle(.plain)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(theme.foreground.opacity(0.6))
                .padding(.top, 14)
                .padding(.bottom, 16)
        }
    }

    /// Arc's Create Space blue, as measured: #1F2AFF, at 0.4 while disabled.
    private static let createColor = Color(red: 0x1F / 255, green: 0x2A / 255, blue: 1)

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
            HStack(spacing: 4) {
                Text(model.profileName(creation.profileID)).lineLimit(1).truncationMode(.tail)
                Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold))
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(theme.foreground)
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(theme.foreground.opacity(0.09), in: Capsule())
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func icon(@ViewBuilder _ image: () -> some View) -> some View {
        image()
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(theme.foreground.opacity(0.6))
            .frame(width: 20)
    }

    /// As measured on Arc: the cards are the theme's ink at about 4.5 % in light and white at about 11 % in dark.
    private func card(fill: Color? = nil, @ViewBuilder content: () -> some View) -> some View {
        let dark = colorScheme == .dark
        return HStack(spacing: 8) { content() }
            .padding(.leading, 8)
            .padding(.trailing, 10)
            .frame(height: 36)
            .background(
                fill ?? (dark ? .white.opacity(0.11) : .black.opacity(0.045)),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .shadow(color: .black.opacity(dark ? 0 : 0.08), radius: 0.5, y: 0.5)
    }
}

/// Arc's header artwork: three cards with 🌴, 💻 and 📚. Turned over by `flip` it is one white card with 🙌, with a glow
/// that pulses once, blue in light and white in dark.
private struct SpaceCreationArtwork: View, Animatable {
    nonisolated var flip: CGFloat
    let glowing: Bool
    @State private var glow = 0.0
    @Environment(\.colorScheme) private var colorScheme

    nonisolated var animatableData: CGFloat {
        get { flip }
        set { flip = newValue }
    }

    var body: some View {
        ZStack {
            if flip < 0.5 {
                ZStack {
                    card("🌴").rotationEffect(.degrees(-12)).offset(x: -15, y: 2)
                    card("📚").rotationEffect(.degrees(12)).offset(x: 15, y: 2)
                    card("💻")
                }
            } else {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(colorScheme == .dark ? Color.white : Color(red: 0.35, green: 0.36, blue: 1))
                    .frame(width: 31, height: 39)
                    .blur(radius: 6)
                    .scaleEffect(1 + 0.4 * glow)
                    .opacity(glowing ? 1 - glow : 0)
                card("🙌")
                    .rotation3DEffect(.degrees(180), axis: (x: 1, y: 0, z: 0))
            }
        }
        .rotation3DEffect(.degrees(180 * flip), axis: (x: 1, y: 0, z: 0), perspective: 0.5)
        .accessibilityHidden(true)
        .onChange(of: glowing) { _, glowing in
            guard glowing else { return }
            withAnimation(.easeOut(duration: 0.45)) { glow = 1 }
        }
    }

    private func card(_ emoji: String) -> some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(.white)
            .strokeBorder(Color(white: 0.9), lineWidth: 0.5)
            .frame(width: 31, height: 39)
            .overlay(Text(emoji).font(.system(size: 15)))
            .shadow(color: .black.opacity(0.15), radius: 1.5, y: 0.5)
    }
}
