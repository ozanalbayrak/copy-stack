# CopyStack

A tiny macOS menu bar app for text you type over and over — an email
address, Slack slash commands, a meeting link. Each snippet gets its own
global keyboard shortcut; press it and the text is pasted into whatever app
is focused. Your real clipboard is left exactly as it was.

## Install

### Homebrew

```bash
brew install --cask ozanalbayrak/tap/copystack
```

The cask clears the quarantine flag for you, so the Gatekeeper step below is
not needed. Apple silicon only for now.

### Manual download

Grab the latest `CopyStack-<version>.zip` from the
[Releases page](https://github.com/ozanalbayrak/copy-stack/releases), unzip
it and move `CopyStack.app` to `/Applications`.

Releases are not notarized (that needs a paid Apple Developer account), so
macOS refuses to open the app the first time:

1. Double-click `CopyStack.app` — macOS says it could not verify the app.
2. Open **System Settings → Privacy & Security**, scroll down, click
   **Open Anyway** next to the CopyStack message and confirm.

Or, from a terminal: `xattr -d com.apple.quarantine /Applications/CopyStack.app`.

Because releases are ad-hoc signed, macOS treats every update as a new app:
after updating, remove CopyStack from the Accessibility list and add the new
copy again.

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

## Pasteboard privacy (macOS 15.4 and later)

To restore your clipboard after a paste, CopyStack has to read it first. On
macOS 15.4 and later the system may ask "CopyStack would like to paste from
<app>" the first time this happens — choose **Always Allow**. You can change
that choice later under **System Settings → Privacy & Security** (the
*Pasteboard* section on macOS 26). If access is denied, CopyStack skips the
paste instead of risking your clipboard.

## Usage

1. Click the clipboard icon in the menu bar → **Settings…**
2. Press **+** to add a snippet, give it a name and text.
3. Click the **Shortcut** field and press a key combination (at least one of
   ⌘ ⌃ ⌥ plus a key — ⇧ on its own isn't enough, and ⌘V is reserved).
   Shortcuts must be unique across snippets.
4. Focus any app and press the shortcut. Clicking a snippet in the menu
   pastes it too.

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

Snippets are stored in
`~/Library/Application Support/CopyStack/snippets.json`.

## Development

```bash
swift test    # unit tests for the Core module
swift build   # compile everything
```

`swift test` never touches your Keychain. To run the one Keychain integration
test against the login Keychain (it creates and deletes a throwaway item):

```bash
COPYSTACK_KEYCHAIN_TESTS=1 swift test --filter KeychainSecretStoreTests
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

## Releasing

Push a version tag and GitHub Actions builds, tests and publishes the zip:

```bash
git tag v0.2.0
git push origin v0.2.0
```

`Scripts/release.sh 0.2.0` produces the same zip locally.

If the repository has a `TAP_GITHUB_TOKEN` secret (a fine-grained personal
access token with *Contents: read and write* on
[`ozanalbayrak/homebrew-tap`](https://github.com/ozanalbayrak/homebrew-tap)),
the workflow also bumps the Homebrew cask to the new version. Without it, edit
`Casks/copystack.rb` in the tap by hand (version + SHA-256 printed in the
release notes).

## Roadmap

- Picker popup: one hotkey opens a searchable list of all snippets.

## License

[MIT](LICENSE)
