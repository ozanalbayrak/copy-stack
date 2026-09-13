import XCTest
@testable import CopyStackCore

final class SnippetStoreTests: XCTestCase {
    private var directory: URL!
    private var fileURL: URL!
    private var secrets: InMemorySecretStore!

    private func makeStore() -> SnippetStore {
        SnippetStore(fileURL: fileURL, secretStore: secrets)
    }

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CopyStackTests-\(UUID().uuidString)", isDirectory: true)
        fileURL = directory.appendingPathComponent("snippets.json")
        secrets = InMemorySecretStore()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: Persistence

    func testStartsEmptyWhenFileIsMissing() {
        XCTAssertEqual(makeStore().snippets, [])
    }

    func testAddPersistsAndReloads() {
        let store = makeStore()
        let added = store.add(name: "Email", text: "me@example.com")
        XCTAssertEqual(store.snippets, [added])
        XCTAssertEqual(makeStore().snippets, [added])
    }

    func testAddUsesDefaultNameAndEmptyText() {
        let snippet = makeStore().add()
        XCTAssertEqual(snippet.name, "New Snippet")
        XCTAssertEqual(snippet.text, "")
        XCTAssertNil(snippet.shortcut)
    }

    func testUpdateReplacesMatchingSnippetAndPersists() {
        let store = makeStore()
        var snippet = store.add(name: "Email", text: "old")
        snippet.text = "new"
        snippet.shortcut = KeyCombo(keyCode: 14, modifiers: KeyCombo.Modifier.control)
        store.update(snippet)
        XCTAssertEqual(store.snippets, [snippet])
        XCTAssertEqual(makeStore().snippets, [snippet])
    }

    func testUpdateIgnoresUnknownID() {
        let store = makeStore()
        store.add(name: "Email")
        store.update(Snippet(name: "Ghost"))
        XCTAssertEqual(store.snippets.map(\.name), ["Email"])
    }

    func testRemoveDeletesSnippetAndPersists() {
        let store = makeStore()
        let email = store.add(name: "Email")
        let slack = store.add(name: "Slack")
        store.remove(id: email.id)
        XCTAssertEqual(store.snippets, [slack])
        XCTAssertEqual(makeStore().snippets, [slack])
    }

    func testStartsEmptyWhenFileIsCorrupt() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: fileURL)
        XCTAssertEqual(makeStore().snippets, [])
    }

    func testSavedFileIsPrettyPrintedJSON() throws {
        makeStore().add(name: "Email", text: "me@example.com")
        let contents = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertTrue(contents.contains("\n"), "expected multi-line output, got: \(contents)")
        XCTAssertTrue(contents.contains("\"Email\""))
    }

    func testSavedFileIsOwnerReadWriteOnly() throws {
        makeStore().add(name: "Email")
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        XCTAssertEqual(attributes[.posixPermissions] as? Int, 0o600)
    }

    // MARK: Shortcut validation

    private let combo = KeyCombo(keyCode: 14, modifiers: KeyCombo.Modifier.control | KeyCombo.Modifier.option)

    private func makeStoreWithEmailBoundToCombo() -> (SnippetStore, Snippet) {
        let store = makeStore()
        var email = store.add(name: "Email")
        email.shortcut = combo
        store.update(email)
        return (store, email)
    }

    func testConflictFindsSnippetOwningCombo() {
        let (store, email) = makeStoreWithEmailBoundToCombo()
        let slack = store.add(name: "Slack")
        XCTAssertEqual(store.conflict(for: combo, excluding: slack.id)?.id, email.id)
    }

    func testConflictIgnoresExcludedSnippet() {
        let (store, email) = makeStoreWithEmailBoundToCombo()
        XCTAssertNil(store.conflict(for: combo, excluding: email.id))
    }

    func testConflictIsNilWhenComboIsUnused() {
        let (store, _) = makeStoreWithEmailBoundToCombo()
        let other = KeyCombo(keyCode: 1, modifiers: KeyCombo.Modifier.command)
        XCTAssertNil(store.conflict(for: other))
    }

    func testValidateRejectsComboWithoutModifiers() {
        let store = makeStore()
        let snippet = store.add()
        XCTAssertThrowsError(try store.validate(KeyCombo(keyCode: 14, modifiers: 0), for: snippet.id)) { error in
            XCTAssertEqual(error as? SnippetStore.ValidationError, .missingModifier)
        }
    }

    func testValidateRejectsShiftOnlyCombo() {
        let store = makeStore()
        let snippet = store.add()
        XCTAssertThrowsError(try store.validate(KeyCombo(keyCode: 14, modifiers: KeyCombo.Modifier.shift), for: snippet.id)) { error in
            XCTAssertEqual(error as? SnippetStore.ValidationError, .missingModifier)
        }
    }

    func testValidateRejectsCommandV() {
        let store = makeStore()
        let snippet = store.add()
        XCTAssertThrowsError(try store.validate(KeyCombo(keyCode: 9, modifiers: KeyCombo.Modifier.command), for: snippet.id)) { error in
            XCTAssertEqual(error as? SnippetStore.ValidationError, .reserved)
        }
    }

    func testValidateAcceptsCommandShiftV() {
        let store = makeStore()
        let snippet = store.add()
        let commandShiftV = KeyCombo(keyCode: 9, modifiers: KeyCombo.Modifier.command | KeyCombo.Modifier.shift)
        XCTAssertNoThrow(try store.validate(commandShiftV, for: snippet.id))
    }

    func testValidateRejectsComboOwnedByAnotherSnippet() {
        let (store, _) = makeStoreWithEmailBoundToCombo()
        let slack = store.add(name: "Slack")
        XCTAssertThrowsError(try store.validate(combo, for: slack.id)) { error in
            XCTAssertEqual(error as? SnippetStore.ValidationError, .shortcutConflict(ownerName: "Email"))
        }
    }

    func testValidateAcceptsComboOwnedByTheSameSnippet() {
        let (store, email) = makeStoreWithEmailBoundToCombo()
        XCTAssertNoThrow(try store.validate(combo, for: email.id))
    }

    func testValidateAcceptsUnusedComboWithModifier() {
        let store = makeStore()
        let snippet = store.add()
        XCTAssertNoThrow(try store.validate(KeyCombo(keyCode: 1, modifiers: KeyCombo.Modifier.command), for: snippet.id))
    }

    // MARK: Secrets

    private final class FailingSecretStore: SecretStore {
        func read() throws -> [UUID: String] { throw SecretStoreError.accessDenied }
        func write(_ secrets: [UUID: String]) throws { throw SecretStoreError.accessDenied }
    }

    /// Wraps an `InMemorySecretStore`; rejects exactly one write when asked.
    private final class FlakySecretStore: SecretStore {
        let inner: InMemorySecretStore
        var failNextWrite = false

        init(inner: InMemorySecretStore) {
            self.inner = inner
        }

        func read() throws -> [UUID: String] { try inner.read() }

        func write(_ secrets: [UUID: String]) throws {
            if failNextWrite {
                failNextWrite = false
                throw SecretStoreError.accessDenied
            }
            try inner.write(secrets)
        }
    }

    private func fileContents() throws -> String {
        try String(contentsOf: fileURL, encoding: .utf8)
    }

    func testSetSecretMovesTextOutOfTheFile() throws {
        let store = makeStore()
        let token = store.add(name: "Token", text: "s3cret")

        try store.setSecret(true, for: token.id)

        XCTAssertEqual(store.snippets[0].text, "")
        XCTAssertTrue(store.snippets[0].isSecret)
        XCTAssertFalse(try fileContents().contains("s3cret"))
        XCTAssertEqual(secrets.secrets, [token.id: "s3cret"])
        XCTAssertEqual(try store.text(for: token.id), "s3cret")

        let reloaded = makeStore()
        XCTAssertEqual(reloaded.snippets[0].text, "")
        XCTAssertTrue(reloaded.snippets[0].isSecret)
        XCTAssertEqual(try reloaded.text(for: token.id), "s3cret")
    }

    func testSetSecretFalseMovesTextBackIntoTheFile() throws {
        let store = makeStore()
        let token = store.add(name: "Token", text: "s3cret")
        try store.setSecret(true, for: token.id)

        try store.setSecret(false, for: token.id)

        XCTAssertEqual(store.snippets[0].text, "s3cret")
        XCTAssertFalse(store.snippets[0].isSecret)
        XCTAssertTrue(try fileContents().contains("s3cret"))
        XCTAssertEqual(secrets.secrets, [:])
    }

    func testSetSecretIsIdempotent() throws {
        let store = makeStore()
        let token = store.add(name: "Token", text: "s3cret")
        try store.setSecret(true, for: token.id)
        try store.setSecret(true, for: token.id)
        XCTAssertEqual(secrets.secrets, [token.id: "s3cret"])
        try store.setSecret(false, for: token.id)
        try store.setSecret(false, for: token.id)
        XCTAssertEqual(store.snippets[0].text, "s3cret")
    }

    func testTextForNormalSnippetComesFromTheFile() throws {
        let store = makeStore()
        let email = store.add(name: "Email", text: "me@example.com")
        XCTAssertEqual(try store.text(for: email.id), "me@example.com")
        XCTAssertEqual(secrets.secrets, [:])
    }

    func testTextForUnknownIDThrows() {
        let store = makeStore()
        XCTAssertThrowsError(try store.text(for: UUID())) { error in
            XCTAssertEqual(error as? SnippetStore.SnippetError, .unknownSnippet)
        }
    }

    func testSetTextOnSecretSnippetWritesOnlyTheSecretStore() throws {
        let store = makeStore()
        let token = store.add(name: "Token", text: "old")
        try store.setSecret(true, for: token.id)

        try store.setText("new", for: token.id)

        XCTAssertEqual(secrets.secrets, [token.id: "new"])
        XCTAssertEqual(store.snippets[0].text, "")
        XCTAssertFalse(try fileContents().contains("new"))
    }

    func testSetTextOnNormalSnippetWritesTheFile() throws {
        let store = makeStore()
        let email = store.add(name: "Email", text: "old")
        try store.setText("new", for: email.id)
        XCTAssertEqual(store.snippets[0].text, "new")
        XCTAssertTrue(try fileContents().contains("new"))
        XCTAssertEqual(secrets.secrets, [:])
    }

    func testUpdateNeverWritesSecretTextOrFlipsTheFlag() throws {
        let store = makeStore()
        let token = store.add(name: "Token", text: "s3cret")
        try store.setSecret(true, for: token.id)

        var edited = store.snippets[0]
        edited.name = "API token"
        edited.text = "leak"
        edited.isSecret = false
        store.update(edited)

        XCTAssertEqual(store.snippets[0].name, "API token")
        XCTAssertEqual(store.snippets[0].text, "")
        XCTAssertTrue(store.snippets[0].isSecret)
        XCTAssertFalse(try fileContents().contains("leak"))
        XCTAssertEqual(secrets.secrets, [token.id: "s3cret"])
    }

    func testUpdateCannotMakeANormalSnippetSecret() throws {
        let store = makeStore()
        var email = store.add(name: "Email", text: "me@example.com")
        email.isSecret = true
        store.update(email)
        XCTAssertFalse(store.snippets[0].isSecret)
        XCTAssertEqual(store.snippets[0].text, "me@example.com")
    }

    func testRemoveDeletesTheSecretEntry() throws {
        let store = makeStore()
        let token = store.add(name: "Token", text: "s3cret")
        try store.setSecret(true, for: token.id)
        store.remove(id: token.id)
        XCTAssertEqual(store.snippets, [])
        XCTAssertEqual(secrets.secrets, [:])
    }

    func testSetSecretTrueLeavesEverythingUnchangedWhenTheStoreFails() throws {
        let store = SnippetStore(fileURL: fileURL, secretStore: FailingSecretStore())
        let token = store.add(name: "Token", text: "s3cret")

        XCTAssertThrowsError(try store.setSecret(true, for: token.id)) { error in
            XCTAssertEqual(error as? SecretStoreError, .accessDenied)
        }

        XCTAssertEqual(store.snippets[0].text, "s3cret")
        XCTAssertFalse(store.snippets[0].isSecret)
        XCTAssertTrue(try fileContents().contains("s3cret"))
    }

    func testOrphanedSecretIsDroppedOnNextSuccessfulWrite() throws {
        let flaky = FlakySecretStore(inner: secrets)
        let store = SnippetStore(fileURL: fileURL, secretStore: flaky)
        let first = store.add(name: "First", text: "one")
        let second = store.add(name: "Second", text: "two")
        try store.setSecret(true, for: first.id)
        try store.setSecret(true, for: second.id)

        flaky.failNextWrite = true
        store.remove(id: first.id)
        XCTAssertEqual(secrets.secrets[first.id], "one", "the denied removal leaves the entry behind")

        try store.setText("changed", for: second.id)

        XCTAssertEqual(secrets.secrets, [second.id: "changed"])
    }
}
