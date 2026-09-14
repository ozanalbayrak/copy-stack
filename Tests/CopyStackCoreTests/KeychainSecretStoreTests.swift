import XCTest
@testable import CopyStackCore

/// Touches the real login Keychain, so it only runs when explicitly asked:
/// `COPYSTACK_KEYCHAIN_TESTS=1 swift test --filter KeychainSecretStoreTests`
/// It uses a throwaway account name and deletes the item at the end.
final class KeychainSecretStoreTests: XCTestCase {
    func testRoundTripUpdateAndDelete() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["COPYSTACK_KEYCHAIN_TESTS"] == "1",
                          "set COPYSTACK_KEYCHAIN_TESTS=1 to run against the login Keychain")
        let store = KeychainSecretStore(account: "secrets-test-\(UUID().uuidString)")
        // A failed assertion must not leave the throwaway item behind.
        addTeardownBlock { try? store.write([:]) }
        XCTAssertEqual(try store.read(), [:])

        let id = UUID()
        try store.write([id: "s3cret"])
        XCTAssertEqual(try store.read(), [id: "s3cret"])

        try store.write([id: "changed"])
        XCTAssertEqual(try store.read(), [id: "changed"])

        try store.write([:])
        XCTAssertEqual(try store.read(), [:])
    }
}
