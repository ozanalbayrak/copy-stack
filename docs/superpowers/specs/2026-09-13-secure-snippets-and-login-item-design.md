# Secret Snippets and Launch at Login — Design Spec

**Date:** 2026-09-13
**Status:** Approved
**Builds on:** `2026-09-13-copy-stack-design.md` (CopyStack 0.1.x)

## Problem

`snippets.json` is plaintext in `~/Library/Application Support/CopyStack/`.
That is fine for an email address, but some snippets are tokens or passwords:
any process running as the user can read the file, it lands in backups and
dotfile syncs, and during a paste the text sits on the system pasteboard for
~150 ms where clipboard managers record it.

Separately, a menu bar utility should be able to start at login.

## Goals

- Per-snippet opt-in secure storage: the text of a "secret" snippet never
  touches `snippets.json`; it lives in the user's login Keychain.
- Secret text is only read when needed (paste, reveal), never at launch.
- Clipboard managers ignore what CopyStack puts on the pasteboard.
- `snippets.json` is not world-readable.
- A "Launch at login" toggle in Settings.

## Non-goals

- Encrypting the whole file or syncing secrets between Macs.
- A master password / locking the app.
- Removing the Keychain item on `brew zap` (documented instead).
- Hiding secret snippet *names* in the menu.

## Decisions

| Question | Decision |
|---|---|
| Where secrets live | One generic-password Keychain item: service `com.ozanalbayrak.CopyStack`, account `secrets`, value = JSON `{ "<snippet-uuid>": "<text>" }`, `kSecAttrSynchronizable` false. |
| Why one item, not one per snippet | Keychain "Always Allow" grants are per item and per code signature. Ad-hoc-signed releases change signature on every update; one item means one prompt per update instead of one per secret snippet. |
| When the Keychain is touched | Lazily: first paste or first "Reveal" after launch. Never at startup, never for non-secret snippets. |
| Which snippets | Per-snippet `isSecret` flag, toggled in the editor. Default off; existing files decode with `isSecret = false`. |
| Clipboard managers | Every paste marks the pasteboard with `org.nspasteboard.ConcealedType` and `org.nspasteboard.TransientType` (the convention 1Password, Maccy, Raycast and Paste follow). Applied to all pastes, not only secret ones — everything CopyStack writes is transient. |
| File permissions | `snippets.json` is written with mode `0600`. |
| Launch at login | `SMAppService.mainApp` (macOS 13+). Toggle in the Settings sidebar footer. |
| In-memory handling | The `Snippet` values held by `SnippetStore` never contain secret text (`text` is `""` for secret snippets). Secret text is fetched on demand via `text(for:)`. |

Alternatives considered: app-level AES encryption with the key in the Keychain
(more code, only pays off if the file must sync); passphrase-based encryption
(prompt at every launch — too much friction for this tool).

## Architecture

### Core: `SecretStore`

```swift
public protocol SecretStore {
    /// All stored secrets. Empty when nothing has been stored yet.
    func read() throws -> [UUID: String]
    /// Replaces all stored secrets.
    func write(_ secrets: [UUID: String]) throws
}

public enum SecretStoreError: Error, Equatable {
    /// The user denied the Keychain prompt or the keychain is locked.
    case accessDenied
    /// Any other Keychain failure, with the OSStatus.
    case failure(OSStatus)
}
```

- `KeychainSecretStore` (Core, `import Security`): `SecItemCopyMatching` /
  `SecItemAdd` / `SecItemUpdate` / `SecItemDelete` on one
  `kSecClassGenericPassword` item. `errSecItemNotFound` on read → `[:]`.
  `errSecUserCanceled`, `errSecAuthFailed`, `errSecInteractionNotAllowed` →
  `.accessDenied`; anything else → `.failure(status)`. Writing an empty
  dictionary deletes the item.
- `InMemorySecretStore` (Core): dictionary-backed, for tests and previews.

Core stays free of AppKit and Carbon; `Security` is a Foundation-level
framework.

### Core: `Snippet`

```swift
public struct Snippet: Identifiable, Codable, Equatable {
    public var id: UUID
    public var name: String
    public var text: String        // "" when isSecret
    public var shortcut: KeyCombo?
    public var isSecret: Bool      // decodes as false when absent
}
```

### Core: `SnippetStore` additions

```swift
public init(fileURL: URL = SnippetStore.defaultFileURL,
            secretStore: SecretStore = KeychainSecretStore())

/// The text to paste. Reads the secret store for secret snippets.
public func text(for id: Snippet.ID) throws -> String

/// Writes text to the right place: JSON for normal snippets, secret store
/// for secret ones.
public func setText(_ text: String, for id: Snippet.ID) throws

/// Moves the text between JSON and the secret store and flips the flag.
public func setSecret(_ isSecret: Bool, for id: Snippet.ID) throws
```

Behaviour:

- `update(_:)` never writes secret text: for a snippet whose stored
  `isSecret` is true it forces `text = ""` before saving. Callers use
  `setText` for secret text.
- `setSecret(true)`: read secrets → insert current text → **write secrets
  first**, then set `text = ""`, `isSecret = true`, save JSON. A secret-store
  failure throws and leaves everything unchanged.
- `setSecret(false)`: read secrets → take the text → set `text`,
  `isSecret = false`, **save JSON first**, then remove the entry and write
  secrets. A failure on the second step is logged; the text is already safe
  in JSON.
- `remove(id:)`: removes the snippet, then best-effort removes its secret
  entry (logged on failure).
- `save()`: after the atomic write, sets POSIX permissions `0600` on the
  file.

### App: `Paster`

`drain()` writes the markers right after the string:

```swift
pasteboard.setString(text, forType: .string)
pasteboard.setData(Data(), forType: .init("org.nspasteboard.ConcealedType"))
pasteboard.setData(Data(), forType: .init("org.nspasteboard.TransientType"))
```

### App: resolving text before pasting

`AppDelegate` gains `func paste(_ snippet: Snippet)` which calls
`store.text(for: snippet.id)` and hands the result to `Paster`; on error it
logs and does not paste. `HotKeyManager`'s trigger closure and the menu
buttons call this instead of `paster.paste(snippet.text)`.

### App: `LoginItemManager`

```swift
final class LoginItemManager: ObservableObject {
    @Published private(set) var status: SMAppService.Status
    func refresh()                      // re-reads SMAppService.mainApp.status
    func setEnabled(_ enabled: Bool) throws   // register() / unregister(), then refresh()
    static func openSystemSettings()    // SMAppService.openSystemSettingsLoginItems()
}
```

Owned by `AppDelegate`; refreshed on `NSApplication.didBecomeActiveNotification`
alongside the Accessibility check.

### Settings window

**Sidebar footer** (below the `+`/`−` row): `Toggle("Launch at login")`
bound to `status == .enabled`. On change → `setEnabled`; on error show the
message in a red caption. When `status == .requiresApproval`: caption
"Approve in System Settings → General → Login Items" with an "Open" button.

**Editor** (`SnippetEditor`), below the Shortcut row:

- `Toggle("Store in Keychain")` bound to `snippet.isSecret`. On change →
  `store.setSecret`; on error revert the toggle and show a red caption
  ("Keychain access was denied" / "Keychain error <status>").
- When `isSecret` is false: the existing `TextEditor` bound to
  `snippet.text` (unchanged).
- When `isSecret` is true: a masked panel — lock icon, "Hidden — stored in
  Keychain", a **Reveal** button. Reveal calls `store.text(for:)` into
  `@State revealedText` and swaps in a `TextEditor` bound to it; edits go to
  `store.setText`. A **Hide** button clears `revealedText`. Selection change
  (`.id(id)`) resets to hidden. Read errors show the red caption.

The menu is unchanged: it shows names only.

## Error handling

| Situation | Behaviour |
|---|---|
| Keychain read denied at paste time | No paste; logged. |
| Keychain read denied on Reveal | Red caption in editor; stays hidden. |
| Keychain write fails when enabling "Store in Keychain" | Toggle reverts; caption; text stays in JSON. |
| Keychain write fails when disabling | Text already restored to JSON; stale Keychain entry logged (cleaned on next successful write). |
| `chmod 0600` fails | Logged; file still saved. |
| `SMAppService.register` throws (e.g. running from `swift run`, not a bundle) | Toggle reverts; caption with the error. |
| Login item needs approval | Caption + "Open" button to Login Items. |

## Testing

Core unit tests with `InMemorySecretStore` and a temp file:

- Old JSON without `isSecret` decodes with `false`.
- `setSecret(true)` moves text: `snippets[i].text == ""`, the file on disk
  does not contain the text, the secret store does; `text(for:)` returns it.
- `setSecret(false)` moves it back; the secret store no longer has it.
- `setText` on a secret snippet updates the secret store, not the file.
- `update(_:)` with a non-empty `text` on a secret snippet keeps `""`.
- `remove(id:)` deletes the secret entry.
- A throwing `SecretStore` (`FailingSecretStore` test double) makes
  `setSecret(true)` throw and leaves JSON and flag unchanged.
- `save()` leaves the file with mode `0600`.

Manual checklist (README):

1. Make a snippet secret → Keychain Access shows one "CopyStack" item; the
   JSON file has `"text" : ""` for it.
2. Quit, relaunch, press its shortcut → macOS asks once for Keychain access
   (Always Allow) → text pastes.
3. With Maccy or Raycast clipboard history running, paste any snippet → it
   does not appear in the history.
4. Turn "Store in Keychain" off → text is back in the JSON file.
5. Toggle "Launch at login" on → System Settings → General → Login Items
   lists CopyStack; log out/in → CopyStack is running.
6. `ls -l snippets.json` shows `-rw-------`.

## Documentation

README gains "Secret snippets" (what goes to the Keychain, the one-time
prompt after each update on ad-hoc builds, how to delete the item in Keychain
Access, that `brew zap` leaves it) and "Launch at login" sections. The cask
caveats mention the Keychain prompt.

## Compatibility

- Deployment target stays macOS 14 (`SMAppService` is 13+).
- Existing `snippets.json` files load unchanged.
- Version: 0.2.0.
