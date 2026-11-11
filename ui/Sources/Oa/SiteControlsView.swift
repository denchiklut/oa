import DevKit
import SwiftUI

/// Arc's Site Controls as open-arch E23 recorded it: the site's changed settings, each toggled between allowed and
/// blocked in place, then whether the connection is secure and "…" for every setting of the site. Arc's page actions,
/// extensions, Developer Mode and Automatic Picture-In-Picture rows are left out until Oa has them.
struct SiteControlsView: View {
    let model: WindowModel
    let isSecure: Bool
    let dismiss: () -> Void
    @State private var settings: [SiteSetting] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
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
        .padding(12)
        .frame(width: 236)
        .onAppear { settings = model.siteSettings() }
    }

    private func openAllSiteSettings() {
        dismiss()
        model.openAllSiteSettings()
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
