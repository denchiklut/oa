import AppKit
import Darwin
import DevKit
import Foundation

/// The live engine: Chromium through OaCore inside the app bundle's framework. Chromium's run loop drives AppKit.
@MainActor
public final class ChromiumBrowserApplication: BrowserApplication {
    private let main: CoreMain
    private let arguments: [String]
    private var engine: CoreEngine?
    private var contexts: [UUID: ChromiumBrowserContext] = [:]

    /// Loads the framework from the app bundle, or nil when the bundle has none. Call it before the process starts a
    /// second thread: PartitionAlloc installs its allocator when the framework loads.
    public static func bundled(userDataDirectory: URL) -> ChromiumBrowserApplication? {
        guard
            let frameworks = Bundle.main.privateFrameworksURL,
            case let path = frameworks.appendingPathComponent("Chromium Framework.framework/Chromium Framework").path,
            FileManager.default.fileExists(atPath: path)
        else { return nil }
        guard let library = dlopen(path, RTLD_LAZY | RTLD_LOCAL | RTLD_FIRST) else {
            FileHandle.standardError.write(Data("oa: dlopen \(path): \(String(cString: dlerror()))\n".utf8))
            return nil
        }
        guard let symbol = dlsym(library, "OACoreMain") else {
            FileHandle.standardError.write(Data("oa: the framework has no OACoreMain\n".utf8))
            return nil
        }
        return ChromiumBrowserApplication(
            main: unsafeBitCast(symbol, to: CoreMain.self), userDataDirectory: userDataDirectory)
    }

    private init(main: CoreMain, userDataDirectory: URL) {
        self.main = main
        arguments = CommandLine.arguments + ["--user-data-dir=\(userDataDirectory.path)", "--use-mock-keychain"]
    }

    public func run(ready: @escaping @MainActor () -> Void) -> Int32 {
        let start = Start(application: self, ready: ready)
        let context = Unmanaged.passRetained(start).toOpaque()
        defer { Unmanaged<Start>.fromOpaque(context).release() }
        var argv: [UnsafePointer<CChar>?] = arguments.map { UnsafePointer(strdup($0)) } + [nil]
        let callback: CoreReadyCallback = { context, engine in
            let start = Unmanaged<Start>.fromOpaque(context!).takeUnretainedValue()
            let object = Unmanaged<AnyObject>.fromOpaque(engine).takeUnretainedValue()
            MainActor.assumeIsolated { start.engineDidStart(object) }
        }
        return argv.withUnsafeMutableBufferPointer { argv in
            main(Int32(arguments.count), argv.baseAddress!, callback, context)
        }
    }

    public func terminate() {
        NSApplication.shared.reply(toApplicationShouldTerminate: false)
        engine?.quit()
    }

    public func browserContext(id: UUID) -> any BrowserContext {
        if let context = contexts[id] { return context }
        let context = ChromiumBrowserContext(
            id: id, profile: { [weak self] in self?.engine?.profile(identifier: id.uuidString) })
        contexts[id] = context
        return context
    }

    public func attachWindow(_ window: NSWindow, id: UUID) {
        engine?.attach(window, identifier: id.uuidString)
    }

    public func closeWindow(id: UUID) {
        engine?.closeWindow(identifier: id.uuidString)
    }

    public func askToLeave(windowID: UUID) async -> Bool {
        guard let engine else { return true }
        return await withCheckedContinuation { continuation in
            engine.askToLeaveWindow(identifier: windowID.uuidString) { continuation.resume(returning: $0) }
        }
    }

    @MainActor
    private final class Start {
        let application: ChromiumBrowserApplication
        let ready: @MainActor () -> Void

        init(application: ChromiumBrowserApplication, ready: @escaping @MainActor () -> Void) {
            self.application = application
            self.ready = ready
        }

        func engineDidStart(_ engine: AnyObject) {
            application.engine = unsafeBitCast(engine, to: CoreEngine.self)
            ready()
        }
    }
}

@MainActor
final class ChromiumBrowserContext: BrowserContext {
    let id: UUID
    private let profile: @MainActor () -> CoreProfile?

    init(id: UUID, profile: @escaping @MainActor () -> CoreProfile?) {
        self.id = id
        self.profile = profile
    }

    func makePage(windowID: UUID, restoring sessionID: PageSessionID?) async -> (page: any Page, restored: Bool)? {
        guard let profile = profile() else { return nil }
        let delegate = PageDelegate()
        let created = CreatedPage()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            profile.createPage(
                inWindow: windowID.uuidString, restoringSessionID: sessionID?.rawValue ?? -1, delegate: delegate
            ) { page, restored in
                MainActor.assumeIsolated {
                    created.page = page
                    created.restored = restored
                }
                continuation.resume()
            }
        }
        guard let page = created.page else { return nil }
        return (ChromiumPage(id: UUID(), page: page, delegate: delegate), created.restored)
    }
}

@MainActor
private final class CreatedPage {
    var page: CorePage?
    var restored = false
}
