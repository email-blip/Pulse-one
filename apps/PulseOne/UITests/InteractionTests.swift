import XCTest

@MainActor
final class InteractionTests: XCTestCase {
    /// Without a test scenario the real stores run: first-start setup, no test banner, no invented values,
    /// and the ring is reachable from TODAY.
    func testRealModeShowsNoTestDataAndOffersScan() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "YES"]
        app.launch()
        let next = app.buttons["setup.next"]
        XCTAssertTrue(next.waitForExistence(timeout: 15))
        XCTAssertFalse(app.descendants(matching: .any)["testBanner"].exists)
        app.buttons["setup.skipAll"].tap()
        let openRing = app.buttons["openRing"]
        XCTAssertTrue(openRing.waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "Noch keine Werte")).firstMatch.exists)
        openRing.tap()
        XCTAssertTrue(app.buttons["scan"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Noch keine echten Messwerte. Verbinde deinen Ring und miss den Puls."].exists)
    }

    /// The setup continues step by step and ends in the tab app.
    func testSetupLeadsToTabs() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "YES"]
        app.launch()
        let next = app.buttons["setup.next"]
        XCTAssertTrue(next.waitForExistence(timeout: 15))
        for _ in 0..<4 { app.buttons["setup.next"].tap() }
        app.buttons["setup.finish"].tap()
        XCTAssertTrue(app.tabBars.buttons["Verlauf"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Verlauf"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["openProfile"].firstMatch.waitForExistence(timeout: 5))
    }

    /// HEALTH lists kinds with data and opens the chart detail.
    func testHealthOpensDetail() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "YES", "-uiTestScenario", "health"]
        app.launch()
        let row = app.buttons["health.resting_heart_rate"]
        XCTAssertTrue(row.waitForExistence(timeout: 15))
        row.tap()
        XCTAssertTrue(app.descendants(matching: .any)["detail.chart"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["testBanner"].exists)
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

    /// The devices screen lists sources with their real stage and keeps the test label.
    func testDevicesScreenShowsStages() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "YES", "-uiTestScenario", "devices"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["device.colmi.r03"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.descendants(matching: .any)["device.apple.health"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["testBanner"].exists)
        let stage = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "Synchronisierung erfolgreich")).firstMatch
        XCTAssertTrue(stage.exists)
        // Old ring rows were migrated into the sample store and are listed per kind (Directive 3.1).
        let migrated = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "3 · zuletzt")).firstMatch
        XCTAssertTrue(migrated.exists)
        // Health synced but delivered nothing: the permission hint is shown.
        XCTAssertTrue(app.descendants(matching: .any)["healthPermissionHint"].exists)
        // Preferred source per kind (Review 3.2 §4).
        XCTAssertTrue(app.descendants(matching: .any)["preferredSources"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["preference.heart_rate"].exists)
    }
}
