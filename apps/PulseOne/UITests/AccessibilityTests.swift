import XCTest

/// Runs Apple's built-in accessibility audit (contrast, hit regions, labels, Dynamic Type clipping …).
@MainActor
final class AccessibilityTests: XCTestCase {
    func testStartAudit() throws { try audit(scenario: "start") }
    func testScanningAudit() throws { try audit(scenario: "scanning") }
    func testLiveAudit() throws { try audit(scenario: "live") }
    func testDevicesAudit() throws { try audit(scenario: "devices") }
    func testOnboardingAudit() throws { try audit(scenario: "onboarding") }
    func testDashboardAudit() throws { try audit(scenario: "dashboard") }
    /// The tile editor (team 03): arrows, size menu and on/off switch per tile.
    func testDashboardEditAudit() throws { try audit(scenario: "dashboardEdit", screen: "dashboard") }
    func testTimelineAudit() throws { try audit(scenario: "timeline") }
    /// ROOK's "Warum?" from the dashboard, with the numbers behind the statement.
    func testWhyAudit() throws {
        try audit(scenario: "dashboard", screen: "why") { app in
            let why = app.buttons["rook.why"]
            XCTAssertTrue(why.waitForExistence(timeout: 15))
            why.tap()
        }
    }
    func testIntelligenceAudit() throws { try audit(scenario: "intelligence") }
    func testCoachAudit() throws { try audit(scenario: "coach") }
    /// ROOK's two demonstration cases (team 04) and the "Warum?" sheet.
    func testRookPositiveAudit() throws { try audit(scenario: "rookPositive") }
    func testRookClarifyAudit() throws { try audit(scenario: "rookClarify") }
    func testRookWhyAudit() throws {
        try audit(scenario: "rookClarify", screen: "why") { app in
            let why = app.buttons["rook.why"]
            XCTAssertTrue(why.waitForExistence(timeout: 15))
            why.tap()
        }
    }
    func testInsightNormalAudit() throws { try audit(scenario: "insightNormal") }
    func testInsightNightsAudit() throws { try audit(scenario: "insightNights") }
    func testInsightGapAudit() throws { try audit(scenario: "insightGap") }
    /// DesignKit component preview (team 02): tokens, tile, buttons, chips, orb states.
    func testDesignKitAudit() throws { try audit(scenario: "designKit") }

    /// Scenarios whose start screen identifier differs from the scenario name.
    private static let startScreens = ["dashboardEdit": "dashboard"]

    // Rebuild M1 screens (team 06). Skipped until integrated; failures once `PULSE_M1_STRICT=1`.
    func testM1DashboardAudit() throws { try auditM1(.dashboard) }
    func testM1DashboardEditAudit() throws { try auditM1(.dashboardEdit) }
    func testM1TimelineAudit() throws { try auditM1(.timeline) }
    func testM1HypnogramAudit() throws { try auditM1(.hypnogram) }
    func testM1WhyAudit() throws { try auditM1(.why) }
    func testM1WorkoutAudit() throws { try auditM1(.workout) }
    func testM1WorkoutSummaryAudit() throws { try auditM1(.workoutSummary) }

    private func auditM1(_ place: M1.Place) throws {
        let app = M1.launch()
        try M1.skipIfMissing { try M1.open(place, in: app) }
        // Same settle time as the other screens: text must not be measured mid-fade.
        Thread.sleep(forTimeInterval: 2)
        try AuditPolicy.run(app, name: "m1-\(place.rawValue)")
    }

    /// No Dynamic Type override here: the audit changes the text size itself to find clipping.
    private func audit(scenario: String, screen: String? = nil, prepare: ((XCUIApplication) -> Void)? = nil) throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "YES", "-uiTestScenario", scenario]
        app.launch()
        let start = prepare == nil ? (screen ?? scenario) : (Self.startScreens[scenario] ?? scenario)
        XCTAssertTrue(app.descendants(matching: .any)["screen.\(start)"].waitForExistence(timeout: 15))
        if let prepare {
            prepare(app)
            XCTAssertTrue(app.descendants(matching: .any)["screen.\(screen ?? scenario)"].waitForExistence(timeout: 15))
        }
        // Let the launch transition finish: run 4 reported contrast on text that is still fading in.
        // Tab screens load SwiftData queries and charts first; 1.5 s still caught text mid-fade on them (run 36).
        Thread.sleep(forTimeInterval: 3)
        try AuditPolicy.run(app, name: scenario) { issue, barFrames in
            // Only on the nutrition screen: a contrast finding without element (frame 0×0) seen once on a slow
            // runner (PR #32). Scoped to this screen so element-less findings elsewhere still fail.
            scenario == "nutrition" && issue.auditType == .contrast && issue.element == nil && !barFrames.isEmpty
        }
    }
}
