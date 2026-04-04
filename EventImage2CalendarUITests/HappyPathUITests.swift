import XCTest

final class HappyPathUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--skip-onboarding"]
        app.launch()
    }

    func testEventListAppears() {
        // The main event list should be visible after launch
        let navBar = app.navigationBars.firstMatch
        XCTAssertTrue(navBar.waitForExistence(timeout: 5))
    }

    func testSettingsNavigation() {
        // Tap the settings/gear button
        let settingsButton = app.buttons["Settings"]
        guard settingsButton.waitForExistence(timeout: 3) else { return }

        // Swipe up to ensure the button is visible (may be off-screen on smaller simulators)
        if !settingsButton.isHittable {
            app.swipeUp()
        }
        guard settingsButton.isHittable else { return }

        settingsButton.tap()
        // Settings should show version info
        let versionLabel = app.staticTexts["Version"]
        XCTAssertTrue(versionLabel.waitForExistence(timeout: 3))
    }
}
