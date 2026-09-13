# CopyStack — Design Spec

**Date:** 2026-09-13
**Status:** Approved

## Problem

Certain strings get typed by hand many times a day — an email address, a few
Slack slash commands, a meeting link. Keeping them on the system clipboard is
not an option because the clipboard is constantly overwritten. CopyStack keeps a
small, user-editable set of text snippets and pastes any of them into the
frontmost application with a dedicated global keyboard shortcut.

## Goals

- Store a list of named text snippets, each with an optional global shortcut.
- Pressing a snippet's shortcut pastes its text into whatever app is focused.
- Snippets and shortcuts are editable from a menu bar icon.
- The user's real clipboard is left as it was after a paste.
- Native, dependency-free, small.

## Non-goals (for now)

- A single "picker" hotkey that opens a searchable popup (planned as a
  follow-up; the design leaves room for it).
- Launch at login.
- Custom app icon.
- Import/export of snippets.
- Rich text or image snippets — text only.

## Decisions

| Question | Decision |
|---|---|
| Shortcut model | One global shortcut per snippet. |
| Paste mechanism | Temporarily place text on `NSPasteboard.general`, post ⌘V via `CGEvent`, restore the previous pasteboard contents. |
| Hotkey capture | Carbon `RegisterEventHotKey`. Works without Accessibility permission and consumes the keystroke. Deprecated but still functional and widely used (Maccy, Raycast, Alfred). |
| UI | Menu bar menu (paste by clicking) plus a separate Settings window for editing. |
| Stack | Swift 6, SwiftUI + AppKit, Swift Package (no `.xcodeproj`). Target macOS 14+. |
| Persistence | JSON file at `~/Library/Application Support/CopyStack/snippets.json`. |
| Language | Everything in the repo — code, comments, docs, commit messages, UI strings — is English. |

Alternatives considered for hotkey capture: `sindresorhus/KeyboardShortcuts`
(adds a dependency and a second source of truth for shortcuts in UserDefaults)
and a `CGEvent` tap (requires Accessibility for capture itself and is overkill).

## Architecture

Single Swift Package with two targets and one test target.

```
copy-stack/
├── Package.swift
├── Sources/
│   ├── CopyStackCore/              # Foundation-only, unit-testable
│   │   ├── Snippet.swift
│   │   ├── KeyCombo.swift
│   │   └── SnippetStore.swift
│   └── CopyStack/                  # Executable, AppKit/SwiftUI
│       ├── CopyStackApp.swift
│       ├── HotKeyManager.swift
│       ├── Paster.swift
│       ├── AccessibilityGate.swift
│       ├── MenuBarView.swift
│       ├── SettingsView.swift
│       └── ShortcutRecorderView.swift
├── Tests/CopyStackCoreTests/
├── Scripts/build-app.sh
└── Resources/Info.plist
```

`CopyStackCore` has no AppKit dependency so its logic can be tested with plain
XCTest. Carbon key codes and modifier flags are stored as raw integers in Core
to keep it free of Carbon imports; the app target does the translation.

### Data model

```swift
public struct Snippet: Identifiable, Codable, Equatable {
    public var id: UUID
    public var name: String        // Label shown in the menu, e.g. "Email"
    public var text: String        // Content to paste; may be multi-line
    public var shortcut: KeyCombo? // nil = no shortcut, reachable via menu only
}

public struct KeyCombo: Codable, Equatable, Hashable {
    public var keyCode: UInt32     // Carbon virtual key code (e.g. 14 = E)
    public var modifiers: UInt32   // Carbon modifier bitmask
    public var displayString: String { get } // "⌃⌥E"
}
```

`displayString` orders modifiers in the standard macOS order ⌃ ⌥ ⇧ ⌘. Key
names are resolved from the key code using a static table for letters, digits
and common keys; unknown codes fall back to `Key<code>`.

Validation rules enforced by `SnippetStore`:

- A `KeyCombo` must include at least one modifier.
- No two snippets may share the same `KeyCombo`. `store.conflict(for:excluding:)`
  returns the snippet that already owns a combo, if any.

### SnippetStore

`@MainActor final class SnippetStore: ObservableObject` with
`@Published var snippets: [Snippet]`.

- `init(fileURL:)` loads from disk. Missing or unreadable/undecodable file →
  empty list (unreadable file is logged, not fatal).
- `add()`, `remove(id:)`, `update(_:)` mutate and then `save()`.
- `save()` writes pretty-printed JSON atomically, creating the directory if
  needed.
- Default file URL: `~/Library/Application Support/CopyStack/snippets.json`.

### HotKeyManager

- Owns Carbon hotkey registrations. On app launch and on every change to
  `store.snippets`, it unregisters everything and re-registers every snippet that
  has a shortcut. Snippet counts are small; diffing is not worth the complexity.
- Each registration gets an incrementing `EventHotKeyID.id`; a dictionary maps
  that id back to `Snippet.id`.
- A single `InstallEventHandler` for `kEventHotKeyPressed` looks up the snippet
  and calls `Paster.paste(text:)`.
- `isEnabled` flag: the shortcut recorder sets it to `false` while recording so
  the pressed keys do not trigger a paste, and restores it afterward.

### Paster

Sequence on trigger, all on the main thread, queued so back-to-back triggers do
not interleave:

1. If Accessibility is not granted, do not paste. Show the system prompt via
   `AccessibilityGate.requestIfNeeded()` and return. (Without permission
   `CGEvent.post` silently does nothing; the user must learn why.)
2. Snapshot `NSPasteboard.general`: for every `NSPasteboardItem`, copy every
   `type` and its `data`. Remember the pasteboard `changeCount`.
3. `clearContents()` and `setString(text, forType: .string)`.
4. Post ⌘V: `CGEvent(keyboardEventSource:virtualKey: 9, keyDown: true)` with
   `flags = .maskCommand`, then the matching key-up. Explicitly setting flags
   means modifiers the user is still physically holding (⌃⌥ from the hotkey)
   are ignored.
5. After ~150 ms (`DispatchQueue.main.asyncAfter`), restore the snapshot: clear,
   then write each item back with all its types. If the snapshot was empty,
   leave the pasteboard empty.
6. Release the queue so the next paste can run.

### AccessibilityGate

- `isTrusted` → `AXIsProcessTrusted()`.
- `requestIfNeeded()` → `AXIsProcessTrustedWithOptions` with the prompt option,
  called once at launch and whenever a paste is attempted without permission.
- `openSystemSettings()` opens
  `x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility`.

### Menu bar (`MenuBarView`)

`MenuBarExtra` with a clipboard SF Symbol, `.menu` style:

```
Email                    ⌃⌥E
Slack /standup           ⌃⌥S
Meeting link
──────────────
Settings…                ⌘,
Quit CopyStack           ⌘Q
```

Clicking a snippet runs the same `Paster` flow. With no snippets a disabled
"No snippets yet" row is shown. `Settings…` opens the settings window via
`openWindow`. The app runs as an accessory (`LSUIElement = true` in Info.plist,
plus `NSApp.setActivationPolicy(.accessory)` in code so `swift run` behaves the
same).

### Settings window (`SettingsView`)

A `Window` scene, roughly 600×400.

- Top: a yellow banner when Accessibility is not granted, with an
  "Open System Settings" button. Refreshed when the window becomes key.
- Left: `List` of snippets bound to selection; `+` / `−` buttons underneath.
  `+` appends a snippet named "New Snippet" with empty text and selects it.
  `−` removes the selection.
- Right: editor for the selected snippet — `Name` text field, `Text`
  multi-line `TextEditor` in monospaced font, `Shortcut` recorder. Every edit is
  written straight to the store; there is no Save button.
- Empty selection shows a placeholder "Select or add a snippet".

### ShortcutRecorderView

`NSViewRepresentable` around a small `NSView` subclass:

- Idle: shows the current combo's `displayString` or "Click to record".
- Click → recording state, label "Press keys…", `HotKeyManager.isEnabled = false`.
- `keyDown`: if the event has at least one of ⌃⌥⇧⌘ and a non-modifier key,
  build a `KeyCombo` (mapping `NSEvent.modifierFlags` to Carbon flags) and
  check `store.conflict(for:excluding:)`. On conflict: stay in recording state,
  show "Already used by 'Email'" in red. Otherwise commit and return to idle.
- `Esc` cancels. Losing first-responder status cancels.
- A small `×` button clears the shortcut.
- On leaving recording state, `HotKeyManager.isEnabled = true`.

## Error handling

| Situation | Behaviour |
|---|---|
| Accessibility not granted at paste time | No paste; system permission prompt; banner in Settings. |
| Snippets file missing | Start with empty list. |
| Snippets file corrupt | Log to `os.Logger`, start with empty list, overwrite on next save. |
| Cannot write snippets file | Log; keep in-memory state; retry on next change. |
| `RegisterEventHotKey` fails (e.g. combo taken by another app) | Log with the combo; snippet stays in list without a working hotkey. |
| Pasteboard restore fails for a type | Skip that type, restore the rest. |

## Testing

Unit tests in `Tests/CopyStackCoreTests` (XCTest):

- `Snippet` and `KeyCombo` encode/decode round-trip; `shortcut: nil` survives.
- `KeyCombo.displayString`: modifier ordering ⌃⌥⇧⌘, letter/digit/named keys,
  unknown key code fallback.
- `SnippetStore`: add/remove/update persist to a temp directory and reload;
  missing file → empty; corrupt file → empty; `conflict(for:excluding:)` finds
  another snippet's combo and ignores the excluded id; combo with no modifiers
  is rejected.

`HotKeyManager`, `Paster`, and the recorder depend on live system APIs and are
verified manually. The README carries the checklist:

1. Build, launch, grant Accessibility when prompted.
2. Add a snippet, record ⌃⌥E.
3. Focus TextEdit, press ⌃⌥E → text appears.
4. Copy an image in Preview, press ⌃⌥E in TextEdit → text appears, then ⌘V
   in Preview still pastes the image.
5. Try to record ⌃⌥E on a second snippet → rejected with the owner's name.
6. Clear the shortcut → menu row loses its shortcut label, hotkey no longer
   fires.

## Build & distribution

`Scripts/build-app.sh`:

1. `swift build -c release`.
2. Assemble `build/CopyStack.app/Contents/{MacOS,Resources}`, copy the binary
   and `Resources/Info.plist` (`CFBundleIdentifier =
   com.ozanalbayrak.CopyStack`, `LSUIElement = true`, `LSMinimumSystemVersion =
   14.0`).
3. `codesign --force --sign "${CODESIGN_IDENTITY:--}"`.

Known trap: macOS ties the Accessibility grant to the app's code signature.
With ad-hoc signing the code hash changes on every build, so the permission is
lost after each rebuild. Setting `CODESIGN_IDENTITY` to an "Apple Development"
certificate (free with an Apple ID in Xcode) gives a stable designated
requirement and keeps the grant across builds. The README explains this.

## Future work

- Picker popup: one hotkey opens a list, type-to-filter, Enter pastes. The
  `Paster` and `SnippetStore` are already shaped for it.
- Launch at login via `SMAppService`.
