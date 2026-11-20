import AppKit
import Carbon.HIToolbox

/// Arc's `ARCKeyboardShortcut`, stored under its names: the key as a character and the four modifiers.
struct ARCKeyboardShortcut: Hashable, Codable {
    static let modifierMask: NSEvent.ModifierFlags = [.shift, .control, .option, .command]

    /// Arc's `shortcutsForbiddenForUsers`: never recorded, never loaded and never kept from a page.
    static let shortcutsForbiddenForUsers: Set<ARCKeyboardShortcut> = [
        ARCKeyboardShortcut(key: "z", modifiers: .command), ARCKeyboardShortcut(key: "x", modifiers: .command),
        ARCKeyboardShortcut(key: "v", modifiers: .command),
        ARCKeyboardShortcut(key: "z", modifiers: [.command, .shift]),
        ARCKeyboardShortcut(key: "i", modifiers: .command), ARCKeyboardShortcut(key: "b", modifiers: .command),
        ARCKeyboardShortcut(key: "u", modifiers: .command), ARCKeyboardShortcut(key: "a", modifiers: .command),
        ARCKeyboardShortcut(key: "\t", modifiers: .option),
    ]

    let deviceIndependentModifierFlags: UInt
    let keyEquivalent: String

    var modifiers: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: deviceIndependentModifierFlags) }

    /// As Arc reads a menu item's: lower case, Shift for an upper-case key, and one spelling for a special key.
    init(key: String, modifiers: NSEvent.ModifierFlags) {
        let lowercased = key.lowercased()
        var modifiers = modifiers.intersection(Self.modifierMask)
        if lowercased != key { modifiers.insert(.shift) }
        keyEquivalent = KeyCode.code(for: lowercased).flatMap(KeyCode.character) ?? lowercased
        deviceIndependentModifierFlags = modifiers.rawValue
    }

    /// As Arc's `NSEvent.keyboardShortcut`. The key is `characters` under Command without Control or Option,
    /// whatever Shift does, which a layout that turns Latin under Command gives in Latin; otherwise the key
    /// without its modifiers; and the key code's character when the event has none.
    init?(event: NSEvent) {
        guard event.type == .keyDown || event.type == .keyUp else { return nil }
        let latin = event.modifierFlags.intersection([.command, .control, .option]) == .command
        let characters = latin ? event.characters : event.charactersIgnoringModifiers
        guard let key = characters.flatMap({ $0.isEmpty ? nil : $0 }) ?? KeyCode.character(for: event.keyCode)
        else { return nil }
        self.init(key: key.lowercased(), modifiers: event.modifierFlags)
    }

    /// As Arc reads a key a page consumed: by the key itself, not by what the layout types with it.
    init?(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        guard let key = KeyCode.character(for: keyCode) else { return nil }
        self.init(key: key, modifiers: modifiers)
    }

    /// What `NSMenuItem.keyEquivalent` takes for the key.
    var menuKeyEquivalent: String {
        if keyEquivalent == "⇥", modifiers.contains(.shift) { return "\u{19}" }
        return KeyCode.menuCharacters[keyEquivalent] ?? keyEquivalent
    }

    /// One string per key cap: the modifiers in the system's order, then the key.
    var symbols: [String] {
        let modifiers = modifiers
        let names: [(NSEvent.ModifierFlags, String)] = [
            (.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘"),
        ]
        return names.filter { modifiers.contains($0.0) }.map(\.1) + [keySymbol]
    }

    private var keySymbol: String {
        if let scalar = keyEquivalent.unicodeScalars.first, keyEquivalent.unicodeScalars.count == 1,
            (0xF704...0xF726).contains(scalar.value)
        {
            return "F\(scalar.value - 0xF703)"
        }
        return keyEquivalent == " " ? "⎵" : keyEquivalent.uppercased()
    }
}

/// Arc's `KeyCode` with its `keyToCharacterMapping`: the US character of each key, a glyph for a special key and
/// AppKit's code point for a function key.
enum KeyCode {
    private static let characters: [UInt16: String] = [
        0: "a", 1: "s", 2: "d", 3: "f", 4: "h", 5: "g", 6: "z", 7: "x", 8: "c", 9: "v", 11: "b", 12: "q", 13: "w",
        14: "e", 15: "r", 16: "y", 17: "t", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9",
        26: "7", 27: "-", 28: "8", 29: "0", 30: "]", 31: "o", 32: "u", 33: "[", 34: "i", 35: "p", 36: "↩", 37: "l",
        38: "j", 39: "'", 40: "k", 41: ";", 42: "\\", 43: ",", 44: "/", 45: "n", 46: "m", 47: ".", 48: "⇥",
        49: " ", 50: "`", 51: "⌫", 53: "⎋", 64: "\u{F714}", 65: ".", 67: "𝗑", 69: "+", 71: "⌧", 75: "/",
        76: "↩\u{FE0E}", 78: "-", 79: "\u{F715}", 80: "\u{F716}", 81: "=", 82: "0", 83: "1", 84: "2", 85: "3",
        86: "4", 87: "5", 88: "6", 89: "7", 90: "\u{F717}", 91: "8", 92: "9", 96: "\u{F708}", 97: "\u{F709}",
        98: "\u{F70A}", 99: "\u{F706}", 100: "\u{F70B}", 101: "\u{F70C}", 103: "\u{F70E}", 105: "\u{F710}",
        106: "\u{F713}", 107: "\u{F711}", 109: "\u{F70D}", 111: "\u{F70F}", 113: "\u{F712}", 114: "?\u{20DD}",
        115: "↖", 116: "⇞", 117: "⌦", 118: "\u{F707}", 119: "↘", 120: "\u{F705}", 121: "⇟", 122: "\u{F704}",
        123: "←", 124: "→", 125: "↓", 126: "↑",
    ]

    /// AppKit's spellings of the special keys, by their glyph.
    static let menuCharacters: [String: String] = [
        "↩": "\r", "↩\u{FE0E}": "\u{3}", "⌫": "\u{8}", "⌦": "\u{F728}", "⎋": "\u{1B}", "⇥": "\t",
        "↖": "\u{F729}", "↘": "\u{F72B}", "⇞": "\u{F72C}", "⇟": "\u{F72D}", "?\u{20DD}": "\u{F746}",
        "⌧": "\u{F739}", "↑": "\u{F700}", "↓": "\u{F701}", "←": "\u{F702}", "→": "\u{F703}",
    ]

    private static let codes: [String: UInt16] = {
        var codes: [String: UInt16] = ["\u{19}": 48, "\u{7F}": 51]
        for (glyph, character) in menuCharacters {
            codes[character] = characters.first { $0.value == glyph }?.key
        }
        for (code, character) in characters.sorted(by: { $0.key > $1.key }) { codes[character] = code }
        return codes
    }()

    static func code(for string: String) -> UInt16? { codes[string] }

    /// As Arc's `keyCodeToCharacter`: the table, and for a key outside it the current Latin layout's character.
    static func character(for code: UInt16) -> String? {
        if let character = characters[code] { return character }
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
            let property = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(property).takeUnretainedValue() as Data
        var deadKeys: UInt32 = 0
        var length = 0
        var units = [UniChar](repeating: 0, count: 4)
        let status = data.withUnsafeBytes {
            UCKeyTranslate(
                $0.bindMemory(to: UCKeyboardLayout.self).baseAddress, code, UInt16(kUCKeyActionDisplay), 0,
                UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeys, units.count, &length,
                &units)
        }
        return status == noErr && length > 0 ? String(utf16CodeUnits: units, count: length) : nil
    }
}

extension NSMenuItem {
    /// As Arc's `NSMenuItem.keyboardShortcut`.
    var keyboardShortcut: ARCKeyboardShortcut? {
        keyEquivalent.isEmpty ? nil : ARCKeyboardShortcut(key: keyEquivalent, modifiers: keyEquivalentModifierMask)
    }
}
