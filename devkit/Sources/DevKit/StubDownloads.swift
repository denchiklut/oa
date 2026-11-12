import Foundation
import Observation

/// Downloads without an engine: each takes about fifteen seconds at the engine's half-second cadence and leaves a
/// small text file in a temporary folder, so the app's file actions have something to act on.
@MainActor
@Observable
final class StubDownloads: Downloads {
    private(set) var items: [Download] = []
    @ObservationIgnored private var running: [Download.ID: Task<Void, Never>] = [:]
    @ObservationIgnored private var paused: Set<Download.ID> = []
    private static var count = 0
    private static let size: Int64 = 94_400_000

    func start(from page: URL?, pageID: UUID, failing: Bool) {
        Self.count += 1
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("OaStubDownloads")
        let id = UUID().uuidString
        items.append(
            Download(
                id: id, status: .inProgress, totalBytes: Self.size,
                file: folder.appendingPathComponent("stub-download-\(Self.count).txt"),
                sourceURL: page?.appendingPathComponent("file.txt"), pageID: pageID))
        running[id] = Task { [weak self] in
            for step in 1...30 {
                try? await Task.sleep(for: .milliseconds(500))
                while self?.paused.contains(id) == true { try? await Task.sleep(for: .milliseconds(500)) }
                guard !Task.isCancelled, let self else { return }
                if failing, step == 12 { return finish(id, as: .failed) }
                change(id) {
                    $0.receivedBytes = Self.size * Int64(step) / 30
                    $0.bytesPerSecond = Self.size / 15
                    $0.secondsRemaining = (30 - step) / 2
                }
            }
            self?.finish(id, as: .finished)
        }
    }

    func pause(_ id: Download.ID) {
        guard running[id] != nil else { return }
        paused.insert(id)
        change(id) { $0.status = .paused }
    }

    func resume(_ id: Download.ID) {
        guard paused.remove(id) != nil else { return }
        change(id) { $0.status = .inProgress }
    }

    func cancel(_ id: Download.ID) {
        if running[id] != nil { finish(id, as: .cancelled) }
    }

    func remove(_ id: Download.ID) {
        cancel(id)
        items.removeAll { $0.id == id }
    }

    private func finish(_ id: Download.ID, as status: Download.Status) {
        running.removeValue(forKey: id)?.cancel()
        paused.remove(id)
        change(id) {
            $0.status = status
            $0.bytesPerSecond = 0
            $0.secondsRemaining = nil
            guard status == .finished, let file = $0.file else { return }
            try? FileManager.default.createDirectory(
                at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? Data("A file from the stub engine.\n".utf8).write(to: file)
        }
    }

    private func change(_ id: Download.ID, _ change: (inout Download) -> Void) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        change(&items[index])
    }
}
