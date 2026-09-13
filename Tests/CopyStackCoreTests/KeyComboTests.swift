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
