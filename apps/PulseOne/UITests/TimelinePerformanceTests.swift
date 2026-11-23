import XCTest

/// Scrubbing performance on a year of 5-minute heart rate (`neubauM1Year`, about 105 000 points).
/// Target (plan §8, Vorgaben M): fluid scrubbing at 60 fps, no permanent animation of hidden views.
///
/// The simulator is not an iPhone: these numbers find regressions and gross problems, they do not prove
/// 60 fps on the device (status level "Simulator"). Without a stored baseline XCTest only records the
/// values; `scripts/qa/perf-summary.py` writes them into the run summary.
@MainActor
final class TimelinePerformanceTests: XCTestCase {
    override func setUp() async throws {
        continueAfterFailure = true
    }

    /// Cursor dragged across the year view and the day view: time, CPU and memory per drag.
    func testScrubbingYearOfData() throws {
        let app = try openYearTimeline()
        let chart = M1.element(app, M1.Timeline.chart)
        let options = XCTMeasureOptions()
        options.iterationCount = 5
        measure(metrics: [XCTClockMetric(), XCTCPUMetric(application: app), XCTMemoryMetric(application: app)],
                options: options) {
            chart.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.4))
                .press(forDuration: 0.3, thenDragTo: chart.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.4)),
                       withVelocity: .slow, thenHoldForDuration: 0.1)
        }
        XCTAssertTrue(M1.element(app, M1.Timeline.selection).exists, "Cursor-Anzeige nach dem Ziehen fehlt")
    }

    /// Panning the timeline: frame rate and hitch time ratio from the system scroll signposts
    /// (Swift Charts' scrollable axis pans in a scroll view). Apple's guide: hitch ratio under 5 ms/s is good.
    func testPanningHitches() throws {
        let app = try openYearTimeline()
        let chart = M1.element(app, M1.Timeline.chart)
        let options = XCTMeasureOptions()
        options.iterationCount = 5
        measure(metrics: [XCTOSSignpostMetric.scrollingAndDecelerationMetric], options: options) {
            chart.swipeRight(velocity: .fast)
        }
    }

    /// Nothing may keep animating once a screen is hidden: CPU of the app idling on the timeline after the
    /// dashboard (orb, tiles) went off screen.
    func testIdleCPUWithDashboardHidden() throws {
        let app = try openYearTimeline()
        let options = XCTMeasureOptions()
        options.iterationCount = 3
        measure(metrics: [XCTCPUMetric(application: app)], options: options) {
            Thread.sleep(forTimeInterval: 5)
        }
    }

    private func openYearTimeline() throws -> XCUIApplication {
        let app = M1.launch("neubauM1Year")
        // Inserting a year of points takes a while on a CI simulator.
        try M1.skipIfMissing {
            try M1.require(app, M1.Screen.dashboard, step: "Dashboard (Jahresdaten)", timeout: 180)
            let tile = try M1.require(app, M1.Dashboard.heartRateTile, step: "Puls-Kachel")
            M1.reveal(tile, in: app)
            tile.tap()
            try M1.require(app, M1.Screen.timeline, step: "Verlauf")
            try M1.require(app, M1.Timeline.chart, step: "Spuren")
        }
        // Zoom out to the widest range the timeline offers (Jahr), if it shows the range picker.
        let year = app.buttons["Jahr"]
        if year.waitForExistence(timeout: 3) { year.tap() }
        Thread.sleep(forTimeInterval: 1)
        return app
    }
}
