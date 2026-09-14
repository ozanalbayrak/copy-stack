# Secret Snippets and Launch at Login Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the user mark individual snippets as secret so their text lives in the login Keychain instead of `snippets.json`, keep clipboard managers from recording CopyStack's pastes, tighten the file's permissions, and add a "Launch at login" toggle.

**Architecture:** `CopyStackCore` gains a `SecretStore` protocol (Keychain-backed in production, in-memory in tests) and `SnippetStore` learns to route text to it for snippets flagged `isSecret`; the in-memory `Snippet` values never hold secret text. The app resolves text through `SnippetStore.text(for:)` right before pasting, marks the pasteboard with the nspasteboard.org "concealed"/"transient" types, and wraps `SMAppService` in a small `LoginItemManager` surfaced in the Settings sidebar.

**Tech Stack:** Swift 5 language mode on the Swift 6.3 toolchain, Foundation + Security (Core), SwiftUI + AppKit + ServiceManagement (app), XCTest.

**Spec:** `docs/superpowers/specs/2026-09-13-secure-snippets-and-login-item-design.md` (builds on `docs/superpowers/specs/2026-09-13-copy-stack-design.md`)

## Global Constraints

- Deployment target stays macOS 14. No third-party dependencies.
- `CopyStackCore` must not import AppKit or Carbon (`Foundation`, `os`, `Security` are fine).
- Everything in the repo — code, comments, docs, commit messages, UI strings — is English.
- Keychain layout: one `kSecClassGenericPassword` item, service `com.ozanalbayrak.CopyStack`, account `secrets`, value = JSON object keyed by snippet UUID string, `kSecAttrSynchronizable` false.
- The Keychain is never read at launch; only on paste or "Reveal".
- `Snippet.text` is always `""` for a snippet whose `isSecret` is true, both in memory and on disk.
- Every paste marks the pasteboard with `org.nspasteboard.ConcealedType` and `org.nspasteboard.TransientType`.
- `snippets.json` is written with POSIX mode `0600`.
- Existing `snippets.json` files (no `isSecret` key) must load unchanged with `isSecret == false`.
- Unit tests must never touch the real Keychain; the one Keychain integration test is skipped unless `COPYSTACK_KEYCHAIN_TESTS=1`.
- Logger subsystem: `com.ozanalbayrak.CopyStack`.
- Run all commands from the repo root: `/Users/ozanalbayrak/conductor/workspaces/copy-stack/athens`.

## File Map

| Path | Responsibility |
|---|---|
| `Sources/CopyStackCore/Snippet.swift` | Add `isSecret` with backward-compatible decoding. |
| `Sources/CopyStackCore/SecretStore.swift` | `SecretStore` protocol, `SecretStoreError`, `InMemorySecretStore`. |
| `Sources/CopyStackCore/KeychainSecretStore.swift` | Keychain-backed `SecretStore` (one generic-password item). |
| `Sources/CopyStackCore/SnippetStore.swift` | Route secret text to the `SecretStore`; `text(for:)`, `setText`, `setSecret`; `0600`. |
| `Sources/CopyStack/Paster.swift` | Concealed/transient pasteboard markers. |
| `Sources/CopyStack/CopyStackApp.swift` | `AppDelegate.paste(_:)` resolving text; `LoginItemManager` ownership. |
| `Sources/CopyStack/MenuBarView.swift` | Menu rows call `paste(snippet)`. |
| `Sources/CopyStack/SettingsView.swift` | "Store in Keychain" toggle + masked/reveal text area; "Launch at login" toggle. |
| `Sources/CopyStack/LoginItemManager.swift` | `SMAppService.mainApp` wrapper. |
| `Tests/CopyStackCoreTests/SnippetTests.swift` | `isSecret` decoding, in-memory store. |
| `Tests/CopyStackCoreTests/KeychainSecretStoreTests.swift` | Opt-in Keychain integration test. |
| `Tests/CopyStackCoreTests/SnippetStoreTests.swift` | Secret routing, permissions. |
| `README.md`, `Resources/Info.plist` | Docs and version 0.2.0. |

---

### Task 1: `Snippet.isSecret`, `SecretStore` protocol, `InMemorySecretStore`

**Files:**
- Modify: `Sources/CopyStackCore/Snippet.swift`
- Create: `Sources/CopyStackCore/SecretStore.swift`
- Test: `Tests/CopyStackCoreTests/SnippetTests.swift`

**Interfaces:**
- Produces:
  - `Snippet.isSecret: Bool`; `Snippet.init(id:name:text:shortcut:isSecret:)` with `isSecret` defaulting to `false`.
  - `public protocol SecretStore { func read() throws -> [UUID: String]; func write(_ secrets: [UUID: String]) throws }`
  - `public enum SecretStoreError: Error, Equatable { case accessDenied; case failure(OSStatus) }`
  - `public final class InMemorySecretStore: SecretStore { public private(set) var secrets: [UUID: String]; public init(secrets: [UUID: String] = [:]) }`

- [ ] **Step 1: Write the failing tests**

`Tests/CopyStackCoreTests/SnippetTests.swift`:

```swift
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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter SnippetTests 2>&1 | tail -20`
Expected: compile error — `extra argument 'isSecret' in call` / `cannot find 'InMemorySecretStore' in scope`.

- [ ] **Step 3: Add `isSecret` to `Snippet`**

Replace `Sources/CopyStackCore/Snippet.swift` with:

```swift
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
```

(`encode(to:)` stays synthesized; defining `init(from:)` alone doesn't disable it.)

- [ ] **Step 4: Create `SecretStore.swift`**

`Sources/CopyStackCore/SecretStore.swift`:

```swift
import Foundation

/// Where secret snippet text lives. Implementations hold every secret in one
/// place so a single read serves all of them.
public protocol SecretStore {
    /// All stored secrets keyed by snippet id. Empty when nothing has been stored yet.
    func read() throws -> [UUID: String]
    /// Replaces all stored secrets.
    func write(_ secrets: [UUID: String]) throws
}

public enum SecretStoreError: Error, Equatable {
    /// The user denied the Keychain prompt, or the keychain is locked.
    case accessDenied
    /// Any other Keychain failure, with its status code.
    case failure(OSStatus)
}

/// Dictionary-backed store for tests and previews.
public final class InMemorySecretStore: SecretStore {
    public private(set) var secrets: [UUID: String]

    public init(secrets: [UUID: String] = [:]) {
        self.secrets = secrets
    }

    public func read() throws -> [UUID: String] {
        secrets
    }

    public func write(_ secrets: [UUID: String]) throws {
        self.secrets = secrets
    }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `swift test 2>&1 | grep -E "Executed|error:" | tail -3`
Expected: `Executed 27 tests, with 0 failures` (24 existing + 3 new), no errors.

- [ ] **Step 6: Commit**

```bash
git add Sources/CopyStackCore/Snippet.swift Sources/CopyStackCore/SecretStore.swift Tests/CopyStackCoreTests/SnippetTests.swift
git commit -m "Add Snippet.isSecret and the SecretStore protocol"
```

---

### Task 2: `KeychainSecretStore`

**Files:**
- Create: `Sources/CopyStackCore/KeychainSecretStore.swift`
- Test: `Tests/CopyStackCoreTests/KeychainSecretStoreTests.swift`

**Interfaces:**
- Consumes: `SecretStore`, `SecretStoreError` from Task 1.
- Produces: `public final class KeychainSecretStore: SecretStore { public static let service: String; public static let defaultAccount: String; public init(account: String = KeychainSecretStore.defaultAccount) }`

- [ ] **Step 1: Write the opt-in integration test**

`Tests/CopyStackCoreTests/KeychainSecretStoreTests.swift`:

```swift
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
```

- [ ] **Step 2: Run it to verify it fails**

Run: `COPYSTACK_KEYCHAIN_TESTS=1 swift test --filter KeychainSecretStoreTests 2>&1 | tail -20`
Expected: compile error — `cannot find 'KeychainSecretStore' in scope`.

- [ ] **Step 3: Implement `KeychainSecretStore`**

`Sources/CopyStackCore/KeychainSecretStore.swift`:

```swift
import Foundation
import Security

/// Keeps all secrets in one generic-password item in the login Keychain.
///
/// One item rather than one per snippet: Keychain access grants are per item
/// and per code signature, and ad-hoc-signed builds change signature on every
/// update. One item means the user is asked once per update, not once per
/// secret snippet.
public final class KeychainSecretStore: SecretStore {
    public static let service = "com.ozanalbayrak.CopyStack"
    public static let defaultAccount = "secrets"

    private let account: String

    public init(account: String = KeychainSecretStore.defaultAccount) {
        self.account = account
    }

    public func read() throws -> [UUID: String] {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data else { return [:] }
            return try Self.decode(data)
        case errSecItemNotFound:
            return [:]
        default:
            throw Self.error(for: status)
        }
    }

    public func write(_ secrets: [UUID: String]) throws {
        if secrets.isEmpty {
            let status = SecItemDelete(baseQuery as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw Self.error(for: status)
            }
            return
        }
        let data = try Self.encode(secrets)
        let update: [String: Any] = [kSecValueData as String: data]
        var status = SecItemUpdate(baseQuery as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var attributes = baseQuery
            attributes[kSecValueData as String] = data
            attributes[kSecAttrLabel as String] = "CopyStack secret snippets"
            status = SecItemAdd(attributes as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw Self.error(for: status) }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: false,
        ]
    }

    private static func error(for status: OSStatus) -> SecretStoreError {
        switch status {
        case errSecUserCanceled, errSecAuthFailed, errSecInteractionNotAllowed:
            return .accessDenied
        default:
            return .failure(status)
        }
    }

    // Stored as a JSON object keyed by UUID string; `[UUID: String]` itself
    // would encode as a flat array.
    private static func encode(_ secrets: [UUID: String]) throws -> Data {
        let keyed = Dictionary(uniqueKeysWithValues: secrets.map { ($0.key.uuidString, $0.value) })
        return try JSONEncoder().encode(keyed)
    }

    private static func decode(_ data: Data) throws -> [UUID: String] {
        let keyed = try JSONDecoder().decode([String: String].self, from: data)
        var result: [UUID: String] = [:]
        for (key, value) in keyed {
            if let id = UUID(uuidString: key) {
                result[id] = value
            }
        }
        return result
    }
}
```

- [ ] **Step 4: Run the integration test once against the real Keychain, then the full suite**

Run: `COPYSTACK_KEYCHAIN_TESTS=1 swift test --filter KeychainSecretStoreTests 2>&1 | grep -E "Executed|error:|failed" | tail -3`
Expected: `Executed 1 test, with 0 failures`. No Keychain dialog should appear (the test process created the item, so it may read it).

Run: `swift test 2>&1 | grep -E "Executed|skipped|error:" | tail -3`
Expected: `Executed 28 tests, with 1 test skipped and 0 failures` — the Keychain test is skipped without the env var.

Confirm nothing was left behind: `security find-generic-password -s com.ozanalbayrak.CopyStack 2>&1 | head -1`
Expected: `security: SecKeychainSearchCopyNext: The specified item could not be found in the keychain.` (unless the user already has real secrets — then the account must not start with `secrets-test-`).

- [ ] **Step 5: Commit**

```bash
git add Sources/CopyStackCore/KeychainSecretStore.swift Tests/CopyStackCoreTests/KeychainSecretStoreTests.swift
git commit -m "Add KeychainSecretStore backed by one generic-password item"
```

---

### Task 3: `SnippetStore` secret routing

**Files:**
- Modify: `Sources/CopyStackCore/SnippetStore.swift`
- Test: `Tests/CopyStackCoreTests/SnippetStoreTests.swift`

**Interfaces:**
- Consumes: `SecretStore`, `SecretStoreError`, `InMemorySecretStore`, `KeychainSecretStore`, `Snippet.isSecret`.
- Produces:
  - `public init(fileURL: URL = SnippetStore.defaultFileURL, secretStore: SecretStore = KeychainSecretStore())`
  - `public enum SnippetStore.SnippetError: Error, Equatable { case unknownSnippet }`
  - `public func text(for id: Snippet.ID) throws -> String`
  - `public func setText(_ text: String, for id: Snippet.ID) throws`
  - `public func setSecret(_ isSecret: Bool, for id: Snippet.ID) throws`
  - `update(_:)` preserves the stored `isSecret` and forces `text = ""` for secret snippets; `remove(id:)` also drops the secret entry.

- [ ] **Step 1: Give the test file an in-memory secret store**

In `Tests/CopyStackCoreTests/SnippetStoreTests.swift`:

1. Add a property and a factory below `private var fileURL: URL!`:

```swift
    private var secrets: InMemorySecretStore!

    private func makeStore() -> SnippetStore {
        SnippetStore(fileURL: fileURL, secretStore: secrets)
    }
```

2. In `setUpWithError`, after `fileURL = …`, add `secrets = InMemorySecretStore()`.
3. Replace every `SnippetStore(fileURL: fileURL)` in the file with `makeStore()`:

```bash
sed -i '' 's/SnippetStore(fileURL: fileURL)/makeStore()/g' Tests/CopyStackCoreTests/SnippetStoreTests.swift
grep -c "makeStore()" Tests/CopyStackCoreTests/SnippetStoreTests.swift   # expect 18 (17 call sites + the definition)
```

- [ ] **Step 2: Append the failing secret-routing tests**

Add before the final closing brace of `SnippetStoreTests`:

```swift
    // MARK: Secrets

    private final class FailingSecretStore: SecretStore {
        func read() throws -> [UUID: String] { throw SecretStoreError.accessDenied }
        func write(_ secrets: [UUID: String]) throws { throw SecretStoreError.accessDenied }
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
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `swift test --filter SnippetStoreTests 2>&1 | tail -20`
Expected: compile error — `extra argument 'secretStore' in call`.

- [ ] **Step 4: Implement the routing in `SnippetStore`**

In `Sources/CopyStackCore/SnippetStore.swift`:

1. Replace the stored properties and initializer:

```swift
    @Published public private(set) var snippets: [Snippet]
    public let fileURL: URL
    private let secretStore: SecretStore

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
```

2. Replace `remove(id:)` and `update(_:)`:

```swift
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
```

3. Add a new section after `// MARK: Mutations` (before `// MARK: Shortcut validation`):

```swift
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
            try secretStore.write(secrets)
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
        if isSecret {
            // Secret store first: if it fails, nothing has changed.
            var secrets = try secretStore.read()
            secrets[id] = snippets[index].text
            try secretStore.write(secrets)
            snippets[index].text = ""
            snippets[index].isSecret = true
            save()
        } else {
            let text = try secretStore.read()[id] ?? ""
            // JSON first: the text is safe before the secret entry goes away.
            snippets[index].text = text
            snippets[index].isSecret = false
            save()
            removeSecret(for: id)
        }
    }

    /// Best-effort removal; the caller has already persisted the state that
    /// matters, so a failure here is only logged.
    private func removeSecret(for id: Snippet.ID) {
        do {
            var secrets = try secretStore.read()
            guard secrets.removeValue(forKey: id) != nil else { return }
            try secretStore.write(secrets)
        } catch {
            Self.logger.error("Failed to remove secret for \(id.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `swift test 2>&1 | grep -E "Executed|error:" | tail -3`
Expected: `Executed 39 tests, with 1 test skipped and 0 failures` (28 + 11 new).

- [ ] **Step 6: Commit**

```bash
git add Sources/CopyStackCore/SnippetStore.swift Tests/CopyStackCoreTests/SnippetStoreTests.swift
git commit -m "Route secret snippet text through the SecretStore"
```

---

### Task 4: `snippets.json` is written with mode 0600

**Files:**
- Modify: `Sources/CopyStackCore/SnippetStore.swift` (`save()`)
- Test: `Tests/CopyStackCoreTests/SnippetStoreTests.swift`

**Interfaces:**
- Consumes: `SnippetStore.save()` from Task 3.
- Produces: nothing new; behaviour only.

- [ ] **Step 1: Write the failing test**

Append inside `SnippetStoreTests`, after the `// MARK: Persistence` tests:

```swift
    func testSavedFileIsOwnerReadWriteOnly() throws {
        makeStore().add(name: "Email")
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        XCTAssertEqual(attributes[.posixPermissions] as? Int, 0o600)
    }
```

- [ ] **Step 2: Run it to verify it fails**

Run: `swift test --filter SnippetStoreTests/testSavedFileIsOwnerReadWriteOnly 2>&1 | grep -E "XCTAssert|Executed" | tail -3`
Expected: FAIL — `XCTAssertEqual failed: ("Optional(420)") is not equal to ("Optional(384)")` (0o644 vs 0o600).

- [ ] **Step 3: Set the permissions after the atomic write**

In `save()` in `Sources/CopyStackCore/SnippetStore.swift`, replace the body with:

```swift
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
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test 2>&1 | grep -E "Executed|error:" | tail -3`
Expected: `Executed 40 tests, with 1 test skipped and 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add Sources/CopyStackCore/SnippetStore.swift Tests/CopyStackCoreTests/SnippetStoreTests.swift
git commit -m "Write snippets.json with owner-only permissions"
```

---

### Task 5: Concealed pasteboard markers and text resolution before pasting

**Files:**
- Modify: `Sources/CopyStack/Paster.swift`
- Modify: `Sources/CopyStack/CopyStackApp.swift`
- Modify: `Sources/CopyStack/MenuBarView.swift`

**Interfaces:**
- Consumes: `SnippetStore.text(for:)` (Task 3), `Paster.paste(_ text: String)`, `HotKeyManager.init(store:onTrigger:)`.
- Produces:
  - `AppDelegate.paste(_ snippet: Snippet)`
  - `MenuBarView(store: SnippetStore, paste: @escaping (Snippet) -> Void)` — replaces the `paster:` parameter.

- [ ] **Step 1: Mark every paste as concealed and transient**

In `Sources/CopyStack/Paster.swift`:

1. Below `private static let vKeyCode: CGKeyCode = 9 // kVK_ANSI_V` add:

```swift
    /// Markers from nspasteboard.org. Clipboard managers (Maccy, Raycast,
    /// Paste, …) skip items that carry them, so a secret never lands in
    /// someone's clipboard history. Everything CopyStack writes is transient.
    private static let concealedType = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
    private static let transientType = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")
```

2. In `drain()`, replace

```swift
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        postCommandV()
```

with

```swift
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        pasteboard.setData(Data(), forType: Self.concealedType)
        pasteboard.setData(Data(), forType: Self.transientType)
        postCommandV()
```

- [ ] **Step 2: Resolve text in `AppDelegate`**

Replace `Sources/CopyStack/CopyStackApp.swift` with:

```swift
import AppKit
import CopyStackCore
import os
import SwiftUI

@main
struct CopyStackApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("CopyStack", systemImage: "doc.on.clipboard") {
            MenuBarView(store: appDelegate.store, paste: appDelegate.paste)
        }
        // A `Settings` scene is never auto-presented; a lone `Window` scene
        // would open itself at launch (and be restored on relaunch).
        Settings {
            SettingsView(store: appDelegate.store, hotKeyManager: appDelegate.hotKeyManager)
        }
    }
}

/// Owns the long-lived objects. SwiftUI scenes read them through the adaptor.
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = SnippetStore()
    let paster = Paster()
    lazy var hotKeyManager = HotKeyManager(store: store) { [weak self] snippet in
        self?.paste(snippet)
    }

    private static let logger = Logger(subsystem: "com.ozanalbayrak.CopyStack", category: "AppDelegate")

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu bar only: no Dock icon, no app switcher entry. Info.plist sets
        // LSUIElement for the bundle; this covers `swift run`.
        NSApp.setActivationPolicy(.accessory)
        _ = hotKeyManager // register shortcuts at launch
        AccessibilityGate.requestIfNeeded()
    }

    /// Resolves the snippet's text (Keychain for secret ones) and pastes it.
    /// A Keychain failure is logged and nothing is pasted.
    func paste(_ snippet: Snippet) {
        do {
            paster.paste(try store.text(for: snippet.id))
        } catch {
            Self.logger.error("Could not read text for \(snippet.name, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }
}
```

- [ ] **Step 3: Menu rows call `paste(snippet)`**

In `Sources/CopyStack/MenuBarView.swift`:

- Replace `let paster: Paster` with `let paste: (Snippet) -> Void`.
- Replace the row button body `paster.paste(snippet.text)` with `paste(snippet)`.

- [ ] **Step 4: Build, test, bundle, smoke-test**

Run: `swift build 2>&1 | grep -E "warning|error|Compiling|Build complete" | tail -3`
Expected: `Build complete!`, no warnings.

Run: `swift test 2>&1 | grep -E "Executed|error:" | tail -1`
Expected: `Executed 40 tests, with 1 test skipped and 0 failures`.

Run: `Scripts/build-app.sh && open build/CopyStack.app && sleep 3 && pgrep -x CopyStack && pkill -x CopyStack`
Expected: `Built build/CopyStack.app`, a pid, then the app quits.

Needs human verification: with Maccy (or Raycast clipboard history) running, paste a snippet from the menu → the text does not appear in the clipboard history; a normal ⌘C afterwards still does.

- [ ] **Step 5: Commit**

```bash
git add Sources/CopyStack/Paster.swift Sources/CopyStack/CopyStackApp.swift Sources/CopyStack/MenuBarView.swift
git commit -m "Mark pastes as concealed and resolve secret text before pasting"
```

---

### Task 6: "Store in Keychain" toggle and masked text in the editor

**Files:**
- Modify: `Sources/CopyStack/SettingsView.swift` (`SnippetEditor` only)

**Interfaces:**
- Consumes: `SnippetStore.setSecret(_:for:)`, `setText(_:for:)`, `text(for:)`, `SecretStoreError`, `Snippet.isSecret`.
- Produces: `SnippetEditor(snippet:store:hotKeyManager:)` keeps its signature (custom init added).

- [ ] **Step 1: Replace `SnippetEditor`**

In `Sources/CopyStack/SettingsView.swift`, replace the whole `struct SnippetEditor` with:

```swift
/// Edits one snippet. Every change goes straight to the store; there is no Save button.
struct SnippetEditor: View {
    @Binding var snippet: Snippet
    @ObservedObject var store: SnippetStore
    let hotKeyManager: HotKeyManager

    @State private var shortcutError: String?
    /// Local copy of the toggle so a failed `setSecret` can revert it.
    @State private var isSecret: Bool
    @State private var secretError: String?
    /// Secret text while revealed; `nil` means masked.
    @State private var revealedText: String?

    init(snippet: Binding<Snippet>, store: SnippetStore, hotKeyManager: HotKeyManager) {
        _snippet = snippet
        _store = ObservedObject(wrappedValue: store)
        self.hotKeyManager = hotKeyManager
        _isSecret = State(initialValue: snippet.wrappedValue.isSecret)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LabeledContent("Name") {
                TextField("Name", text: $snippet.name)
                    .textFieldStyle(.roundedBorder)
            }
            LabeledContent("Shortcut") {
                VStack(alignment: .leading, spacing: 4) {
                    ShortcutRecorderView(
                        combo: snippet.shortcut,
                        onRecordingChanged: { isRecording in
                            hotKeyManager.isEnabled = !isRecording
                        },
                        onRecord: { combo in
                            do {
                                try store.validate(combo, for: snippet.id)
                                snippet.shortcut = combo
                                shortcutError = nil
                                return true
                            } catch SnippetStore.ValidationError.shortcutConflict(let ownerName) {
                                shortcutError = "Already used by “\(ownerName)”"
                            } catch SnippetStore.ValidationError.reserved {
                                shortcutError = "⌘V is reserved — CopyStack uses it to paste"
                            } catch SnippetStore.ValidationError.missingModifier {
                                shortcutError = "Add ⌘, ⌃ or ⌥ — ⇧ alone can't be a global shortcut"
                            } catch {
                                shortcutError = error.localizedDescription
                            }
                            return false
                        },
                        onClear: {
                            snippet.shortcut = nil
                            shortcutError = nil
                        })
                    .fixedSize()
                    if let shortcutError {
                        Text(shortcutError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            LabeledContent("Storage") {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Store in Keychain", isOn: $isSecret)
                        .onChange(of: isSecret) { _, newValue in
                            // Also fires when a failed attempt reverts the
                            // toggle; the guard makes that a no-op.
                            guard newValue != snippet.isSecret else { return }
                            do {
                                try store.setSecret(newValue, for: snippet.id)
                                secretError = nil
                                revealedText = nil
                            } catch {
                                isSecret = snippet.isSecret
                                secretError = Self.message(for: error)
                            }
                        }
                    if let secretError {
                        Text(secretError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            Text("Text")
                .font(.headline)
            if snippet.isSecret {
                secretTextArea
            } else {
                TextEditor(text: $snippet.text)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .border(Color(nsColor: .separatorColor))
            }
        }
        .padding()
    }

    @ViewBuilder
    private var secretTextArea: some View {
        if let revealedText {
            VStack(alignment: .leading, spacing: 6) {
                TextEditor(text: Binding(
                    get: { revealedText },
                    set: { newValue in
                        self.revealedText = newValue
                        do {
                            try store.setText(newValue, for: snippet.id)
                            secretError = nil
                        } catch {
                            secretError = Self.message(for: error)
                        }
                    }))
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .border(Color(nsColor: .separatorColor))
                Button("Hide") {
                    self.revealedText = nil
                }
            }
        } else {
            VStack(spacing: 8) {
                Image(systemName: "lock.fill")
                    .font(.title)
                    .foregroundStyle(.secondary)
                Text("Hidden — stored in Keychain")
                    .foregroundStyle(.secondary)
                Button("Reveal") {
                    do {
                        revealedText = try store.text(for: snippet.id)
                        secretError = nil
                    } catch {
                        secretError = Self.message(for: error)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .border(Color(nsColor: .separatorColor))
        }
    }

    private static func message(for error: Error) -> String {
        switch error {
        case SecretStoreError.accessDenied:
            return "Keychain access was denied"
        case SecretStoreError.failure(let status):
            return "Keychain error \(status)"
        default:
            return error.localizedDescription
        }
    }
}
```

Notes for the implementer: every keystroke in the revealed editor does one Keychain read + write; secrets are short, so this is acceptable. `SettingsView` already applies `.id(id)` to `SnippetEditor`, so switching snippets re-runs `init` and resets `revealedText`.

- [ ] **Step 2: Build, test, bundle, smoke-test**

Run: `swift build 2>&1 | grep -E "warning|error|Build complete" | tail -3`
Expected: `Build complete!`, no warnings.

Run: `swift test 2>&1 | grep -E "Executed|error:" | tail -1`
Expected: `Executed 40 tests, with 1 test skipped and 0 failures`.

Run: `Scripts/build-app.sh && open build/CopyStack.app && sleep 3 && pgrep -x CopyStack && pkill -x CopyStack`
Expected: builds, launches, quits.

Needs human verification:
1. Select a snippet with text, turn "Store in Keychain" on → text area becomes the lock panel; `snippets.json` shows `"isSecret" : true` and `"text" : ""`; Keychain Access shows one item "CopyStack secret snippets".
2. Click Reveal → the text appears (macOS may ask for Keychain access once — Always Allow); edit it; Hide.
3. Press the snippet's shortcut in TextEdit → the edited text pastes.
4. Turn the toggle off → text is back in the editor and in the JSON file; the Keychain item is gone (or lacks that id).
5. Deny the Keychain prompt on Reveal → red "Keychain access was denied", panel stays masked.

- [ ] **Step 3: Commit**

```bash
git add Sources/CopyStack/SettingsView.swift
git commit -m "Add Store in Keychain toggle with masked secret text in the editor"
```

---

### Task 7: Launch at login

**Files:**
- Create: `Sources/CopyStack/LoginItemManager.swift`
- Modify: `Sources/CopyStack/CopyStackApp.swift`
- Modify: `Sources/CopyStack/SettingsView.swift` (`SettingsView` only)

**Interfaces:**
- Consumes: `AppDelegate`, `SettingsView(store:hotKeyManager:)`.
- Produces:
  - `final class LoginItemManager: ObservableObject { @Published private(set) var status: SMAppService.Status; var isEnabled: Bool; func refresh(); func setEnabled(_ enabled: Bool) throws; static func openSystemSettings() }`
  - `AppDelegate.loginItem: LoginItemManager`
  - `SettingsView(store:hotKeyManager:loginItem:)`

- [ ] **Step 1: Write `LoginItemManager`**

`Sources/CopyStack/LoginItemManager.swift`:

```swift
import Combine
import ServiceManagement

/// Wraps `SMAppService.mainApp` so the Settings window can show and change
/// whether CopyStack starts at login.
///
/// Only meaningful for the bundled app (`CopyStack.app`); `register()` throws
/// when run from a bare `swift run` binary.
final class LoginItemManager: ObservableObject {
    @Published private(set) var status: SMAppService.Status = SMAppService.mainApp.status

    var isEnabled: Bool {
        status == .enabled
    }

    func refresh() {
        status = SMAppService.mainApp.status
    }

    /// Registers or unregisters the login item, then re-reads the status.
    func setEnabled(_ enabled: Bool) throws {
        defer { refresh() }
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    static func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
```

- [ ] **Step 2: Own it in `AppDelegate` and pass it to Settings**

In `Sources/CopyStack/CopyStackApp.swift`:

- In `AppDelegate`, below `let paster = Paster()`, add `let loginItem = LoginItemManager()`.
- Change the `Settings` scene content to
  `SettingsView(store: appDelegate.store, hotKeyManager: appDelegate.hotKeyManager, loginItem: appDelegate.loginItem)`.

- [ ] **Step 3: Add the toggle to the sidebar**

In `Sources/CopyStack/SettingsView.swift`, inside `struct SettingsView`:

1. Below `let hotKeyManager: HotKeyManager` add:

```swift
    @ObservedObject var loginItem: LoginItemManager
```

2. Below `@State private var isTrusted = AccessibilityGate.isTrusted` add:

```swift
    @State private var loginItemError: String?
```

3. In the `.onReceive(... didBecomeActiveNotification ...)` closure, add `loginItem.refresh()` after `isTrusted = AccessibilityGate.isTrusted`.

4. In `sidebar`, after the `HStack { … } .buttonStyle(.borderless).padding(6)` block (the `+`/`−` row) and before the closing brace of the `VStack`, add:

```swift
            Divider()
            VStack(alignment: .leading, spacing: 4) {
                Toggle("Launch at login", isOn: Binding(
                    get: { loginItem.isEnabled },
                    set: { enabled in
                        do {
                            try loginItem.setEnabled(enabled)
                            loginItemError = nil
                        } catch {
                            loginItemError = error.localizedDescription
                        }
                    }))
                if loginItem.status == .requiresApproval {
                    HStack(spacing: 4) {
                        Text("Approve in System Settings → General → Login Items")
                        Button("Open") {
                            LoginItemManager.openSystemSettings()
                        }
                    }
                    .font(.caption)
                }
                if let loginItemError {
                    Text(loginItemError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .padding(8)
```

- [ ] **Step 4: Build, test, bundle, smoke-test**

Run: `swift build 2>&1 | grep -E "warning|error|Build complete" | tail -3`
Expected: `Build complete!`, no warnings.

Run: `swift test 2>&1 | grep -E "Executed|error:" | tail -1`
Expected: `Executed 40 tests, with 1 test skipped and 0 failures`.

Run: `Scripts/build-app.sh && open build/CopyStack.app && sleep 3 && pgrep -x CopyStack && pkill -x CopyStack`
Expected: builds, launches, quits.

Needs human verification (with the app installed in `/Applications`):
1. Settings → toggle "Launch at login" on → System Settings → General → Login Items lists CopyStack; macOS may show a "Background Items Added" notification.
2. Log out and back in → CopyStack's icon is in the menu bar.
3. Toggle off → the Login Items entry disappears.
4. Running from `build/` or `swift run`, toggling on shows a red error caption instead of silently failing.

- [ ] **Step 5: Commit**

```bash
git add Sources/CopyStack/LoginItemManager.swift Sources/CopyStack/CopyStackApp.swift Sources/CopyStack/SettingsView.swift
git commit -m "Add Launch at login toggle backed by SMAppService"
```

---

### Task 8: README and version

**Files:**
- Modify: `README.md`
- Modify: `Resources/Info.plist`

- [ ] **Step 1: Document the features**

In `README.md`:

1. In the `## Usage` section, after step 4 (`Focus any app and press the shortcut…`), add:

````markdown

### Secret snippets

Turn on **Store in Keychain** for a snippet that holds a token or a password.
Its text moves out of `snippets.json` into your login Keychain (one item named
"CopyStack secret snippets") and is only read when you paste it or click
**Reveal**. The first time after each update, macOS asks whether CopyStack may
use the item — choose **Always Allow**. (Releases are ad-hoc signed, so macOS
treats every update as a new app; a paid Developer ID would make this a
one-time prompt.)

Everything CopyStack pastes is marked as concealed and transient, so clipboard
managers such as Maccy, Raycast and Paste don't record it.

To remove the secrets entirely, delete the "CopyStack secret snippets" item in
Keychain Access; uninstalling (including `brew uninstall --zap`) leaves it in
place.

### Launch at login

Settings → **Launch at login**. This registers the installed `CopyStack.app`
with macOS (System Settings → General → Login Items); it does not work for
builds run from the repository.
````

2. Replace the six-item manual checklist under `## Development` with:

```markdown
1. Build, launch, grant Accessibility when prompted.
2. Add a snippet and record ⌃⌥E.
3. Focus TextEdit and press ⌃⌥E → the text appears.
4. Copy an image in Preview, press ⌃⌥E in TextEdit → the text appears, and
   ⌘V in Preview still pastes the image.
5. Try to record ⌃⌥E on a second snippet → rejected, naming the owner.
6. Clear the shortcut → the menu row loses its label and the hotkey no
   longer fires.
7. Turn on **Store in Keychain** for a snippet → `snippets.json` shows
   `"text" : ""` for it and Keychain Access shows "CopyStack secret snippets".
   Quit, relaunch, press its shortcut → one Keychain prompt, then the text
   pastes.
8. With Maccy or Raycast clipboard history running, paste any snippet → it
   does not show up in the history.
9. Turn **Store in Keychain** off → the text is back in `snippets.json`.
10. `ls -l ~/Library/Application\ Support/CopyStack/snippets.json` shows
    `-rw-------`.
11. Toggle **Launch at login** → CopyStack appears under System Settings →
    General → Login Items; log out and in → it is running.
```

3. Under `## Development`, after the `swift build` fenced block, add:

```markdown
`swift test` never touches your Keychain. To run the one Keychain integration
test against the login Keychain (it creates and deletes a throwaway item):

```bash
COPYSTACK_KEYCHAIN_TESTS=1 swift test --filter KeychainSecretStoreTests
```
```

4. In `## Roadmap`, remove the "Launch at login." bullet.

- [ ] **Step 2: Bump the default version**

In `Resources/Info.plist`, change `CFBundleShortVersionString` from `0.1.0` to `0.2.0` and `CFBundleVersion` from `1` to `2`.

- [ ] **Step 3: Verify**

Run: `plutil -lint Resources/Info.plist && grep -c '```' README.md`
Expected: `Resources/Info.plist: OK` and an even number.

Run: `swift test 2>&1 | grep -E "Executed|error:" | tail -1`
Expected: `Executed 40 tests, with 1 test skipped and 0 failures`.

- [ ] **Step 4: Commit**

```bash
git add README.md Resources/Info.plist
git commit -m "Document secret snippets and launch at login; bump version to 0.2.0"
```
