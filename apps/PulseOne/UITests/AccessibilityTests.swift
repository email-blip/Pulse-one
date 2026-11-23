import XCTest

/// Runs Apple's built-in accessibility audit (contrast, hit regions, labels, Dynamic Type clipping …).
@MainActor
final class AccessibilityTests: XCTestCase {
    func testStartAudit() throws { try audit(scenario: "start") }
    func testScanningAudit() throws { try audit(scenario: "scanning") }
    func testLiveAudit() throws { try audit(scenario: "live") }
    func testHeartAudit() throws { try audit(scenario: "heart") }
    func testDevicesAudit() throws { try audit(scenario: "devices") }
    func testOnboardingAudit() throws { try audit(scenario: "onboarding") }
    func testTodayAudit() throws { try audit(scenario: "today") }
    func testHealthAudit() throws { try audit(scenario: "health") }
    func testHealthDetailAudit() throws { try audit(scenario: "healthDetail") }
    func testIntelligenceAudit() throws { try audit(scenario: "intelligence") }
    /// The stored consultation of the test scenario, opened from the Analyse tab.
    func testConsultationAudit() throws {
        try audit(scenario: "intelligence", screen: "consultation") { app in
            let row = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Seit ein paar Tagen müde")).firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 15))
            row.tap()
        }
    }
    /// Recovery score with its building blocks, opened from the rings on TODAY.
    func testScoreAudit() throws {
        try audit(scenario: "today", screen: "score") { app in
            let ring = app.buttons["today.score.recovery"]
            XCTAssertTrue(ring.waitForExistence(timeout: 15))
            ring.tap()
        }
    }
    func testCoachAudit() throws { try audit(scenario: "coach") }
    func testInsightNormalAudit() throws { try audit(scenario: "insightNormal") }
    func testInsightNightsAudit() throws { try audit(scenario: "insightNights") }
    func testInsightGapAudit() throws { try audit(scenario: "insightGap") }

    /// No Dynamic Type override here: the audit changes the text size itself to find clipping.
    private func audit(scenario: String, screen: String? = nil, prepare: ((XCUIApplication) -> Void)? = nil) throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "YES", "-uiTestScenario", scenario]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["screen.\(scenario)"].waitForExistence(timeout: 15))
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
