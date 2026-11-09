import DevKit
import DevKitLive
import Foundation

enum AppEngine {
    /// Chromium when the bundle carries its framework, else the stub. `OA_ENGINE=stub` forces the stub.
    @MainActor
    static func make() -> any BrowserApplication {
        if ProcessInfo.processInfo.environment["OA_ENGINE"] != "stub",
            let chromium = ChromiumBrowserApplication.bundled(
                userDataDirectory: dataDirectory.appendingPathComponent("Chromium", isDirectory: true))
        {
            return chromium
        }
        return StubBrowserApplication()
    }

    static var dataDirectory: URL {
        if let path = ProcessInfo.processInfo.environment["OA_DATA_DIRECTORY"] {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("Oa", isDirectory: true)
    }
}
