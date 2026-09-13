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
