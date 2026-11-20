import XCTest

@MainActor
final class InteractionTests: XCTestCase {
    /// Without a test scenario the real Bluetooth store runs: no test banner, no invented values.
    func testRealModeShowsNoTestDataAndOffersScan() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "YES"]
        app.launch()
        XCTAssertTrue(app.buttons["scan"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.descendants(matching: .any)["testBanner"].exists)
        XCTAssertTrue(app.staticTexts["Noch keine echten Messwerte. Verbinde deinen Ring und miss den Puls."].exists)
    }

    /// Test scenarios must always be marked as such.
    func testScenarioIsLabelledAsTestView() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "YES", "-uiTestScenario", "live"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["testBanner"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["stopMeasure"].exists)
    }

    func testScanListShowsColmiRingOnly() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "YES", "-uiTestScenario", "scanning"]
        app.launch()
        XCTAssertTrue(app.buttons["ring.R03_1A2B"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["ring.Kopfhörer"].exists)
    }

    /// The Heart Chamber opens from the main screen, keeps the test label and closes again.
    func testHeartChamberOpensAndCloses() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "YES", "-uiTestScenario", "connected"]
        app.launch()
        let open = app.buttons["openHeart"]
        XCTAssertTrue(open.waitForExistence(timeout: 15))
        open.tap()
        XCTAssertTrue(app.descendants(matching: .any)["heart3d"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.descendants(matching: .any)["testBanner"].exists)
        app.buttons["closeHeart"].tap()
        XCTAssertTrue(open.waitForExistence(timeout: 10))
    }
}
