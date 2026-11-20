import XCTest

/// Runs Apple's built-in accessibility audit (contrast, hit regions, labels, Dynamic Type clipping …).
@MainActor
final class AccessibilityTests: XCTestCase {
    func testStartAudit() throws { try audit(scenario: "start") }
    func testScanningAudit() throws { try audit(scenario: "scanning") }
    func testLiveAudit() throws { try audit(scenario: "live") }
    func testHeartAudit() throws { try audit(scenario: "heart") }

    /// No Dynamic Type override here: the audit changes the text size itself to find clipping.
    private func audit(scenario: String) throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "YES", "-uiTestScenario", scenario]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["screen.\(scenario)"].waitForExistence(timeout: 15))
        try app.performAccessibilityAudit { issue in
            let element = issue.element
            print("AUDIT[\(scenario)] \(issue.auditType.rawValue) | \(issue.compactDescription) | id=\(element?.identifier ?? "-") label=\(element?.label ?? "-") type=\(element?.elementType.rawValue ?? 0) frame=\(element?.frame ?? .zero)")
            // The orb is a decorative Canvas with its own label and value; contrast is not measurable there.
            // Same for the 3D heart: a rendered scene, not text.
            return ["orb", "heart3d"].contains(element?.identifier ?? "") && issue.auditType == .contrast
        }
    }
}
