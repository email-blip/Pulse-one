import XCTest

@MainActor
final class InteractionTests: XCTestCase {
    /// Without a test scenario the real stores run: first-start setup, no test banner, no invented values,
    /// and the ring is reachable from the dashboard.
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

    private func launch(_ scenario: String, _ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "YES", "-uiTestScenario", scenario, "-AppleLanguages", "(de)",
                               "-AppleLocale", "de_DE"] + extra
        app.launch()
        return app
    }

    /// Team 03 acceptance: a tile moved in the editor keeps its place after the app restarts.
    func testMovedTileKeepsItsPlaceAfterRestart() {
        var app = launch("dashboardEdit", ["-resetDashboardLayout", "YES"])
        XCTAssertTrue(app.descendants(matching: .any)["screen.dashboard"].waitForExistence(timeout: 15))
        let moveUp = app.buttons["tile.metric.hrv_ring.moveUp"]
        XCTAssertTrue(moveUp.waitForExistence(timeout: 10))
        moveUp.tap()
        XCTAssertTrue(isBefore("tile.metric.hrv_ring", "tile.metric.resting_heart_rate", in: app))
        app.terminate()

        app = launch("dashboardEdit")
        XCTAssertTrue(app.descendants(matching: .any)["screen.dashboard"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["tile.metric.hrv_ring"].waitForExistence(timeout: 10))
        XCTAssertTrue(isBefore("tile.metric.hrv_ring", "tile.metric.resting_heart_rate", in: app),
                      "moved tile lost its place after the restart")
        // Leave the standard order for the screenshots of this scenario.
        app.buttons["tile.metric.hrv_ring.moveDown"].tap()
        XCTAssertTrue(isBefore("tile.metric.resting_heart_rate", "tile.metric.hrv_ring", in: app))
    }

    /// Reading order of two tiles: row first, then left to right.
    private func isBefore(_ first: String, _ second: String, in app: XCUIApplication) -> Bool {
        let a = app.buttons[first].frame, b = app.buttons[second].frame
        return abs(a.minY - b.minY) < 4 ? a.minX < b.minX : a.minY < b.minY
    }

    /// Team 03 acceptance: the cursor shows the picked measurement with its own original time; in the gap
    /// (ring off for 70 minutes, until 83 minutes before the test time) it picks nothing.
    func testCursorShowsOriginalTimeAndGapSelectsNothing() throws {
        let app = launch("timeline")
        XCTAssertTrue(app.descendants(matching: .any)["screen.timeline"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.descendants(matching: .any)["testBanner"].exists)
        let chart = app.descendants(matching: .any)["timeline.chart"]
        XCTAssertTrue(chart.waitForExistence(timeout: 10))
        let selection = app.descendants(matching: .any)["timeline.selection"]

        chart.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)).tap()
        XCTAssertTrue(selection.waitForExistence(timeout: 5))
        let pulse = firstRow(selection.label)
        let match = try XCTUnwrap(pulse.range(of: #"gemessen \d{2}:\d{2}"#, options: .regularExpression),
                                  "no original time in: \(pulse)")
        let minute = Int(pulse[match].suffix(2)) ?? -1
        XCTAssertEqual(minute % 5, 0, "cursor time instead of the measurement's own time: \(pulse)")

        // 24-hour window ending at the test time: the gap sits at 0.894–0.942 of the width.
        let before = selection.label
        chart.coordinate(withNormalizedOffset: CGVector(dx: 0.918, dy: 0.2)).tap()
        // The tap resolves after the hold-to-scrub gesture gives up; wait for the readout to move.
        let moved = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label != %@", before), object: selection)
        XCTAssertEqual(XCTWaiter().wait(for: [moved], timeout: 5), .completed, "the cursor did not move: \(before)")
        let gap = firstRow(selection.label)
        XCTAssertTrue(gap.contains("keine Messung"), "the gap selected a value: \(gap)")
        XCTAssertFalse(gap.contains("gemessen"))
    }

    /// The pulse track comes first in the readout.
    private func firstRow(_ label: String) -> String {
        String(label.split(separator: ";").first ?? "")
    }

    /// The hypnogram names phase, start and end of a tapped interval.
    func testHypnogramShowsPickedPhase() {
        let app = launch("timelineHypnogram")
        XCTAssertTrue(app.descendants(matching: .any)["screen.timeline"].waitForExistence(timeout: 15))
        let segment = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "hypnogram.segment.")).element(boundBy: 1)
        XCTAssertTrue(segment.waitForExistence(timeout: 10))
        segment.tap()
        let picked = app.descendants(matching: .any)["hypnogram.selection"]
        XCTAssertTrue(picked.waitForExistence(timeout: 5))
        let timed = NSPredicate(format: "label MATCHES %@", #".*\d{2}:\d{2}–\d{2}:\d{2}.*"#)
        let found = XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: timed, object: picked)], timeout: 5)
        XCTAssertEqual(found, .completed, "no phase interval in: \(picked.label)")
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
