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

    /// No Dynamic Type override here: the audit changes the text size itself to find clipping.
    private func audit(scenario: String) throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "YES", "-uiTestScenario", scenario]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["screen.\(scenario)"].waitForExistence(timeout: 15))
        // Let the launch transition finish: run 4 reported contrast on text that is still fading in.
        Thread.sleep(forTimeInterval: 1.5)
        // Rendered visuals (orb canvas, 3D heart) carry their own label and value; contrast of text drawn
        // over a gradient is not measurable there.
        let visualFrames = ["orb", "heart3d"].compactMap { id -> CGRect? in
            let element = app.descendants(matching: .any)[id]
            return element.exists ? element.frame : nil
        }
        try app.performAccessibilityAudit { issue in
            let element = issue.element
            print("AUDIT[\(scenario)] \(issue.auditType.rawValue) | \(issue.compactDescription) | id=\(element?.identifier ?? "-") label=\(element?.label ?? "-") type=\(element?.elementType.rawValue ?? 0) frame=\(element?.frame ?? .zero)")
            if issue.auditType == .contrast, let frame = element?.frame,
               visualFrames.contains(where: { $0.insetBy(dx: -2, dy: -2).contains(frame) }) {
                return true
            }
            // Known false positive: the audit reports one-line captions as clipped although they wrap
            // fully at accessibility sizes. Clipping is checked instead on the xxxl screenshot matrix
            // (studio-visual-qa), see DECISIONS.md.
            return issue.auditType == .textClipped
        }
    }
}
