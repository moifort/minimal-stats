import XCTest
import Carbon.HIToolbox
@testable import Stats

final class GlobalHotKeyTests: XCTestCase {

    func testPopoverShortcutIsControlOptionCommandS() {
        XCTAssertEqual(GlobalHotKey.togglePopover.keyCode, UInt32(kVK_ANSI_S))
        XCTAssertEqual(GlobalHotKey.togglePopover.modifiers, UInt32(controlKey | optionKey | cmdKey))
    }

    func testShortcutIsHeldUntilReleased() {
        // An unusual combination, so a running Stats or another app cannot hold it
        let shortcut = GlobalHotKey.Shortcut(keyCode: UInt32(kVK_F19), modifiers: UInt32(controlKey | optionKey | cmdKey | shiftKey))
        var hotKey = GlobalHotKey(shortcut) {}
        XCTAssertNotNil(hotKey)
        XCTAssertNil(GlobalHotKey(shortcut) {}, "a combination can only be registered once")
        hotKey = nil
        XCTAssertNotNil(GlobalHotKey(shortcut) {})
    }
}
