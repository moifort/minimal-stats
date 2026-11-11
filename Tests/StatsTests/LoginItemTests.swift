import XCTest
import ServiceManagement
@testable import Stats

final class LoginItemTests: XCTestCase {

    func testRegistersOnFirstLaunchOnly() {
        XCTAssertEqual(AppDelegate.loginItemAction(status: .notRegistered, registeredBefore: false), .register)
        XCTAssertEqual(AppDelegate.loginItemAction(status: .notFound, registeredBefore: false), .register)
    }

    func testItemRemovedByTheUserStaysRemoved() {
        XCTAssertEqual(AppDelegate.loginItemAction(status: .notRegistered, registeredBefore: true), .none)
    }

    func testExistingRegistrationIsOnlyRemembered() {
        // Installs registered by earlier versions, which had no flag
        XCTAssertEqual(AppDelegate.loginItemAction(status: .enabled, registeredBefore: false), .markRegistered)
        XCTAssertEqual(AppDelegate.loginItemAction(status: .requiresApproval, registeredBefore: false), .markRegistered)
        XCTAssertEqual(AppDelegate.loginItemAction(status: .enabled, registeredBefore: true), .none)
    }
}
