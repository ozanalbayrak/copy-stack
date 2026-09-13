import XCTest
@testable import CopyStackCore

final class SnippetStoreTests: XCTestCase {
    private var directory: URL!
    private var fileURL: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CopyStackTests-\(UUID().uuidString)", isDirectory: true)
        fileURL = directory.appendingPathComponent("snippets.json")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: Persistence

    func testStartsEmptyWhenFileIsMissing() {
        XCTAssertEqual(SnippetStore(fileURL: fileURL).snippets, [])
    }

    func testAddPersistsAndReloads() {
        let store = SnippetStore(fileURL: fileURL)
        let added = store.add(name: "Email", text: "me@example.com")
        XCTAssertEqual(store.snippets, [added])
        XCTAssertEqual(SnippetStore(fileURL: fileURL).snippets, [added])
    }

    func testAddUsesDefaultNameAndEmptyText() {
        let snippet = SnippetStore(fileURL: fileURL).add()
        XCTAssertEqual(snippet.name, "New Snippet")
        XCTAssertEqual(snippet.text, "")
        XCTAssertNil(snippet.shortcut)
    }

    func testUpdateReplacesMatchingSnippetAndPersists() {
        let store = SnippetStore(fileURL: fileURL)
        var snippet = store.add(name: "Email", text: "old")
        snippet.text = "new"
        snippet.shortcut = KeyCombo(keyCode: 14, modifiers: KeyCombo.Modifier.control)
        store.update(snippet)
        XCTAssertEqual(store.snippets, [snippet])
        XCTAssertEqual(SnippetStore(fileURL: fileURL).snippets, [snippet])
    }

    func testUpdateIgnoresUnknownID() {
        let store = SnippetStore(fileURL: fileURL)
        store.add(name: "Email")
        store.update(Snippet(name: "Ghost"))
        XCTAssertEqual(store.snippets.map(\.name), ["Email"])
    }

    func testRemoveDeletesSnippetAndPersists() {
        let store = SnippetStore(fileURL: fileURL)
        let email = store.add(name: "Email")
        let slack = store.add(name: "Slack")
        store.remove(id: email.id)
        XCTAssertEqual(store.snippets, [slack])
        XCTAssertEqual(SnippetStore(fileURL: fileURL).snippets, [slack])
    }

    func testStartsEmptyWhenFileIsCorrupt() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: fileURL)
        XCTAssertEqual(SnippetStore(fileURL: fileURL).snippets, [])
    }

    func testSavedFileIsPrettyPrintedJSON() throws {
        SnippetStore(fileURL: fileURL).add(name: "Email", text: "me@example.com")
        let contents = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertTrue(contents.contains("\n"), "expected multi-line output, got: \(contents)")
        XCTAssertTrue(contents.contains("\"Email\""))
    }
}
