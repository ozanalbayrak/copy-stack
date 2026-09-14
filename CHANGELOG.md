# Changelog

All notable changes to CopyStack are listed here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); the release workflow
publishes the section matching the pushed tag as the GitHub release notes.

## [Unreleased]

## [0.2.0] - 2026-09-14

### Added
- **Secret snippets.** Turn on *Store in Keychain* for a snippet and its text
  moves out of `snippets.json` into your login Keychain (one item, "CopyStack
  secret snippets"). The editor shows a masked panel with *Reveal* / *Hide*;
  the Keychain is only read when you paste or reveal, never at launch.
- **Launch at login** toggle in Settings, with a hint when macOS needs you to
  approve the login item.

### Changed
- Every paste is marked as concealed and transient on the pasteboard, so
  clipboard managers (Maccy, Raycast, Paste) don't record it.
- `snippets.json` is written with owner-only permissions (`0600`).
- Revealed secret edits are committed to the Keychain after a short pause
  instead of on every keystroke.

### Fixed
- The Accessibility banner in Settings now updates as soon as the permission
  is granted instead of staying stale until the next app switch.
- A secret snippet with no stored text is skipped with a log message instead
  of pasting an empty string.

### Notes
- Files written by 0.1.x load unchanged. Downgrading to 0.1.x is not
  supported: it drops the secret flag on the next save.
- After each update of an ad-hoc-signed build, macOS asks again for
  Accessibility and (on first use) Keychain access — choose *Always Allow*.

## [0.1.1] - 2026-09-13

### Changed
- Release pipeline: GitHub Actions builds, tests and publishes the zip on
  every `v*` tag and bumps the Homebrew cask. No changes to the app itself.

## [0.1.0] - 2026-09-13

### Added
- Menu bar app that stores named text snippets and pastes any of them into
  the frontmost app with a per-snippet global keyboard shortcut.
- Pasting borrows the system pasteboard for a moment and restores your
  previous clipboard, including images and rich text.
- Settings window to add, edit and delete snippets and record shortcuts;
  duplicate shortcuts and ⌘V are rejected.
- Gatekeeper-, Accessibility- and pasteboard-privacy-aware: the app explains
  what to grant and never clears your clipboard when a read is denied.

[Unreleased]: https://github.com/ozanalbayrak/copy-stack/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/ozanalbayrak/copy-stack/compare/v0.1.1...v0.2.0
[0.1.1]: https://github.com/ozanalbayrak/copy-stack/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/ozanalbayrak/copy-stack/releases/tag/v0.1.0
