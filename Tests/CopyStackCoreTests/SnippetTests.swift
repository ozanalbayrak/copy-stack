import XCTest
@testable import CopyStackCore

final class SnippetTests: XCTestCase {
    func testDecodesLegacyJSONWithoutIsSecret() throws {
        let json = """
        {"id":"11111111-1111-1111-1111-111111111111","name":"Email","text":"me@example.com"}
        """
        let snippet = try JSONDecoder().decode(Snippet.self, from: Data(json.utf8))
        XCTAssertFalse(snippet.isSecret)
        XCTAssertNil(snippet.shortcut)
        XCTAssertEqual(snippet.name, "Email")
        XCTAssertEqual(snippet.text, "me@example.com")
    }

    func testIsSecretRoundTrips() throws {
        let snippet = Snippet(name: "Token", text: "", isSecret: true)
        let data = try JSONEncoder().encode(snippet)
        XCTAssertEqual(try JSONDecoder().decode(Snippet.self, from: data), snippet)
    }

    func testInMemorySecretStoreRoundTrips() throws {
        let store = InMemorySecretStore()
        XCTAssertEqual(try store.read(), [:])
        let id = UUID()
        try store.write([id: "s3cret"])
        XCTAssertEqual(try store.read(), [id: "s3cret"])
        try store.write([:])
        XCTAssertEqual(try store.read(), [:])
    }
}
