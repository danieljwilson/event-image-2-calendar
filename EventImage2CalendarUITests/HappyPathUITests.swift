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
        if settingsButton.waitForExistence(timeout: 3) {
            settingsButton.tap()
            // Settings should show version info
            let versionLabel = app.staticTexts["Version"]
            XCTAssertTrue(versionLabel.waitForExistence(timeout: 3))
        }
    }
}
