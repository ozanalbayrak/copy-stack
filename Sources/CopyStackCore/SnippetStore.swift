import Foundation
import os

/// Owns the snippet list and mirrors every change to a JSON file.
/// Use from the main thread only.
public final class SnippetStore: ObservableObject {
    @Published public private(set) var snippets: [Snippet]
    public let fileURL: URL

    private static let logger = Logger(subsystem: "com.ozanalbayrak.CopyStack", category: "SnippetStore")

    /// `~/Library/Application Support/CopyStack/snippets.json`
    public static var defaultFileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CopyStack", isDirectory: true)
            .appendingPathComponent("snippets.json")
    }

    public init(fileURL: URL = SnippetStore.defaultFileURL) {
        self.fileURL = fileURL
        self.snippets = Self.load(from: fileURL)
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
        snippets.removeAll { $0.id == id }
        save()
    }

    /// Replaces the stored snippet with the same id. Unknown ids are ignored.
    public func update(_ snippet: Snippet) {
        guard let index = snippets.firstIndex(where: { $0.id == snippet.id }) else { return }
        snippets[index] = snippet
        save()
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
