import Foundation

/// Arc's `SessionRestorationClient`: the engine tab each sidebar item had in each window and profile, so the pages the
/// engine restores from the last session find their items. Kept in Arc's `StorableSessionRestorationData.json`,
/// with Oa's profile ID where Arc's context ID is.
@MainActor
final class SessionRestorationClient {
    struct Key: Codable, Hashable {
        struct Browser: Codable, Hashable {
            let windowID: UUID
            let contextID: UUID
        }

        let itemId: UUID
        let browser: Browser
    }

    /// As read at launch: the last session's tabs.
    let lastSession: [Key: Int32]
    private let url: URL
    private var written: [Key: Int32]
    private var frozen = false

    init(directory: URL) {
        url = directory.appendingPathComponent("StorableSessionRestorationData.json")
        let stored = (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(Stored.self, from: $0) }
        lastSession = stored?.mapping.values ?? [:]
        written = lastSession
    }

    /// Arc's `getTabOwnerId`: the item whose tab had `sessionID` in the last session, in the window's own browser
    /// first.
    func owner(ofTab sessionID: Int32, contextID: UUID, windowID: UUID) -> Key? {
        let owners = lastSession.filter { $0.value == sessionID && $0.key.browser.contextID == contextID }.keys
        return owners.first { $0.browser.windowID == windowID } ?? owners.first
    }

    func save(_ mapping: [Key: Int32]) {
        guard !frozen, mapping != written else { return }
        written = mapping
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? encoder.encode(Stored(mapping: Mapping(values: mapping))).write(to: url, options: .atomic)
    }

    /// The mapping at quit, before the windows let go of their pages; nothing is written after it.
    func saveAndFreeze(_ mapping: [Key: Int32]) {
        save(mapping)
        frozen = true
    }

    private struct Stored: Codable {
        var version = 1
        let mapping: Mapping
    }

    /// Arc's dictionary encoding: keys and values one after another in `keysToValues`.
    private struct Mapping: Codable {
        let values: [Key: Int32]

        init(values: [Key: Int32]) { self.values = values }

        private enum CodingKeys: String, CodingKey { case keysToValues }

        init(from decoder: Decoder) throws {
            var list = try decoder.container(keyedBy: CodingKeys.self).nestedUnkeyedContainer(forKey: .keysToValues)
            var values: [Key: Int32] = [:]
            while !list.isAtEnd {
                let key = try list.decode(Key.self)
                values[key] = try list.decode(Int32.self)
            }
            self.values = values
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            var list = container.nestedUnkeyedContainer(forKey: .keysToValues)
            for (key, value) in values.sorted(by: { $0.key.itemId.uuidString < $1.key.itemId.uuidString }) {
                try list.encode(key)
                try list.encode(value)
            }
        }
    }
}
