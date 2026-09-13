import Foundation
import os

/// Owns the snippet list and mirrors every change to a JSON file.
/// Use from the main thread only.
public final class SnippetStore: ObservableObject {
    @Published public private(set) var snippets: [Snippet]
    public let fileURL: URL
    private let secretStore: SecretStore
    /// Ids whose Keychain entry could not be removed, e.g. because the user
    /// denied the prompt while deleting the snippet. Dropped from the payload
    /// on the next successful write.
    private var pendingSecretRemovals: Set<UUID> = []

    private static let logger = Logger(subsystem: "com.ozanalbayrak.CopyStack", category: "SnippetStore")

    /// `~/Library/Application Support/CopyStack/snippets.json`
    public static var defaultFileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CopyStack", isDirectory: true)
            .appendingPathComponent("snippets.json")
    }

    public init(fileURL: URL = SnippetStore.defaultFileURL, secretStore: SecretStore = KeychainSecretStore()) {
        self.fileURL = fileURL
        self.secretStore = secretStore
        self.snippets = Self.load(from: fileURL)
    }

    public enum SnippetError: Error, Equatable {
        case unknownSnippet
    }

    // MARK: Mutations

    @discardableResult
    public func add(name: String = "New Snippet", text: String = "") -> Snippet {
        let snippet = Snippet(name: name, text: text)
        snippets.append(snippet)
        save()
        return snippet
    }

    public func remove(id: Snippet.ID) {
        guard let index = snippets.firstIndex(where: { $0.id == id }) else { return }
        let wasSecret = snippets[index].isSecret
        snippets.remove(at: index)
        save()
        if wasSecret {
            removeSecret(for: id)
        }
    }

    /// Replaces the stored snippet with the same id. Unknown ids are ignored.
    ///
    /// Never touches secret text or the `isSecret` flag: for a secret snippet
    /// `text` is forced back to `""`. Use `setText(_:for:)` and
    /// `setSecret(_:for:)` for those.
    public func update(_ snippet: Snippet) {
        guard let index = snippets.firstIndex(where: { $0.id == snippet.id }) else { return }
        var snippet = snippet
        snippet.isSecret = snippets[index].isSecret
        if snippet.isSecret {
            snippet.text = ""
        }
        snippets[index] = snippet
        save()
    }

    // MARK: Secrets

    /// The text to paste. Reads the secret store for secret snippets.
    public func text(for id: Snippet.ID) throws -> String {
        guard let snippet = snippets.first(where: { $0.id == id }) else {
            throw SnippetError.unknownSnippet
        }
        guard snippet.isSecret else { return snippet.text }
        return try secretStore.read()[id] ?? ""
    }

    /// Writes text to the right place: the JSON file for normal snippets,
    /// the secret store for secret ones.
    public func setText(_ text: String, for id: Snippet.ID) throws {
        guard let index = snippets.firstIndex(where: { $0.id == id }) else {
            throw SnippetError.unknownSnippet
        }
        if snippets[index].isSecret {
            var secrets = try secretStore.read()
            secrets[id] = text
            // An id being written is live again; it must not be stripped.
            pendingSecretRemovals.remove(id)
            try writeSecrets(secrets)
        } else {
            snippets[index].text = text
            save()
        }
    }

    /// Moves the text between the JSON file and the secret store and flips
    /// the flag. No-op when the snippet is already in the requested state.
    public func setSecret(_ isSecret: Bool, for id: Snippet.ID) throws {
        guard let index = snippets.firstIndex(where: { $0.id == id }) else {
            throw SnippetError.unknownSnippet
        }
        guard snippets[index].isSecret != isSecret else { return }
        var updated = snippets[index]
        if isSecret {
            // Secret store first: if it fails, nothing has changed.
            var secrets = try secretStore.read()
            secrets[id] = updated.text
            // A removal that failed earlier (toggle off, then on again) must
            // not strip the id that is being written now.
            pendingSecretRemovals.remove(id)
            try writeSecrets(secrets)
            updated.text = ""
            updated.isSecret = true
            snippets[index] = updated
            save()
        } else {
            let text = try secretStore.read()[id] ?? ""
            // JSON first: the text is safe before the secret entry goes away.
            updated.text = text
            updated.isSecret = false
            snippets[index] = updated
            save()
            removeSecret(for: id)
        }
    }

    /// Best-effort removal; the caller has already persisted the state that
    /// matters, so a failure here is only logged. The id is remembered so the
    /// next successful write drops the stale entry.
    private func removeSecret(for id: Snippet.ID) {
        do {
            var secrets = try secretStore.read()
            guard secrets.removeValue(forKey: id) != nil else { return }
            try writeSecrets(secrets)
        } catch {
            pendingSecretRemovals.insert(id)
            Self.logger.error("Failed to remove secret for \(id.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Every write goes through here so entries that could not be removed
    /// earlier are dropped as soon as the secret store accepts a write again.
    private func writeSecrets(_ secrets: [UUID: String]) throws {
        var secrets = secrets
        for id in pendingSecretRemovals {
            secrets.removeValue(forKey: id)
        }
        try secretStore.write(secrets)
        pendingSecretRemovals.removeAll()
    }

    // MARK: Shortcut validation

    public enum ValidationError: Error, Equatable {
        /// The combo has none of ⌘⌃⌥; a bare or ⇧-only key can't be a global hotkey.
        case missingModifier
        /// The combo is ⌘V, which CopyStack itself posts to paste.
        case reserved
        /// Another snippet already uses this combo.
        case shortcutConflict(ownerName: String)
    }

    /// The snippet that already owns `combo`, ignoring the snippet with id `excluding`.
    public func conflict(for combo: KeyCombo, excluding id: Snippet.ID? = nil) -> Snippet? {
        snippets.first { $0.id != id && $0.shortcut == combo }
    }

    /// Throws if `combo` can't be assigned to the snippet with `snippetID`.
    public func validate(_ combo: KeyCombo, for snippetID: Snippet.ID) throws {
        guard combo.hasModifiers else { throw ValidationError.missingModifier }
        if combo == KeyCombo.paste { throw ValidationError.reserved }
        if let owner = conflict(for: combo, excluding: snippetID) {
            throw ValidationError.shortcutConflict(ownerName: owner.name)
        }
    }

    // MARK: Persistence

    private func save() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(snippets)
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            Self.logger.error("Failed to save snippets: \(error.localizedDescription, privacy: .public)")
            return
        }
        // The file lists snippet names and shortcuts; keep it to the owner.
        do {
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        } catch {
            Self.logger.error("Failed to set permissions on snippets file: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func load(from fileURL: URL) -> [Snippet] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        do {
            let data = try Data(contentsOf: fileURL)
            return try JSONDecoder().decode([Snippet].self, from: data)
        } catch {
            logger.error("Failed to load snippets, starting empty: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }
}
