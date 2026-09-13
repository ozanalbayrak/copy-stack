import Foundation

/// A named piece of text that can be pasted, optionally bound to a global shortcut.
public struct Snippet: Identifiable, Codable, Equatable {
    public var id: UUID
    /// Label shown in the menu, e.g. "Email".
    public var name: String
    /// Content to paste; may span multiple lines.
    public var text: String
    /// `nil` means the snippet is reachable from the menu only.
    public var shortcut: KeyCombo?

    public init(id: UUID = UUID(), name: String, text: String = "", shortcut: KeyCombo? = nil) {
        self.id = id
        self.name = name
        self.text = text
        self.shortcut = shortcut
    }
}
