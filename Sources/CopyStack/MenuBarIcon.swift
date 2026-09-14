import AppKit

/// The menu bar glyph: a stepped stack of two bars behind a card with a
/// knocked-out line — the same object as the app icon, reduced to three
/// filled shapes.
///
/// Drawn in code from the design handoff's 18-unit geometry
/// (`design/design_handoff_copystack_icon/README.md`) so it stays crisp at
/// every scale factor and needs no resource bundle. Marked as a template so
/// macOS tints it for light, dark and highlighted menu bar states.
enum MenuBarIcon {
    static let image: NSImage = {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            let path = NSBezierPath()
            path.windingRule = .evenOdd
            // Back bar
            path.appendRoundedRect(NSRect(x: 5.7, y: 1.5, width: 6.6, height: 1.6), xRadius: 0.8, yRadius: 0.8)
            // Mid bar
            path.appendRoundedRect(NSRect(x: 4.1, y: 3.9, width: 9.8, height: 1.6), xRadius: 0.8, yRadius: 0.8)
            // Card with the snippet line knocked out (even-odd)
            path.appendRoundedRect(NSRect(x: 2.1, y: 6.4, width: 13.8, height: 10.1), xRadius: 2.3, yRadius: 2.3)
            path.appendRoundedRect(NSRect(x: 4.6, y: 10.2, width: 6.4, height: 1.9), xRadius: 0.95, yRadius: 0.95)
            NSColor.black.setFill()
            path.fill()
            return true
        }
        image.isTemplate = true
        return image
    }()
}
