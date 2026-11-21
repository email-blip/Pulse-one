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
    func testCoachAudit() throws { try audit(scenario: "coach") }
    func testNutritionAudit() throws { try audit(scenario: "nutrition") }

    /// No Dynamic Type override here: the audit changes the text size itself to find clipping.
    private func audit(scenario: String) throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "YES", "-uiTestScenario", scenario]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["screen.\(scenario)"].waitForExistence(timeout: 15))
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
        // The audit then measures text through the glass. Checked on the screenshot matrix instead (DECISIONS.md).
        let barFrames = (app.navigationBars.allElementsBoundByIndex + app.tabBars.allElementsBoundByIndex)
            .filter(\.exists).map { $0.frame.insetBy(dx: 0, dy: -32) }
        try app.performAccessibilityAudit { issue in
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
    }
}
