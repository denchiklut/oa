import DevKit
import SwiftUI

/// Arc's permission prompt as seen live: a popover 262 pt wide with the first kind's badge, the question and two buttons,
/// "Not Now" storing Block and "Allow" granting for good. A click outside or leaving the app dismisses it; Esc does
/// nothing.
struct PermissionRequestView: View {
    let model: WindowModel
    let request: PagePermissionRequest

    var body: some View {
        VStack(spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: request.kinds.first?.symbol ?? "hand.raised.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(.primary.opacity(0.08)))
                Text(Self.question(for: request))
                    .font(.system(size: 13, weight: .medium))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: 8) {
                Button("Not Now") { model.respond(to: request, with: .deny) }
                    .buttonStyle(PromptButtonStyle(fill: 0.06))
                Button("Allow") { model.respond(to: request, with: .allow) }
                    .buttonStyle(PromptButtonStyle(fill: 0.16))
            }
        }
        .padding(12)
        .frame(width: 236)
        .onDisappear { model.permissionPromptClosed() }
    }

    static func question(for request: PagePermissionRequest) -> String {
        let site = request.nameOrOrigin
        if request.kinds.count == 1 {
            switch request.kinds[0] {
            case .notifications: return "Allow \(site) to send you notifications?"
            case .idleDetection: return "Allow \(site) to know when you're actively using this device?"
            case .multipleDownloads: return "Allow \(site) to download multiple files?"
            case .quota: return "Allow \(site) to store files on your device?"
            default: break
            }
        }
        return "Allow \(site) to access your \(request.kinds.map(\.promptName).joined(separator: ", "))?"
    }
}

private struct PromptButtonStyle: ButtonStyle {
    let fill: Double

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .frame(maxWidth: .infinity, minHeight: 32)
            .background(
                RoundedRectangle(cornerRadius: 8).fill(.primary.opacity(configuration.isPressed ? fill + 0.08 : fill))
            )
            .contentShape(Rectangle())
    }
}

extension WindowModel {
    /// For a popover on the page's own bar; a click outside or leaving the app sets it false, which dismisses.
    func permissionPromptBinding(forPeek: Bool) -> Binding<Bool> {
        Binding(
            get: { self.permissionRequest != nil && (self.peek != nil) == forPeek },
            set: { shown in
                if !shown, let request = self.permissionRequest { self.respond(to: request, with: .dismiss) }
            })
    }
}

extension PermissionKind {
    /// As Arc's prompt words them: seen live for location, clipboard, camera and microphone; the rest follow the
    /// comments on Arc's strings.
    var promptName: String {
        switch self {
        case .ambientLogin: "ambient login"
        case .ar: "AR session"
        case .cameraPanTiltZoom: "camera pan and tilt"
        case .camera: "camera"
        case .capturedSurfaceControl: "captured surface control"
        case .clipboard: "clipboard"
        case .topLevelStorageAccess, .storageAccess, .quota: "storage"
        case .fileSystemAccess: "file system access"
        case .geolocation: "location"
        case .handTracking: "hand tracking"
        case .identityProvider: "identity provider"
        case .idleDetection: "idle detection"
        case .localFonts: "font access"
        case .localNetwork: "local network"
        case .loopbackNetwork: "loopback network"
        case .microphone: "microphone"
        case .midiSysex: "MIDI sysex"
        case .multipleDownloads: "automatic downloads"
        case .notifications: "notifications"
        case .keyboardLock: "keyboard lock"
        case .pointerLock: "pointer lock"
        case .protocolHandler: "protocol handlers"
        case .sensors: "sensors"
        case .vr: "VR session"
        case .webAppInstallation: "web app installation"
        case .windowManagement: "window management"
        }
    }

    var symbol: String {
        switch self {
        case .notifications: "bell.fill"
        case .geolocation: "location.fill"
        case .clipboard: "clipboard.fill"
        case .camera, .cameraPanTiltZoom: "camera.fill"
        case .microphone: "mic.fill"
        case .multipleDownloads: "arrow.down.circle.fill"
        case .midiSysex: "pianokeys"
        case .sensors: "sensor.fill"
        case .localFonts: "textformat"
        case .windowManagement: "macwindow.on.rectangle"
        default: "hand.raised.fill"
        }
    }
}
