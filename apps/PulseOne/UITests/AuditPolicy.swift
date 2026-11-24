import XCTest

/// The accessibility audit with the documented exclusions (DECISIONS.md) in one place, so every screen is
/// checked by the same rules. Everything not excluded here fails the test.
@MainActor
enum AuditPolicy {
    /// Runs the full audit on the current screen. `name` tags the log lines; `visualIDs` are rendered visuals
    /// (orb canvas, 3D heart) whose text contrast over a gradient cannot be measured; `extra` adds a
    /// screen-specific exclusion that must be justified at the call site.
    static func run(_ app: XCUIApplication, name: String, visualIDs: [String] = ["orb", "heart3d"],
                    extra: ((XCUIAccessibilityAuditIssue, _ barFrames: [CGRect]) -> Bool)? = nil) throws {
        let visualFrames = visualIDs.compactMap { id -> CGRect? in
            let element = app.descendants(matching: .any)[id]
            return element.exists ? element.frame : nil
        }
        // System bars are translucent glass on iOS 26 and content scrolls beneath them; the audit then measures
        // text through the glass and the scroll-edge blur (about 56 pt under the navigation bar, PR #34, and up
        // to 72 pt above the floating tab bar, run 64). Checked on the screenshot matrix instead.
        let navFrames = app.navigationBars.allElementsBoundByIndex.filter(\.exists).map { $0.frame.insetBy(dx: 0, dy: -56) }
        let tabFrames = app.tabBars.allElementsBoundByIndex.filter(\.exists).map { $0.frame.insetBy(dx: 0, dy: -72) }
        let barFrames = navFrames + tabFrames
        // Content text lying under the floating tab bar (outside the bar's own items). SwiftUI keeps these covered
        // nodes in the tree, and the audit reports some of them a second time without an element (frame 0, run 213).
        let coveredTexts = tabFrames.isEmpty ? 0 : coveredTextCount(app, in: tabFrames)
        var toleratedWithoutElement = 0

        let handler: (XCUIAccessibilityAuditIssue) throws -> Bool = { issue in
            let element = issue.element
            print("AUDIT[\(name)] \(issue.auditType.rawValue) | \(issue.compactDescription) | id=\(element?.identifier ?? "-") "
                  + "label=\(element?.label ?? "-") type=\(element?.elementType.rawValue ?? 0) frame=\(element?.frame ?? .zero)")
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
            // A contrast finding without element is tolerated only while text is provably covered by the tab bar,
            // and at most once per covered text; any further one fails. Each is reported (DECISIONS.md, run 213).
            if issue.auditType == .contrast, element == nil, toleratedWithoutElement < coveredTexts {
                toleratedWithoutElement += 1
                print("::warning title=Audit geduldet (\(name))::Kontrast ohne Element, verdeckt unter der Tab-Leiste: "
                      + "\(toleratedWithoutElement) von \(coveredTexts) verdeckten Texten")
                return true
            }
            // Text the audit finds only in the pixels (no element) is the content seen through the bar glass.
            if issue.auditType == .elementDetection, element == nil, !barFrames.isEmpty {
                return true
            }
            if let extra, extra(issue, barFrames) {
                return true
            }
            // Known false positive: one-line captions reported as clipped although they wrap fully at
            // accessibility sizes. Clipping is checked on the xxxl screenshot matrix (studio-visual-qa).
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

    /// Static texts of the content (not of the tab bar itself) whose frame lies in the tab bar region.
    private static func coveredTextCount(_ app: XCUIApplication, in tabFrames: [CGRect]) -> Int {
        guard let root = try? app.snapshot() else { return 0 }
        var count = 0
        var stack: [any XCUIElementSnapshot] = [root]
        while let node = stack.popLast() {
            if node.elementType == .tabBar { continue }
            if node.elementType == .staticText, !node.frame.isEmpty,
               tabFrames.contains(where: { $0.intersects(node.frame) }) {
                count += 1
            }
            stack.append(contentsOf: node.children)
        }
        return count
    }
}
