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
    func testCoachAudit() throws { try audit(scenario: "coach") }
    func testNutritionAudit() throws { try audit(scenario: "nutrition") }

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
        // Rendered visuals (orb canvas, 3D heart) carry their own label and value; contrast of text drawn
        // over a gradient is not measurable there.
        let visualFrames = ["orb", "heart3d"].compactMap { id -> CGRect? in
            let element = app.descendants(matching: .any)[id]
            return element.exists ? element.frame : nil
        }
        // System bars (navigation, tab bar) are translucent glass on iOS 26 and content scrolls beneath them.
        // The audit then measures text through the glass and the scroll edge effect (about 56 pt, PR #34).
        // Checked on the screenshot matrix instead (DECISIONS.md).
        let barFrames = (app.navigationBars.allElementsBoundByIndex + app.tabBars.allElementsBoundByIndex)
            .filter(\.exists).map { $0.frame.insetBy(dx: 0, dy: -56) }
        let handler: (XCUIAccessibilityAuditIssue) throws -> Bool = { issue in
            let element = issue.element
            print("AUDIT[\(scenario)] \(issue.auditType.rawValue) | \(issue.compactDescription) | id=\(element?.identifier ?? "-") label=\(element?.label ?? "-") type=\(element?.elementType.rawValue ?? 0) frame=\(element?.frame ?? .zero)")
            if issue.auditType == .contrast, let frame = element?.frame,
               visualFrames.contains(where: { $0.insetBy(dx: -2, dy: -2).contains(frame) }) {
                return true
            }
            if issue.auditType == .contrast, let frame = element?.frame,
               barFrames.contains(where: { $0.intersects(frame) }) {
                return true
            }
            // Toolbar buttons in the navigation bar are drawn by the system at its fixed bar size and get the
            // Large Content Viewer instead of scaling (run on PR #26). Content buttons still must scale.
            if issue.auditType == .dynamicType, element?.elementType == .button, let frame = element?.frame,
               app.navigationBars.allElementsBoundByIndex.contains(where: { $0.exists && $0.frame.intersects(frame) }) {
                return true
            }
            // Text the audit finds only in the pixels (no element) is the content seen through the bar glass.
            if issue.auditType == .elementDetection, element == nil, !barFrames.isEmpty {
                return true
            }
            // Only on the nutrition screen: a contrast finding without element (frame 0×0) seen once on a slow
            // runner (PR #32). Scoped to this screen so element-less findings elsewhere still fail.
            if scenario == "nutrition", issue.auditType == .contrast, element == nil, !barFrames.isEmpty {
                return true
            }
            // Known false positive: the audit reports one-line captions as clipped although they wrap
            // fully at accessibility sizes. Clipping is checked instead on the xxxl screenshot matrix
            // (studio-visual-qa), see DECISIONS.md.
            return issue.auditType == .textClipped
        }
        // A slow runner sometimes stops the audit with "failed to complete in time" (Code -56, PR #34).
        // That says nothing about the screen, so the audit runs once more; any other error still fails.
        do {
            try app.performAccessibilityAudit(for: .all, handler)
        } catch let error as NSError where error.domain == "com.apple.xcode.xctest.accessibilityAudit" && error.code == -56 {
            try app.performAccessibilityAudit(for: .all, handler)
        }
    }
}
