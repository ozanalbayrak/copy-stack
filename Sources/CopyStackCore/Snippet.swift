import Foundation

/// A named piece of text that can be pasted, optionally bound to a global shortcut.
public struct Snippet: Identifiable, Codable, Equatable {
    public var id: UUID
    /// Label shown in the menu, e.g. "Email".
    public var name: String
    /// Content to paste; may span multiple lines. Always `""` for secret
    /// snippets — their text lives in the `SecretStore`.
    public var text: String
    /// `nil` means the snippet is reachable from the menu only.
    public var shortcut: KeyCombo?
    /// When true the text is kept in the Keychain instead of the JSON file.
    public var isSecret: Bool

    public init(id: UUID = UUID(), name: String, text: String = "", shortcut: KeyCombo? = nil,
                isSecret: Bool = false) {
        self.id = id
        self.name = name
        self.text = text
        self.shortcut = shortcut
        self.isSecret = isSecret
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, text, shortcut, isSecret
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        text = try container.decode(String.self, forKey: .text)
        shortcut = try container.decodeIfPresent(KeyCombo.self, forKey: .shortcut)
        // Files written before 0.2.0 have no `isSecret` key.
        isSecret = try container.decodeIfPresent(Bool.self, forKey: .isSecret) ?? false
    }
}
