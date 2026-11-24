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

        tapPulseTrack(chart, at: 0.5, in: app)
        XCTAssertTrue(selection.waitForExistence(timeout: 5), "no read-out; chart: \(chart.value as? String ?? "-")")
        let pulse = firstRow(selection.label)
        let match = try XCTUnwrap(pulse.range(of: #"gemessen \d{2}:\d{2}"#, options: .regularExpression),
                                  "no original time in: \(pulse)")
        let minute = Int(pulse[match].suffix(2)) ?? -1
        XCTAssertEqual(minute % 5, 0, "cursor time instead of the measurement's own time: \(pulse)")

        // 24-hour window ending at the test time: the gap sits at 0.894–0.942 of the width.
        let before = selection.label
        tapPulseTrack(chart, at: 0.918, in: app)
        let moved = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label != %@", before), object: selection)
        XCTAssertEqual(XCTWaiter().wait(for: [moved], timeout: 5), .completed,
                       "the cursor did not move: \(before); chart: \(chart.value as? String ?? "-")")
        let gap = firstRow(selection.label)
        XCTAssertTrue(gap.contains("keine Messung"), "the gap selected a value: \(gap)")
        XCTAssertFalse(gap.contains("gemessen"))
    }

    /// Taps the pulse track (first row of the chart) at a fraction of its width. The read-out above the chart
    /// grows after the first tap and pushes the chart down; a fixed point inside the chart then sat under the
    /// floating tab bar and the tap went to the bar. Scrolls the row clear of the bar first, by dragging the
    /// screen title area (never the chart, where a drag would pan or scrub).
    private func tapPulseTrack(_ chart: XCUIElement, at fraction: CGFloat, in app: XCUIApplication) {
        let row = CGVector(dx: 0, dy: 70)
        let point = chart.coordinate(withNormalizedOffset: CGVector(dx: fraction, dy: 0)).withOffset(row)
        let bar = app.tabBars.firstMatch
        let limit = (bar.exists ? bar.frame.minY : app.frame.maxY) - 60
        if point.screenPoint.y > limit {
            let readout = app.descendants(matching: .any)["timeline.selection"]
            let handle = readout.exists ? readout : app.descendants(matching: .any)["testBanner"]
            let start = handle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            let distance = point.screenPoint.y - limit + 120
            start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -distance)),
                        withVelocity: .slow, thenHoldForDuration: 0.3)
            Thread.sleep(forTimeInterval: 0.5)
        }
        chart.coordinate(withNormalizedOffset: CGVector(dx: fraction, dy: 0)).withOffset(row).tap()
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
