import Foundation

/// A keyboard shortcut expressed with Carbon virtual key codes and modifier
/// flags. Stored as raw integers so this module stays free of Carbon imports.
public struct KeyCombo: Codable, Equatable, Hashable {
    public var keyCode: UInt32
    public var modifiers: UInt32

    public init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// Carbon modifier bits, as defined in `Carbon.HIToolbox/Events.h`.
    public enum Modifier {
        public static let command: UInt32 = 0x0100
        public static let shift: UInt32 = 0x0200
        public static let option: UInt32 = 0x0800
        public static let control: UInt32 = 0x1000

        static let all = command | shift | option | control
    }

    /// True when at least one of ⌃⌥⇧⌘ is set.
    public var hasModifiers: Bool {
        modifiers & Modifier.all != 0
    }

    /// Human-readable form in the standard macOS order, e.g. "⌃⌥⇧⌘E".
    public var displayString: String {
        var result = ""
        if modifiers & Modifier.control != 0 { result += "⌃" }
        if modifiers & Modifier.option != 0 { result += "⌥" }
        if modifiers & Modifier.shift != 0 { result += "⇧" }
        if modifiers & Modifier.command != 0 { result += "⌘" }
        result += Self.keyName(for: keyCode)
        return result
    }

    /// Name of a key by its ANSI virtual key code; unknown codes become "Key<n>".
    public static func keyName(for keyCode: UInt32) -> String {
        keyNames[keyCode] ?? "Key\(keyCode)"
    }

    private static let keyNames: [UInt32: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
        11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T",
        18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9", 26: "7",
        27: "-", 28: "8", 29: "0", 30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P",
        36: "↩", 37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/",
        45: "N", 46: "M", 47: ".", 48: "⇥", 49: "Space", 50: "`", 51: "⌫", 53: "⎋",
        96: "F5", 97: "F6", 98: "F7", 99: "F3", 100: "F8", 101: "F9", 103: "F11",
        105: "F13", 107: "F14", 109: "F10", 111: "F12", 113: "F15", 114: "Help",
        115: "Home", 116: "PgUp", 117: "⌦", 118: "F4", 119: "End", 120: "F2",
        121: "PgDn", 122: "F1", 123: "←", 124: "→", 125: "↓", 126: "↑",
    ]
}
