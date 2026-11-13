import DevKit
import SwiftUI

/// Arc's Site Controls as open-arch E23 recorded it: the profile's extensions, the site's changed settings, each
/// toggled between allowed and blocked in place, then whether the connection is secure and "…" for every setting of
/// the site. Arc's page actions, Developer Mode and Automatic Picture-In-Picture rows are left out until Oa has them.
struct SiteControlsView: View {
    let model: WindowModel
    let isSecure: Bool
    let dismiss: () -> Void
    @State private var settings: [SiteSetting] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Extensions")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.bottom, 10)
            ExtensionGrid(model: model, dismiss: dismiss)
                .padding(.bottom, 15)
            if !settings.isEmpty {
                Text("Settings")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 6)
                ForEach(settings, id: \.type) { setting in
                    SiteSettingRow(setting: setting) {
                        model.toggle(setting)
                        settings = model.siteSettings()
                    }
                }
                Divider().padding(.top, 8).padding(.bottom, 10)
            }
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
        .padding(10)
        .frame(width: 236)
        .onAppear { settings = model.siteSettings() }
    }

    private func openAllSiteSettings() {
        dismiss()
        model.openAllSiteSettings()
    }
}

/// Arc's grid as measured (arc-extensions.md §8b, §9): 48×32 tiles four to a row, 8 pt apart, each extension's
/// with a 14 pt pin badge on its corner, then "+" for the Chrome Web Store.
private struct ExtensionGrid: View {
    let model: WindowModel
    let dismiss: () -> Void

    var body: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.fixed(48), spacing: 8), count: 4), alignment: .leading, spacing: 8
        ) {
            ForEach(model.extensionActions) { action in
                ExtensionTile(help: action.tooltip.isEmpty ? action.name : action.tooltip) {
                    dismiss()
                    model.runExtension(action.id)
                } menu: {
                    model.showExtensionMenu(for: action.id)
                    dismiss()
                } label: {
                    if let icon = action.icon {
                        Image(nsImage: icon).opacity(action.isEnabled ? 1 : 0.4)
                    } else {
                        Image(systemName: "puzzlepiece.extension.fill")
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    PinBadge(pinned: action.pinnedPosition != nil) { model.togglePin(of: action) }
                        .offset(x: 4, y: 4)
                }
            }
            ExtensionTile(help: "Add Extension") {
                dismiss()
                model.addExtension()
            } label: {
                Image(systemName: "plus").font(.system(size: 13, weight: .semibold))
            }
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
        .help(help)
    }
}

/// Oa's own for an extension that isn't pinned, which no Arc capture shows: the same badge in grey.
private struct PinBadge: View {
    let pinned: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            Image(systemName: "pin.fill")
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 14, height: 14)
                .background(pinned ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary), in: Circle())
        }
        .buttonStyle(.plain)
        .help(pinned ? "Unpin Extension" : "Pin Extension")
    }
}

/// Takes the secondary click over a view and nothing else; the engine draws the menu, which SwiftUI's own can't.
private struct SecondaryClick: NSViewRepresentable {
    let action: () -> Void

    func makeNSView(context: Context) -> ClickView { ClickView() }

    func updateNSView(_ view: ClickView, context: Context) { view.action = action }

    final class ClickView: NSView {
        var action: () -> Void = {}

        override func hitTest(_ point: NSPoint) -> NSView? {
            let event = NSApp.currentEvent
            let secondary =
                event?.type == .rightMouseDown
                || (event?.type == .leftMouseDown && event?.modifierFlags.contains(.control) == true)
            return secondary ? super.hitTest(point) : nil
        }

        override func rightMouseDown(with event: NSEvent) { action() }
        override func mouseDown(with event: NSEvent) { action() }
    }
}

/// A setting's symbol in a circle, filled when allowed, then its name and "Allowed" or "Blocked".
private struct SiteSettingRow: View {
    let setting: SiteSetting
    let toggle: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 9) {
                Image(systemName: setting.type.symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(setting.value.isAllowed ? Color(nsColor: .windowBackgroundColor) : .primary)
                    .frame(width: 32, height: 32)
                    .background(.primary.opacity(setting.value.isAllowed ? 0.92 : 0.16), in: Circle())
                VStack(alignment: .leading, spacing: 1) {
                    Text(setting.type.title).font(.system(size: 13, weight: .semibold))
                    Text(setting.value.isAllowed ? "Allowed" : "Blocked")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .contentShape(Rectangle())
            .background(.primary.opacity(hovering ? 0.06 : 0), in: RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal, -6)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
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

    var symbol: String {
        switch self {
        case .geolocation, .geolocationWithOptions: "location.fill"
        case .camera: "camera.fill"
        case .cameraPanTiltZoom: "camera.aperture"
        case .microphone: "mic.fill"
        case .sensors: "gyroscope"
        case .notifications: "bell.fill"
        case .javascript: "curlybraces"
        case .images: "photo.fill"
        case .popups: "arrow.up.forward.app.fill"
        case .windowManagement: "macwindow.on.rectangle"
        case .ads: "megaphone.fill"
        case .backgroundSync: "arrow.triangle.2.circlepath"
        case .sound: "speaker.wave.2.fill"
        case .automaticDownloads: "arrow.down.circle.fill"
        case .midiSysex: "pianokeys"
        case .clipboardReadWrite: "doc.on.clipboard.fill"
        case .usbGuard, .serialGuard: "cable.connector"
        case .hidGuard: "gamecontroller.fill"
        case .fileSystemWriteGuard: "folder.fill"
        case .localFonts: "textformat"
        case .bluetoothGuard, .bluetoothScanning: "antenna.radiowaves.left.and.right"
        case .handTracking: "hand.raised.fill"
        case .vr: "eyeglasses"
        case .ar: "cube.transparent"
        case .idleDetection: "moon.zzz.fill"
        case .federatedIdentityAPI: "person.badge.key.fill"
        case .automaticPictureInPicture: "pip.fill"
        case .capturedSurfaceControl: "rectangle.on.rectangle"
        case .automaticFullscreen: "arrow.up.left.and.arrow.down.right"
        case .keyboardLock: "keyboard.fill"
        case .pointerLock: "cursorarrow"
        case .webAppInstallation: "square.and.arrow.down.fill"
        case .localNetwork: "network"
        case .loopbackNetwork: "desktopcomputer"
        }
    }
}
