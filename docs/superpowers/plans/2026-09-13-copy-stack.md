# CopyStack Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A macOS menu bar app that stores named text snippets and pastes any of them into the frontmost app via a per-snippet global keyboard shortcut, with a Settings window to edit snippets and shortcuts.

**Architecture:** One Swift Package with a Foundation-only `CopyStackCore` library (models + JSON store, unit-tested) and a `CopyStack` executable (SwiftUI `MenuBarExtra` + `Window` scene, Carbon `RegisterEventHotKey` for global shortcuts, a `Paster` that borrows `NSPasteboard.general` for a ⌘V round-trip). A shell script assembles the `.app` bundle.

**Tech Stack:** Swift 5 language mode on the Swift 6.3 toolchain, SwiftUI + AppKit, Carbon.HIToolbox (hotkeys), ApplicationServices (Accessibility), XCTest, `swift build`/`swift test`, `codesign`.

**Spec:** `docs/superpowers/specs/2026-09-13-copy-stack-design.md`

## Global Constraints

- Deployment target: macOS 14.0 (`platforms: [.macOS(.v14)]`, `LSMinimumSystemVersion = 14.0`).
- No third-party dependencies.
- Everything in the repo — code, comments, docs, commit messages, UI strings — is English.
- `CopyStackCore` must not import AppKit or Carbon; it stores key codes and modifier masks as raw `UInt32`.
- Bundle identifier: `com.ozanalbayrak.CopyStack`. Logger subsystem: the same string.
- Snippets file: `~/Library/Application Support/CopyStack/snippets.json`, pretty-printed JSON, written atomically.
- A shortcut must have at least one of ⌃⌥⇧⌘; no two snippets may share a shortcut.
- The app is a menu bar accessory: `LSUIElement = true` and `NSApp.setActivationPolicy(.accessory)`.
- Run all commands from the repo root: `/Users/ozanalbayrak/conductor/workspaces/copy-stack/athens`.

## File Map

| Path | Responsibility |
|---|---|
| `Package.swift` | Package manifest: `CopyStackCore` library, `CopyStack` executable, `CopyStackCoreTests`. |
| `.gitignore` | Ignore `.build/`, `build/`, `.swiftpm/`, `.DS_Store`. |
| `Sources/CopyStackCore/KeyCombo.swift` | `KeyCombo` value type, Carbon modifier bit constants, `displayString`. |
| `Sources/CopyStackCore/Snippet.swift` | `Snippet` value type. |
| `Sources/CopyStackCore/SnippetStore.swift` | Observable list of snippets with JSON persistence and shortcut validation. |
| `Sources/CopyStack/CopyStackApp.swift` | `@main` SwiftUI app, `AppDelegate` owning store/paster/hotkeys, scenes. |
| `Sources/CopyStack/MenuBarView.swift` | Menu bar dropdown content. |
| `Sources/CopyStack/AccessibilityGate.swift` | Accessibility permission check/prompt/open-settings. |
| `Sources/CopyStack/Paster.swift` | Pasteboard snapshot → write → ⌘V → restore, queued. |
| `Sources/CopyStack/HotKeyManager.swift` | Carbon hotkey registration mirroring the store. |
| `Sources/CopyStack/SettingsView.swift` | Settings window: banner, sidebar list, `SnippetEditor`. |
| `Sources/CopyStack/ShortcutRecorderView.swift` | Click-to-record shortcut control (`NSViewRepresentable`). |
| `Tests/CopyStackCoreTests/KeyComboTests.swift` | Display string, modifier check, Codable. |
| `Tests/CopyStackCoreTests/SnippetStoreTests.swift` | Persistence, CRUD, conflict and validation. |
| `Resources/Info.plist` | Bundle metadata, `LSUIElement`. |
| `Scripts/build-app.sh` | Build + assemble + sign `build/CopyStack.app`. |
| `README.md` | Usage, build, permission and signing notes, manual test checklist. |

---

### Task 1: Package scaffold and `KeyCombo`

**Files:**
- Create: `Package.swift`
- Create: `.gitignore`
- Create: `Sources/CopyStackCore/KeyCombo.swift`
- Create: `Sources/CopyStack/CopyStackApp.swift` (temporary stub so the executable target compiles; replaced in Task 4)
- Test: `Tests/CopyStackCoreTests/KeyComboTests.swift`

**Interfaces:**
- Produces:
  - `public struct KeyCombo: Codable, Equatable, Hashable { public var keyCode: UInt32; public var modifiers: UInt32; public init(keyCode: UInt32, modifiers: UInt32) }`
  - `public enum KeyCombo.Modifier { static let command, shift, option, control: UInt32 }`
  - `public var KeyCombo.hasModifiers: Bool`
  - `public var KeyCombo.displayString: String`
  - `public static func KeyCombo.keyName(for keyCode: UInt32) -> String`

- [ ] **Step 1: Create the package manifest, .gitignore and a stub entry point**

`Package.swift`:

```swift
// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "CopyStack",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "CopyStackCore"),
        .executableTarget(
            name: "CopyStack",
            dependencies: ["CopyStackCore"]
        ),
        .testTarget(
            name: "CopyStackCoreTests",
            dependencies: ["CopyStackCore"]
        ),
    ]
)
```

`.gitignore`:

```
.build/
build/
.swiftpm/
.DS_Store
```

`Sources/CopyStack/CopyStackApp.swift` (temporary; Task 4 replaces it):

```swift
import Foundation

@main
struct CopyStackApp {
    static func main() {
        print("CopyStack stub")
    }
}
```

- [ ] **Step 2: Write the failing KeyCombo tests**

`Tests/CopyStackCoreTests/KeyComboTests.swift`:

```swift
import XCTest
@testable import CopyStackCore

final class KeyComboTests: XCTestCase {
    func testDisplayStringOrdersModifiersControlOptionShiftCommand() {
        let all = KeyCombo.Modifier.command | KeyCombo.Modifier.shift
            | KeyCombo.Modifier.option | KeyCombo.Modifier.control
        XCTAssertEqual(KeyCombo(keyCode: 14, modifiers: all).displayString, "⌃⌥⇧⌘E")
    }

    func testDisplayStringForSingleModifier() {
        XCTAssertEqual(KeyCombo(keyCode: 14, modifiers: KeyCombo.Modifier.option).displayString, "⌥E")
    }

    func testDisplayStringForDigitsAndNamedKeys() {
        XCTAssertEqual(KeyCombo(keyCode: 18, modifiers: KeyCombo.Modifier.command).displayString, "⌘1")
        XCTAssertEqual(KeyCombo(keyCode: 49, modifiers: KeyCombo.Modifier.control).displayString, "⌃Space")
        XCTAssertEqual(KeyCombo(keyCode: 122, modifiers: KeyCombo.Modifier.shift).displayString, "⇧F1")
    }

    func testDisplayStringFallsBackForUnknownKeyCode() {
        XCTAssertEqual(KeyCombo(keyCode: 200, modifiers: KeyCombo.Modifier.command).displayString, "⌘Key200")
    }

    func testHasModifiers() {
        XCTAssertFalse(KeyCombo(keyCode: 14, modifiers: 0).hasModifiers)
        XCTAssertTrue(KeyCombo(keyCode: 14, modifiers: KeyCombo.Modifier.shift).hasModifiers)
    }

    func testCodableRoundTrip() throws {
        let combo = KeyCombo(keyCode: 14, modifiers: KeyCombo.Modifier.control | KeyCombo.Modifier.option)
        let data = try JSONEncoder().encode(combo)
        XCTAssertEqual(try JSONDecoder().decode(KeyCombo.self, from: data), combo)
    }
}
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `swift test --filter KeyComboTests 2>&1 | tail -20`
Expected: compile error — `cannot find 'KeyCombo' in scope`.

- [ ] **Step 4: Implement `KeyCombo`**

`Sources/CopyStackCore/KeyCombo.swift`:

```swift
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
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `swift test --filter KeyComboTests 2>&1 | tail -20`
Expected: `Executed 6 tests, with 0 failures`.

- [ ] **Step 6: Commit**

```bash
git add Package.swift .gitignore Sources Tests
git commit -m "Add package scaffold and KeyCombo model"
```

---

### Task 2: `Snippet` model and `SnippetStore` persistence

**Files:**
- Create: `Sources/CopyStackCore/Snippet.swift`
- Create: `Sources/CopyStackCore/SnippetStore.swift`
- Test: `Tests/CopyStackCoreTests/SnippetStoreTests.swift`

**Interfaces:**
- Consumes: `KeyCombo` from Task 1.
- Produces:
  - `public struct Snippet: Identifiable, Codable, Equatable { public var id: UUID; public var name: String; public var text: String; public var shortcut: KeyCombo?; public init(id: UUID = UUID(), name: String, text: String = "", shortcut: KeyCombo? = nil) }`
  - `public final class SnippetStore: ObservableObject`
    - `@Published public private(set) var snippets: [Snippet]`
    - `public let fileURL: URL`
    - `public static var defaultFileURL: URL`
    - `public init(fileURL: URL = SnippetStore.defaultFileURL)`
    - `@discardableResult public func add(name: String = "New Snippet", text: String = "") -> Snippet`
    - `public func remove(id: Snippet.ID)`
    - `public func update(_ snippet: Snippet)`

- [ ] **Step 1: Write the failing store tests**

`Tests/CopyStackCoreTests/SnippetStoreTests.swift`:

```swift
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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter SnippetStoreTests 2>&1 | tail -20`
Expected: compile error — `cannot find 'SnippetStore' in scope`.

- [ ] **Step 3: Implement `Snippet` and `SnippetStore`**

`Sources/CopyStackCore/Snippet.swift`:

```swift
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
```

`Sources/CopyStackCore/SnippetStore.swift`:

```swift
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
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test 2>&1 | tail -20`
Expected: `Executed 14 tests, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add Sources/CopyStackCore Tests
git commit -m "Add Snippet model and JSON-backed SnippetStore"
```

---

### Task 3: Shortcut conflict detection and validation

**Files:**
- Modify: `Sources/CopyStackCore/SnippetStore.swift`
- Test: `Tests/CopyStackCoreTests/SnippetStoreTests.swift`

**Interfaces:**
- Consumes: `SnippetStore`, `Snippet`, `KeyCombo`.
- Produces:
  - `public enum SnippetStore.ValidationError: Error, Equatable { case missingModifier; case shortcutConflict(ownerName: String) }`
  - `public func conflict(for combo: KeyCombo, excluding id: Snippet.ID? = nil) -> Snippet?`
  - `public func validate(_ combo: KeyCombo, for snippetID: Snippet.ID) throws`

- [ ] **Step 1: Append the failing validation tests**

Add to the end of the class body in `Tests/CopyStackCoreTests/SnippetStoreTests.swift`:

```swift
    // MARK: Shortcut validation

    private let combo = KeyCombo(keyCode: 14, modifiers: KeyCombo.Modifier.control | KeyCombo.Modifier.option)

    private func makeStoreWithEmailBoundToCombo() -> (SnippetStore, Snippet) {
        let store = SnippetStore(fileURL: fileURL)
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
        let store = SnippetStore(fileURL: fileURL)
        let snippet = store.add()
        XCTAssertThrowsError(try store.validate(KeyCombo(keyCode: 14, modifiers: 0), for: snippet.id)) { error in
            XCTAssertEqual(error as? SnippetStore.ValidationError, .missingModifier)
        }
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
        let store = SnippetStore(fileURL: fileURL)
        let snippet = store.add()
        XCTAssertNoThrow(try store.validate(KeyCombo(keyCode: 1, modifiers: KeyCombo.Modifier.command), for: snippet.id))
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter SnippetStoreTests 2>&1 | tail -20`
Expected: compile error — `value of type 'SnippetStore' has no member 'conflict'`.

- [ ] **Step 3: Implement conflict detection and validation**

Add to `Sources/CopyStackCore/SnippetStore.swift`, after the `// MARK: Mutations` block:

```swift
    // MARK: Shortcut validation

    public enum ValidationError: Error, Equatable {
        /// The combo has none of ⌃⌥⇧⌘; a bare key can't be a global hotkey.
        case missingModifier
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
        if let owner = conflict(for: combo, excluding: snippetID) {
            throw ValidationError.shortcutConflict(ownerName: owner.name)
        }
    }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test 2>&1 | tail -20`
Expected: `Executed 21 tests, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add Sources/CopyStackCore/SnippetStore.swift Tests/CopyStackCoreTests/SnippetStoreTests.swift
git commit -m "Add shortcut conflict detection and validation to SnippetStore"
```

---

### Task 4: App skeleton — menu bar icon, bundle, build script

**Files:**
- Replace: `Sources/CopyStack/CopyStackApp.swift`
- Create: `Sources/CopyStack/MenuBarView.swift`
- Create: `Resources/Info.plist`
- Create: `Scripts/build-app.sh`

**Interfaces:**
- Consumes: `SnippetStore` from Task 2.
- Produces:
  - `final class AppDelegate: NSObject, NSApplicationDelegate { let store: SnippetStore }` — Task 5 adds `paster`, Task 6 adds `hotKeyManager`.
  - `struct MenuBarView: View { init(store: SnippetStore) }` — Task 5 adds `paster:`.
  - `Scripts/build-app.sh [--debug]` producing `build/CopyStack.app`; honours `CODESIGN_IDENTITY` (default `-`).

- [ ] **Step 1: Write the app entry point and delegate**

`Sources/CopyStack/CopyStackApp.swift` (replace the stub entirely):

```swift
import AppKit
import CopyStackCore
import SwiftUI

@main
struct CopyStackApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("CopyStack", systemImage: "doc.on.clipboard") {
            MenuBarView(store: appDelegate.store)
        }
    }
}

/// Owns the long-lived objects. SwiftUI scenes read them through the adaptor.
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = SnippetStore()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu bar only: no Dock icon, no app switcher entry. Info.plist sets
        // LSUIElement for the bundle; this covers `swift run`.
        NSApp.setActivationPolicy(.accessory)
    }
}
```

- [ ] **Step 2: Write the menu content**

`Sources/CopyStack/MenuBarView.swift`:

```swift
import AppKit
import CopyStackCore
import SwiftUI

/// Content of the menu bar dropdown.
struct MenuBarView: View {
    @ObservedObject var store: SnippetStore

    var body: some View {
        if store.snippets.isEmpty {
            Text("No snippets yet")
        } else {
            ForEach(store.snippets) { snippet in
                Text(Self.title(for: snippet))
            }
        }
        Divider()
        Button("Quit CopyStack") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }

    static func title(for snippet: Snippet) -> String {
        guard let shortcut = snippet.shortcut else { return snippet.name }
        return "\(snippet.name)  —  \(shortcut.displayString)"
    }
}
```

- [ ] **Step 3: Write Info.plist and the build script**

`Resources/Info.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>CopyStack</string>
    <key>CFBundleIdentifier</key>
    <string>com.ozanalbayrak.CopyStack</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>CopyStack</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
```

`Scripts/build-app.sh`:

```bash
#!/usr/bin/env bash
# Builds build/CopyStack.app from the Swift package.
#
# Usage: Scripts/build-app.sh [--debug]
#
# Environment:
#   CODESIGN_IDENTITY  Identity passed to codesign. Defaults to "-" (ad-hoc).
#                      Use an "Apple Development: ..." identity to keep the
#                      Accessibility grant across rebuilds.
set -euo pipefail

cd "$(dirname "$0")/.."

config=release
if [[ "${1:-}" == "--debug" ]]; then
    config=debug
fi

swift build -c "$config"

binary="$(swift build -c "$config" --show-bin-path)/CopyStack"
app="build/CopyStack.app"

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$binary" "$app/Contents/MacOS/CopyStack"
cp Resources/Info.plist "$app/Contents/Info.plist"
printf 'APPL????' > "$app/Contents/PkgInfo"

codesign --force --sign "${CODESIGN_IDENTITY:--}" "$app"

echo "Built $app"
```

Then: `chmod +x Scripts/build-app.sh`

- [ ] **Step 4: Build and verify the tests still pass**

Run: `swift build 2>&1 | tail -5 && swift test 2>&1 | tail -3`
Expected: `Build complete!` and `Executed 21 tests, with 0 failures`.

- [ ] **Step 5: Build the bundle and launch it**

Run: `Scripts/build-app.sh && open build/CopyStack.app`
Expected: `Built build/CopyStack.app`; a clipboard icon appears in the menu bar; no Dock icon; clicking the icon shows "No snippets yet", a separator and "Quit CopyStack"; Quit closes the app.

Run: `codesign -dv build/CopyStack.app 2>&1 | grep Identifier`
Expected: `Identifier=com.ozanalbayrak.CopyStack`.

- [ ] **Step 6: Commit**

```bash
git add Sources/CopyStack Resources Scripts
git commit -m "Add menu bar app skeleton, Info.plist and bundle build script"
```

---

### Task 5: `AccessibilityGate` and `Paster`; paste from the menu

**Files:**
- Create: `Sources/CopyStack/AccessibilityGate.swift`
- Create: `Sources/CopyStack/Paster.swift`
- Modify: `Sources/CopyStack/CopyStackApp.swift`
- Modify: `Sources/CopyStack/MenuBarView.swift`

**Interfaces:**
- Consumes: `AppDelegate`, `MenuBarView` from Task 4.
- Produces:
  - `enum AccessibilityGate { static var isTrusted: Bool; @discardableResult static func requestIfNeeded() -> Bool; static func openSystemSettings() }`
  - `final class Paster { init(pasteboard: NSPasteboard = .general, restoreDelay: TimeInterval = 0.15); func paste(_ text: String) }`
  - `AppDelegate.paster: Paster`
  - `MenuBarView(store:paster:)`

- [ ] **Step 1: Write `AccessibilityGate`**

`Sources/CopyStack/AccessibilityGate.swift`:

```swift
import AppKit
import ApplicationServices

/// Wraps the Accessibility (AX) trust check. Posting synthetic ⌘V requires it.
enum AccessibilityGate {
    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Shows the system "would like to control this computer" prompt when
    /// not yet trusted. Returns the current trust state.
    @discardableResult
    static func requestIfNeeded() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func openSystemSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}
```

- [ ] **Step 2: Write `Paster`**

`Sources/CopyStack/Paster.swift`:

```swift
import AppKit
import os

/// Pastes text into the frontmost app by briefly borrowing the system
/// pasteboard: snapshot → write text → ⌘V → restore.
///
/// Requests are queued so back-to-back triggers don't interleave their
/// snapshot/restore steps. Main thread only.
final class Paster {
    private typealias ItemSnapshot = [NSPasteboard.PasteboardType: Data]

    private let pasteboard: NSPasteboard
    private let restoreDelay: TimeInterval
    private var queue: [String] = []
    private var isPasting = false

    private static let logger = Logger(subsystem: "com.ozanalbayrak.CopyStack", category: "Paster")
    private static let vKeyCode: CGKeyCode = 9 // kVK_ANSI_V

    init(pasteboard: NSPasteboard = .general, restoreDelay: TimeInterval = 0.15) {
        self.pasteboard = pasteboard
        self.restoreDelay = restoreDelay
    }

    func paste(_ text: String) {
        guard AccessibilityGate.isTrusted else {
            // Without the grant CGEvent.post is a silent no-op; make the
            // failure visible instead.
            Self.logger.warning("Paste skipped: Accessibility permission not granted")
            AccessibilityGate.requestIfNeeded()
            return
        }
        queue.append(text)
        drain()
    }

    private func drain() {
        guard !isPasting, !queue.isEmpty else { return }
        isPasting = true
        let text = queue.removeFirst()

        let snapshot = snapshotPasteboard()
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        postCommandV()

        // Give the target app time to read the pasteboard before restoring.
        DispatchQueue.main.asyncAfter(deadline: .now() + restoreDelay) { [weak self] in
            guard let self else { return }
            self.restore(snapshot)
            self.isPasting = false
            self.drain()
        }
    }

    // MARK: Pasteboard snapshot

    private func snapshotPasteboard() -> [ItemSnapshot] {
        (pasteboard.pasteboardItems ?? []).compactMap { item in
            var data: ItemSnapshot = [:]
            for type in item.types {
                if let bytes = item.data(forType: type) {
                    data[type] = bytes
                }
            }
            return data.isEmpty ? nil : data
        }
    }

    private func restore(_ snapshot: [ItemSnapshot]) {
        pasteboard.clearContents()
        guard !snapshot.isEmpty else { return }
        let items = snapshot.map { data -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, bytes) in data {
                if !item.setData(bytes, forType: type) {
                    Self.logger.error("Failed to restore pasteboard type \(type.rawValue, privacy: .public)")
                }
            }
            return item
        }
        pasteboard.writeObjects(items)
    }

    // MARK: Keystroke

    private func postCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: Self.vKeyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: Self.vKeyCode, keyDown: false)
        else {
            Self.logger.error("Failed to create ⌘V events")
            return
        }
        // Explicit flags: modifiers the user is still holding from the
        // hotkey (⌃⌥…) must not leak into the paste keystroke.
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}
```

- [ ] **Step 3: Wire the paster into the delegate and menu**

In `Sources/CopyStack/CopyStackApp.swift`:

- In `AppDelegate`, add `let paster = Paster()` below `let store = SnippetStore()`.
- In `applicationDidFinishLaunching`, after `NSApp.setActivationPolicy(.accessory)`, add:
  ```swift
        AccessibilityGate.requestIfNeeded()
  ```
- Change the `MenuBarExtra` content to `MenuBarView(store: appDelegate.store, paster: appDelegate.paster)`.

In `Sources/CopyStack/MenuBarView.swift`:

- Add `let paster: Paster` below `@ObservedObject var store: SnippetStore`.
- Replace the `ForEach` body so each row is a button:
  ```swift
            ForEach(store.snippets) { snippet in
                Button(Self.title(for: snippet)) {
                    paster.paste(snippet.text)
                }
            }
  ```

- [ ] **Step 4: Build**

Run: `swift build 2>&1 | tail -5`
Expected: `Build complete!` with no errors.

- [ ] **Step 5: Manual verification**

1. Seed a snippet by hand:
   ```bash
   mkdir -p ~/Library/Application\ Support/CopyStack
   cat > ~/Library/Application\ Support/CopyStack/snippets.json <<'JSON'
   [
     { "id": "11111111-1111-1111-1111-111111111111", "name": "Email", "text": "me@example.com" }
   ]
   JSON
   ```
2. `Scripts/build-app.sh && open build/CopyStack.app`. On first launch the Accessibility prompt appears; grant it in System Settings → Privacy & Security → Accessibility (add `build/CopyStack.app`). Quit and reopen the app after granting.
3. Open TextEdit, copy the word `hello` from somewhere. Click the CopyStack icon → "Email". Expected: `me@example.com` appears in TextEdit.
4. Press ⌘V in TextEdit. Expected: `hello` is pasted — the original clipboard survived.
5. Copy an image in Preview, repeat step 3 in TextEdit, then ⌘V in Preview. Expected: text pasted in TextEdit, image still pastes in Preview.

- [ ] **Step 6: Commit**

```bash
git add Sources/CopyStack
git commit -m "Add Paster and AccessibilityGate; paste snippets from the menu"
```

---

### Task 6: `HotKeyManager` — global shortcuts trigger pastes

**Files:**
- Create: `Sources/CopyStack/HotKeyManager.swift`
- Modify: `Sources/CopyStack/CopyStackApp.swift`

**Interfaces:**
- Consumes: `SnippetStore.$snippets`, `Snippet.shortcut`, `KeyCombo.keyCode/modifiers/displayString`, `Paster.paste(_:)`.
- Produces:
  - `final class HotKeyManager { var isEnabled: Bool; init(store: SnippetStore, onTrigger: @escaping (Snippet) -> Void) }`
  - `AppDelegate.hotKeyManager: HotKeyManager`

- [ ] **Step 1: Write `HotKeyManager`**

`Sources/CopyStack/HotKeyManager.swift`:

```swift
import AppKit
import Carbon
import Combine
import CopyStackCore
import os

/// Registers one Carbon global hotkey per snippet that has a shortcut and
/// calls `onTrigger` when one fires. Re-registers everything whenever the
/// store changes; snippet counts are small enough that diffing isn't worth it.
final class HotKeyManager {
    /// Set to `false` while the shortcut recorder is capturing keys so the
    /// pressed combo doesn't trigger a paste.
    var isEnabled = true

    private let store: SnippetStore
    private let onTrigger: (Snippet) -> Void
    private var registrations: [UInt32: (ref: EventHotKeyRef, snippetID: Snippet.ID)] = [:]
    private var nextID: UInt32 = 1
    private var handlerRef: EventHandlerRef?
    private var cancellable: AnyCancellable?

    private static let logger = Logger(subsystem: "com.ozanalbayrak.CopyStack", category: "HotKeyManager")
    private static let signature: OSType = 0x4350_5354 // "CPST"

    init(store: SnippetStore, onTrigger: @escaping (Snippet) -> Void) {
        self.store = store
        self.onTrigger = onTrigger
        installHandler()
        // @Published emits the current value on subscription, so this also
        // performs the initial registration.
        cancellable = store.$snippets.sink { [weak self] snippets in
            self?.register(snippets)
        }
    }

    deinit {
        unregisterAll()
        if let handlerRef {
            RemoveEventHandler(handlerRef)
        }
    }

    // MARK: Carbon plumbing

    private func installHandler() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed))
        let userData = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let userData, let event else { return OSStatus(eventNotHandledErr) }
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID)
            guard status == noErr else { return status }
            let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
            manager.handle(hotKeyID: hotKeyID.id)
            return noErr
        }, 1, &eventType, userData, &handlerRef)
        if status != noErr {
            Self.logger.error("InstallEventHandler failed: \(status)")
        }
    }

    private func handle(hotKeyID: UInt32) {
        guard isEnabled,
              let registration = registrations[hotKeyID],
              let snippet = store.snippets.first(where: { $0.id == registration.snippetID })
        else { return }
        onTrigger(snippet)
    }

    private func register(_ snippets: [Snippet]) {
        unregisterAll()
        for snippet in snippets {
            guard let combo = snippet.shortcut else { continue }
            let id = nextID
            nextID += 1
            var ref: EventHotKeyRef?
            let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
            let status = RegisterEventHotKey(
                combo.keyCode, combo.modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)
            if status == noErr, let ref {
                registrations[id] = (ref, snippet.id)
            } else {
                // Typically the combo is already taken by another app.
                Self.logger.error("RegisterEventHotKey failed for \(combo.displayString, privacy: .public): \(status)")
            }
        }
    }

    private func unregisterAll() {
        for registration in registrations.values {
            UnregisterEventHotKey(registration.ref)
        }
        registrations.removeAll()
    }
}
```

- [ ] **Step 2: Wire it into the delegate**

In `Sources/CopyStack/CopyStackApp.swift`, inside `AppDelegate`:

- Below `let paster = Paster()`, add:
  ```swift
    lazy var hotKeyManager = HotKeyManager(store: store) { [paster] snippet in
        paster.paste(snippet.text)
    }
  ```
- In `applicationDidFinishLaunching`, before `AccessibilityGate.requestIfNeeded()`, add:
  ```swift
        _ = hotKeyManager // register shortcuts at launch
  ```

- [ ] **Step 3: Build**

Run: `swift build 2>&1 | tail -5`
Expected: `Build complete!`.

- [ ] **Step 4: Manual verification**

1. Give the seeded snippet a shortcut (⌃⌥E = keyCode 14, modifiers 0x0800 | 0x1000 = 6144):
   ```bash
   cat > ~/Library/Application\ Support/CopyStack/snippets.json <<'JSON'
   [
     { "id": "11111111-1111-1111-1111-111111111111", "name": "Email", "text": "me@example.com",
       "shortcut": { "keyCode": 14, "modifiers": 6144 } }
   ]
   JSON
   ```
2. `Scripts/build-app.sh && open build/CopyStack.app`. If Accessibility was lost after the rebuild (ad-hoc signing), re-grant it and relaunch.
3. The menu row now reads `Email  —  ⌃⌥E`.
4. Focus TextEdit and press ⌃⌥E. Expected: `me@example.com` appears; nothing else is typed (the keystroke was consumed).
5. Focus Safari's address bar and press ⌃⌥E. Expected: the text appears there too.

- [ ] **Step 5: Commit**

```bash
git add Sources/CopyStack
git commit -m "Add HotKeyManager for per-snippet global shortcuts"
```

---

### Task 7: Settings window — list and name/text editor

**Files:**
- Create: `Sources/CopyStack/SettingsView.swift`
- Modify: `Sources/CopyStack/CopyStackApp.swift`
- Modify: `Sources/CopyStack/MenuBarView.swift`

**Interfaces:**
- Consumes: `SnippetStore.add/remove/update`, `AccessibilityGate`, `HotKeyManager`.
- Produces:
  - `struct SettingsView: View { init(store: SnippetStore, hotKeyManager: HotKeyManager) }`
  - `struct SnippetEditor: View { @Binding var snippet: Snippet; store: SnippetStore; hotKeyManager: HotKeyManager }` — Task 8 adds the shortcut row.
  - Window scene id `"settings"`.

- [ ] **Step 1: Write `SettingsView`**

`Sources/CopyStack/SettingsView.swift`:

```swift
import AppKit
import CopyStackCore
import SwiftUI

/// Settings window: permission banner, snippet list on the left, editor on the right.
struct SettingsView: View {
    @ObservedObject var store: SnippetStore
    let hotKeyManager: HotKeyManager

    @State private var selectedID: Snippet.ID?
    @State private var isTrusted = AccessibilityGate.isTrusted

    var body: some View {
        VStack(spacing: 0) {
            if !isTrusted {
                permissionBanner
            }
            HSplitView {
                sidebar
                    .frame(minWidth: 180, idealWidth: 200, maxWidth: 260)
                editor
                    .frame(minWidth: 360, maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 600, minHeight: 400)
        // The user grants permission in System Settings and comes back; re-check then.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            isTrusted = AccessibilityGate.isTrusted
        }
    }

    private var permissionBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text("Pasting requires Accessibility permission.")
            Spacer()
            Button("Open System Settings") {
                AccessibilityGate.openSystemSettings()
            }
        }
        .padding(10)
        .background(Color.yellow.opacity(0.25))
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            List(selection: $selectedID) {
                ForEach(store.snippets) { snippet in
                    Text(snippet.name.isEmpty ? "Untitled" : snippet.name)
                        .tag(snippet.id)
                }
            }
            Divider()
            HStack(spacing: 0) {
                Button {
                    selectedID = store.add().id
                } label: {
                    Image(systemName: "plus")
                }
                .help("Add snippet")
                Divider().frame(height: 16)
                Button {
                    if let id = selectedID {
                        store.remove(id: id)
                        selectedID = nil
                    }
                } label: {
                    Image(systemName: "minus")
                }
                .help("Remove snippet")
                .disabled(selectedID == nil)
                Spacer()
            }
            .buttonStyle(.borderless)
            .padding(6)
        }
    }

    @ViewBuilder
    private var editor: some View {
        if let id = selectedID, store.snippets.contains(where: { $0.id == id }) {
            SnippetEditor(snippet: binding(for: id), store: store, hotKeyManager: hotKeyManager)
                .id(id)
        } else {
            Text("Select or add a snippet")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func binding(for id: Snippet.ID) -> Binding<Snippet> {
        Binding(
            get: { store.snippets.first { $0.id == id } ?? Snippet(id: id, name: "") },
            set: { store.update($0) })
    }
}

/// Edits one snippet. Every change goes straight to the store; there is no Save button.
struct SnippetEditor: View {
    @Binding var snippet: Snippet
    @ObservedObject var store: SnippetStore
    let hotKeyManager: HotKeyManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LabeledContent("Name") {
                TextField("Name", text: $snippet.name)
                    .textFieldStyle(.roundedBorder)
            }
            Text("Text")
                .font(.headline)
            TextEditor(text: $snippet.text)
                .font(.system(.body, design: .monospaced))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .border(Color(nsColor: .separatorColor))
        }
        .padding()
    }
}
```

- [ ] **Step 2: Add the window scene and menu item**

In `Sources/CopyStack/CopyStackApp.swift`, inside `body`, after the `MenuBarExtra { … }` block, add:

```swift
        Window("CopyStack Settings", id: "settings") {
            SettingsView(store: appDelegate.store, hotKeyManager: appDelegate.hotKeyManager)
        }
        .defaultSize(width: 640, height: 440)
```

In `Sources/CopyStack/MenuBarView.swift`:

- Add `@Environment(\.openWindow) private var openWindow` below `let paster: Paster`.
- Between `Divider()` and the Quit button, add:
  ```swift
        Button("Settings…") {
            openWindow(id: "settings")
            // Accessory apps don't come forward on their own.
            NSApp.activate()
        }
        .keyboardShortcut(",", modifiers: .command)
  ```

- [ ] **Step 3: Build**

Run: `swift build 2>&1 | tail -5`
Expected: `Build complete!`.

- [ ] **Step 4: Manual verification**

1. `Scripts/build-app.sh && open build/CopyStack.app` (re-grant Accessibility if lost).
2. Menu → "Settings…". Expected: the window opens in front with "Email" in the sidebar.
3. Click "Email". Expected: name field shows `Email`, text editor shows `me@example.com`.
4. Change the name to `Work email`. Expected: sidebar row and menu row update; `cat ~/Library/Application\ Support/CopyStack/snippets.json` shows the new name.
5. Click `+`. Expected: "New Snippet" appears, selected, empty text. Type some text; it persists to the file.
6. Select the new snippet, click `−`. Expected: it disappears; editor shows "Select or add a snippet".
7. If the banner is visible, click "Open System Settings". Expected: System Settings opens on Privacy & Security → Accessibility. Grant, switch back; banner disappears.

- [ ] **Step 5: Commit**

```bash
git add Sources/CopyStack
git commit -m "Add Settings window with snippet list and editor"
```

---

### Task 8: `ShortcutRecorderView` and shortcut editing

**Files:**
- Create: `Sources/CopyStack/ShortcutRecorderView.swift`
- Modify: `Sources/CopyStack/SettingsView.swift`

**Interfaces:**
- Consumes: `KeyCombo`, `KeyCombo.Modifier`, `SnippetStore.validate(_:for:)`, `SnippetStore.ValidationError`, `HotKeyManager.isEnabled`.
- Produces:
  - `struct ShortcutRecorderView: NSViewRepresentable { combo: KeyCombo?; onRecordingChanged: (Bool) -> Void; onRecord: (KeyCombo) -> Bool; onClear: () -> Void }`
  - `final class RecorderControl: NSView` with `static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32`

- [ ] **Step 1: Write the recorder**

`Sources/CopyStack/ShortcutRecorderView.swift`:

```swift
import AppKit
import CopyStackCore
import SwiftUI

/// Click-to-record shortcut field. Click, press a combo, done.
///
/// - `onRecordingChanged` fires with `true` when recording starts and `false`
///   when it ends, so the caller can pause global hotkeys.
/// - `onRecord` receives the pressed combo; return `true` to accept it
///   (recording ends) or `false` to reject it (recording continues).
struct ShortcutRecorderView: NSViewRepresentable {
    var combo: KeyCombo?
    var onRecordingChanged: (Bool) -> Void
    var onRecord: (KeyCombo) -> Bool
    var onClear: () -> Void

    func makeNSView(context: Context) -> RecorderControl {
        let control = RecorderControl()
        control.combo = combo
        apply(to: control)
        return control
    }

    func updateNSView(_ control: RecorderControl, context: Context) {
        apply(to: control)
        if !control.isRecording {
            control.combo = combo
        }
    }

    private func apply(to control: RecorderControl) {
        control.onRecordingChanged = onRecordingChanged
        control.onRecord = onRecord
        control.onClear = onClear
    }
}

final class RecorderControl: NSView {
    var combo: KeyCombo? {
        didSet { updateAppearance() }
    }
    var onRecordingChanged: ((Bool) -> Void)?
    var onRecord: ((KeyCombo) -> Bool)?
    var onClear: (() -> Void)?

    private(set) var isRecording = false {
        didSet {
            guard oldValue != isRecording else { return }
            updateAppearance()
            onRecordingChanged?(isRecording)
        }
    }

    private let label = NSTextField(labelWithString: "")
    private let clearButton: NSButton

    private static let escapeKeyCode: UInt16 = 53 // kVK_Escape

    override init(frame: NSRect) {
        let image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Clear shortcut")!
        clearButton = NSButton(image: image, target: nil, action: nil)
        super.init(frame: frame)

        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.borderWidth = 1

        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        clearButton.isBordered = false
        clearButton.target = self
        clearButton.action = #selector(clearTapped)
        clearButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(clearButton)

        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            clearButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            clearButton.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        updateAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 180, height: 24)
    }

    override var acceptsFirstResponder: Bool { true }

    // MARK: Recording

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        isRecording = true
    }

    override func resignFirstResponder() -> Bool {
        isRecording = false
        return super.resignFirstResponder()
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }
        if event.keyCode == Self.escapeKeyCode {
            stopRecording()
            return
        }
        let candidate = KeyCombo(
            keyCode: UInt32(event.keyCode),
            modifiers: Self.carbonModifiers(from: event.modifierFlags))
        if onRecord?(candidate) == true {
            combo = candidate
            stopRecording()
        }
    }

    /// ⌘-combos are routed as key equivalents and never reach `keyDown`.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isRecording, event.type == .keyDown else {
            return super.performKeyEquivalent(with: event)
        }
        keyDown(with: event)
        return true
    }

    private func stopRecording() {
        isRecording = false
        window?.makeFirstResponder(nil)
    }

    @objc private func clearTapped() {
        combo = nil
        onClear?()
    }

    // MARK: Appearance

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    private func updateAppearance() {
        if isRecording {
            label.stringValue = "Press keys…"
        } else if let combo {
            label.stringValue = combo.displayString
        } else {
            label.stringValue = "Click to record"
        }
        let isPlaceholder = isRecording || combo == nil
        label.textColor = isPlaceholder ? .secondaryLabelColor : .labelColor
        clearButton.isHidden = combo == nil || isRecording
        layer?.borderColor = (isRecording ? NSColor.controlAccentColor : NSColor.separatorColor).cgColor
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
    }

    // MARK: Modifier mapping

    /// Maps AppKit modifier flags to the Carbon bitmask stored in `KeyCombo`.
    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var result: UInt32 = 0
        if flags.contains(.command) { result |= KeyCombo.Modifier.command }
        if flags.contains(.shift) { result |= KeyCombo.Modifier.shift }
        if flags.contains(.option) { result |= KeyCombo.Modifier.option }
        if flags.contains(.control) { result |= KeyCombo.Modifier.control }
        return result
    }
}
```

- [ ] **Step 2: Add the shortcut row to `SnippetEditor`**

In `Sources/CopyStack/SettingsView.swift`, in `SnippetEditor`:

- Add `@State private var shortcutError: String?` below `let hotKeyManager: HotKeyManager`.
- Between the `LabeledContent("Name") { … }` block and `Text("Text")`, insert:

```swift
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
                            } catch {
                                shortcutError = "Add at least one modifier key (⌃ ⌥ ⇧ ⌘)"
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
```

- [ ] **Step 3: Build**

Run: `swift build 2>&1 | tail -5`
Expected: `Build complete!`.

- [ ] **Step 4: Manual verification**

1. `Scripts/build-app.sh && open build/CopyStack.app` (re-grant Accessibility if lost). Open Settings.
2. Select "Email". Expected: recorder shows `⌃⌥E` with a `×` button.
3. Click `×`. Expected: recorder shows "Click to record"; menu row is just `Email`; ⌃⌥E in TextEdit does nothing.
4. Click the recorder, press ⌃⌥E. Expected: recorder shows `⌃⌥E`; nothing was pasted into the Settings window during recording; ⌃⌥E in TextEdit pastes again.
5. Click the recorder, press plain `E`. Expected: red "Add at least one modifier key" text, still recording. Press Esc. Expected: back to `⌃⌥E`.
6. Click the recorder, press ⌘⇧K. Expected: recorder shows `⇧⌘K`; ⌘⇧K pastes in TextEdit.
7. Add a second snippet, click its recorder, press ⌘⇧K. Expected: red `Already used by “Email”`, still recording. Press ⌃⌥S. Expected: accepted.
8. Click the recorder, then click into the Name field. Expected: recording cancels (label returns to the combo).
9. Check the file: `cat ~/Library/Application\ Support/CopyStack/snippets.json` shows the shortcuts as `keyCode`/`modifiers`.

- [ ] **Step 5: Commit**

```bash
git add Sources/CopyStack
git commit -m "Add shortcut recorder and shortcut editing in Settings"
```

---

### Task 9: README and end-to-end checklist

**Files:**
- Create: `README.md`

- [ ] **Step 1: Write the README**

`README.md`:

````markdown
# CopyStack

A tiny macOS menu bar app for text you type over and over — an email
address, Slack slash commands, a meeting link. Each snippet gets its own
global keyboard shortcut; press it and the text is pasted into whatever app
is focused. Your real clipboard is left exactly as it was.

## Requirements

- macOS 14 or later
- Xcode 15+ command line tools (`swift`, `codesign`)

## Build

```bash
Scripts/build-app.sh          # release build → build/CopyStack.app
Scripts/build-app.sh --debug  # debug build
open build/CopyStack.app
```

To install, copy `build/CopyStack.app` to `/Applications`.

During development `swift run` works too; the app hides its Dock icon at
runtime.

## Accessibility permission

Pasting works by posting a synthetic ⌘V, which macOS only allows for apps
with Accessibility permission. CopyStack asks on first launch; you can also
grant it under **System Settings → Privacy & Security → Accessibility**. The
Settings window shows a banner until the permission is granted.

### Keeping the permission across rebuilds

macOS ties the grant to the app's code signature. With the default ad-hoc
signature the signature changes on every build, so the permission is lost
each time you rebuild. To avoid that, sign with a stable identity:

```bash
CODESIGN_IDENTITY="Apple Development: Your Name (TEAMID)" Scripts/build-app.sh
```

A free "Apple Development" certificate is enough: open Xcode → Settings →
Accounts, add your Apple ID, and click *Manage Certificates → +*. List your
identities with `security find-identity -v -p codesigning`.

## Usage

1. Click the clipboard icon in the menu bar → **Settings…**
2. Press **+** to add a snippet, give it a name and text.
3. Click the **Shortcut** field and press a key combination (at least one of
   ⌃ ⌥ ⇧ ⌘ plus a key). Shortcuts must be unique across snippets.
4. Focus any app and press the shortcut. Clicking a snippet in the menu
   pastes it too.

Snippets are stored in
`~/Library/Application Support/CopyStack/snippets.json`.

## Development

```bash
swift test    # unit tests for the Core module
swift build   # compile everything
```

The `CopyStackCore` library (models, JSON store, validation) is covered by
unit tests. The parts that talk to the system — global hotkeys, pasting,
the shortcut recorder — are verified by hand:

1. Build, launch, grant Accessibility when prompted.
2. Add a snippet and record ⌃⌥E.
3. Focus TextEdit and press ⌃⌥E → the text appears.
4. Copy an image in Preview, press ⌃⌥E in TextEdit → the text appears, and
   ⌘V in Preview still pastes the image.
5. Try to record ⌃⌥E on a second snippet → rejected, naming the owner.
6. Clear the shortcut → the menu row loses its label and the hotkey no
   longer fires.

## Roadmap

- Picker popup: one hotkey opens a searchable list of all snippets.
- Launch at login.
````

- [ ] **Step 2: Run the full checklist**

Run: `swift test 2>&1 | tail -3 && Scripts/build-app.sh && open build/CopyStack.app`
Expected: `Executed 21 tests, with 0 failures`, `Built build/CopyStack.app`.

Walk through the six-item manual checklist in the README. All six must behave as described.

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "Add README with build, permission and testing notes"
```
