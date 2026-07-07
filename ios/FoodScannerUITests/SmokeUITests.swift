import XCTest

/// Dumb, robust smoke test: launch → tab bar exists → tap Scan → on the
/// Simulator (no camera), the calm "Camera unavailable" state appears instead
/// of a crash or a blank screen. Kept minimal on purpose — this is a smoke
/// test, not a full flow test.
final class SmokeUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testLaunchThenScanTabShowsCameraUnavailableOnSimulator() {
        let app = XCUIApplication()
        app.launch()

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5), "Tab bar should exist right after launch (guest-first — no login wall).")

        let scanTab = app.tabBars.buttons["Scan"]
        XCTAssertTrue(scanTab.waitForExistence(timeout: 5), "Scan tab should be present in the 4-tab shell.")
        scanTab.tap()

        let unavailable = app.staticTexts["Camera unavailable"]
        XCTAssertTrue(
            unavailable.waitForExistence(timeout: 5),
            "Simulator has no camera — expect the calm unavailable state, not a crash."
        )
    }
}
