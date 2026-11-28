import DevKit
import SwiftUI

/// Arc's Site Controls as open-arch E23 recorded it: the profile's extensions, the site's settings, each toggled
/// between allowed and blocked in place, then whether the connection is secure and "…" for every setting of the site.
/// Arc's page actions are left out until Oa has them.
struct SiteControlsView: View {
    let model: WindowModel
    let isSecure: Bool
    let isInternal: Bool
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ExtensionsSection(model: model, dismiss: dismiss)
                .padding(.bottom, 15)
            SettingsSection(model: model, dismiss: dismiss)
            // As Arc: none on its own pages.
            if !isInternal {
                Divider().padding(.top, 8).padding(.bottom, 10)
                HStack {
                    Label(isSecure ? "Secure" : "Insecure", systemImage: isSecure ? "lock.fill" : "lock.slash.fill")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(isSecure ? AnyShapeStyle(.primary) : AnyShapeStyle(Color.orange))
                        .padding(.horizontal, 10)
                        .frame(height: 28)
                        .background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                    Spacer()
                    Menu {
                        Button("Manage Extensions…") {
                            dismiss()
                            model.manageExtensions()
                        }
                        Button("Add Extension…") {
                            dismiss()
                            model.addExtension()
                        }
                        Button("All Site Settings…") { openAllSiteSettings() }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 13, weight: .bold))
                            .frame(width: 28, height: 28)
                            .background(.primary.opacity(0.06), in: Circle())
                    }
                    .menuStyle(.button)
                    .buttonStyle(.plain)
                    .menuIndicator(.hidden)
                    .fixedSize()
                }
            }
        }
        .padding(10)
        .frame(width: 236)
        .background(SiteControlsHitTestAnchor(browserWindow: model.window))
        .modifier(SiteControlsAppearance(model: model))
    }

    private func openAllSiteSettings() {
        dismiss()
        model.openAllSiteSettings()
    }
}

struct SiteControlsAppearance: ViewModifier {
    let model: WindowModel
    @Environment(\.windowColorScheme) private var scheme

    func body(content: Content) -> some View {
        let theme = model.space.map(model.theme(of:)) ?? .default
        let ink = scheme == .dark ? Color.white : .black
        // The native popover follows the window even when the sidebar uses light ink on dark or vice versa.
        content
            .foregroundStyle(ink.opacity(0.75), ink.opacity(0.5), ink.opacity(0.35))
            .tint(theme.semanticColorPalette[scheme].maxContrastColor.color)
            .environment(\.colorScheme, scheme)
    }
}

private struct SiteControlsHitTestAnchor: NSViewRepresentable {
    let browserWindow: NSWindow?

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        (browserWindow?.contentView as? KeyboardShortcutInterceptionView)?.siteControlsContent = view
    }
}

/// Arc's section as measured (arc-extensions.md §8b, §9): the header, with "Manage" at its end while the pointer is
/// over the section, then 48×32 tiles four to a row, 8 pt apart, and "+" for the Chrome Web Store.
struct ExtensionsSection: View {
    let model: WindowModel
    let dismiss: () -> Void
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Extensions")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button("Manage") {
                    dismiss()
                    model.manageExtensions()
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.tertiary)
                .opacity(hovering ? 1 : 0)
            }
            LazyVGrid(
                columns: Array(repeating: GridItem(.fixed(48), spacing: 8), count: 4), alignment: .leading, spacing: 8
            ) {
                ForEach(model.extensionActions) { action in
                    ExtensionActionTile(model: model, action: action, dismiss: dismiss)
                }
                ExtensionTile(help: "Add Extension") {
                    dismiss()
                    model.addExtension()
                } label: {
                    Image(systemName: "plus").font(.system(size: 13, weight: .semibold))
                }
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}

/// Arc's section (arc-site-controls.md): "More" at the header's end while the pointer is over the section, the whole
/// header opening every setting of the site; the site's changed settings, then Developer Mode, then Automatic
/// Picture-In-Picture.
private struct SettingsSection: View {
    let model: WindowModel
    let dismiss: () -> Void
    @State private var settings: [SiteSetting] = []
    @State private var offersReload = false
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                dismiss()
                model.openAllSiteSettings()
            } label: {
                HStack {
                    Text("Settings")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Text("More")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .opacity(hovering ? 1 : 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            ForEach(settings.filter { $0.type != .automaticPictureInPicture }, id: \.type) { setting in
                SiteSettingRow(setting: setting) { toggle(setting) }
            }
            if let url = model.frontPage?.url, ["http", "https"].contains(url.scheme ?? ""), url.host() != nil {
                let blocker = model.adBlocker
                let on = blocker.isEnabled && !blocker.isExcluded(url)
                SiteSettingRow(title: "Block Ads & Trackers", value: on ? "On" : "Off", symbol: "shield.fill", isOn: on)
                {
                    blocker.setExcluded(on, for: url)
                    offersReload = true
                }
                .disabled(!blocker.isEnabled)
                .oaToolTip(
                    !blocker.isEnabled
                        ? "The built-in ad blocker is off. You can change this in Settings."
                        : on
                            ? "The built-in ad blocker is turned on for this site."
                            : "The built-in ad blocker is disabled for this site.")
                if offersReload {
                    Button("Reload Page") {
                        model.frontPage?.reload()
                        offersReload = false
                        dismiss()
                    }.buttonStyle(.plain).padding(.horizontal, 10)
                }
            }
            if let site = RecentPagesSite(url: model.frontPage?.url), model.sidebarContext == .global {
                let previews = model.previewPreferences
                let on = previews.isEnabled(site)
                SiteSettingRow(title: "\(site.name) Previews", value: on ? "On" : "Off", symbol: "eye.fill", isOn: on) {
                    previews.setEnabled(!on, for: site)
                }
                .disabled(!previews.recentPages)
            }
            if GmailAccount(url: model.frontPage?.url) != nil, model.sidebarContext == .global {
                let previews = model.previewPreferences
                let on = previews.gmailEnabled
                SiteSettingRow(title: "Gmail Previews", value: on ? "On" : "Off", symbol: "eye.fill", isOn: on) {
                    previews.gmailSiteEnabled.toggle()
                }
                .disabled(!previews.gmail)
            }
            if let url = model.developerModeURL {
                let on = model.developerMode.isEnabled(for: url)
                SiteSettingRow(title: "Developer Mode", value: on ? "On" : "Off", symbol: "hammer.fill", isOn: on) {
                    dismiss()
                    model.developerMode.toggle(for: url)
                }
            }
            if let setting = settings.first(where: { $0.type == .automaticPictureInPicture }) {
                SiteSettingRow(setting: setting) { toggle(setting) }
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onAppear { settings = model.siteSettings() }
    }

    private func toggle(_ setting: SiteSetting) {
        model.toggle(setting)
        settings = model.siteSettings()
    }
}

/// An extension's tile with its pin on the corner: always for a pinned one, only under the pointer otherwise, as Arc
/// shows it.
private struct ExtensionActionTile: View {
    let model: WindowModel
    let action: ExtensionAction
    let dismiss: () -> Void
    @State private var overTile = false
    @State private var overPin = false

    var body: some View {
        let pinned = action.pinnedPosition != nil
        ExtensionTile(help: action.tooltip.isEmpty ? action.name : action.tooltip) {
            dismiss()
            model.runExtension(action.id)
        } menu: {
            model.showExtensionMenu(for: action.id)
            dismiss()
        } label: {
            ExtensionActionIcon(action: action)
        }
        .onHover { overTile = $0 }
        .overlay(alignment: .bottomTrailing) {
            PinBadge(pinned: pinned) { model.togglePin(of: action) }
                .onHover { overPin = $0 }
                .offset(x: 4, y: 4)
                .opacity(pinned || overTile || overPin ? 1 : 0)
        }
    }
}

private struct ExtensionTile<Label: View>: View {
    let help: String
    let action: () -> Void
    var menu: (() -> Void)?
    @ViewBuilder let label: Label
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            label
                .frame(width: 48, height: 32)
                .background(.primary.opacity(hovering ? 0.12 : 0.06), in: RoundedRectangle(cornerRadius: 8))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .overlay { if let menu { SecondaryClick(action: menu) } }
        .oaToolTip(help)
    }
}

/// Solid for a pinned extension, pale for one that isn't, as Arc draws them.
private struct PinBadge: View {
    let pinned: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            SiteControlsBadge(
                symbol: "pin.fill", font: .system(size: 7, weight: .bold), size: 14, opacity: pinned ? 1 : 0.4)
        }
        .buttonStyle(.plain)
        .oaToolTip(pinned ? "Unpin" : "Pin")
    }
}

private struct SiteControlsBadge: View {
    let symbol: String
    let font: Font
    let size: CGFloat
    let opacity: Double

    var body: some View {
        Circle()
            .fill(.tint.opacity(opacity))
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: symbol)
                    .font(font)
                    .foregroundStyle(.black)
                    .blendMode(.destinationOut)
            }
            .compositingGroup()
    }
}

private struct SiteSettingRow: View {
    let title: String
    let value: String
    let symbol: String
    let isOn: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 9) {
                SiteControlsBadge(
                    symbol: symbol, font: .system(size: 12, weight: .semibold), size: 28, opacity: isOn ? 1 : 0.33)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 13, weight: .semibold))
                    Text(value)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .lineLimit(1)
                Spacer(minLength: 0)
            }
            .frame(height: 33)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

extension SiteSettingRow {
    /// Arc draws every content setting with a gear.
    init(setting: SiteSetting, toggle: @escaping () -> Void) {
        let isOn = setting.value.isAllowed
        self.init(
            title: setting.type.title, value: isOn ? "Allowed" : "Blocked", symbol: "gearshape.fill", isOn: isOn,
            toggle: toggle)
    }
}

extension SiteSettingValue {
    /// As Arc: allowed for the session counts, asking doesn't.
    var isAllowed: Bool { self == .allow || self == .sessionOnly }
}

extension SiteSettingType {
    /// Chrome's names in title case, as Arc shows them.
    var title: String {
        switch self {
        case .geolocation, .geolocationWithOptions: "Location"
        case .camera: "Camera"
        case .cameraPanTiltZoom: "Camera Use & Movement"
        case .microphone: "Microphone"
        case .sensors: "Motion Sensors"
        case .notifications: "Notifications"
        case .javascript: "JavaScript"
        case .images: "Images"
        case .popups: "Pop-Ups and Redirects"
        case .windowManagement: "Window Management"
        case .ads: "Intrusive Ads"
        case .backgroundSync: "Background Sync"
        case .sound: "Sound"
        case .automaticDownloads: "Automatic Downloads"
        case .midiSysex: "MIDI Device Control"
        case .clipboardReadWrite: "Clipboard"
        case .usbGuard: "USB Devices"
        case .hidGuard: "HID Devices"
        case .serialGuard: "Serial Ports"
        case .fileSystemWriteGuard: "File Editing"
        case .localFonts: "Fonts"
        case .bluetoothGuard: "Bluetooth Devices"
        case .bluetoothScanning: "Bluetooth Scanning"
        case .handTracking: "Hand Tracking"
        case .vr: "Virtual Reality"
        case .ar: "Augmented Reality"
        case .idleDetection: "Your Device Use"
        case .federatedIdentityAPI: "Third-Party Sign-In"
        case .automaticPictureInPicture: "Automatic Picture-In-Picture"
        case .capturedSurfaceControl: "Scrolling and Zooming Shared Tabs"
        case .automaticFullscreen: "Automatic Full Screen"
        case .keyboardLock: "Keyboard Override"
        case .pointerLock: "Mouse Lock and Use"
        case .webAppInstallation: "Web App Installations"
        case .localNetwork: "Local Network"
        case .loopbackNetwork: "Apps on Device"
        }
    }
}
