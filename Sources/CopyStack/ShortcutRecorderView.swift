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
