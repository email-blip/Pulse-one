import XCTest

/// Companion activation ("Aktivierung"): the guided session from the test scenario, walked through to the end,
/// and an accessibility audit of its overview.
@MainActor
final class ActivationTests: XCTestCase {
    private let scenario = "companionActivation"

    override func setUp() async throws {
        continueAfterFailure = false
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "YES", "-uiTestScenario", scenario, "-AppleLanguages", "(de)",
                               "-AppleLocale", "de_DE"]
        app.launch()
        return app
    }

    func testGuidedSessionRunsToTheEnd() throws {
        let app = launch()
        XCTAssertTrue(app.descendants(matching: .any)["screen.\(scenario)"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.descendants(matching: .any)["testBanner"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["activation.overview"].waitForExistence(timeout: 10))

        let begin = app.buttons["activation.begin"]
        XCTAssertTrue(begin.waitForExistence(timeout: 10))
        begin.tap()
        XCTAssertTrue(app.descendants(matching: .any)["activation.exerciseName"].waitForExistence(timeout: 10))

        // Tap "Geschafft" until a rest appears (warm-up steps may have no rest), then skip it.
        let done = app.buttons["activation.done"]
        let skip = app.buttons["activation.skipRest"]
        let end = app.descendants(matching: .any)["activation.end"]
        for _ in 0..<12 {
            if skip.exists || end.exists { break }
            if done.waitForExistence(timeout: 5) { done.tap() }
            _ = skip.waitForExistence(timeout: 1)
        }
        if skip.exists {
            skip.tap()
            XCTAssertTrue(app.descendants(matching: .any)["activation.exerciseName"].waitForExistence(timeout: 10))
        }

        // End early (the partial result is saved), unless the session already finished.
        let endEarly = app.buttons["activation.endEarly"]
        if !end.exists, endEarly.waitForExistence(timeout: 5) {
            endEarly.tap()
        }
        XCTAssertTrue(end.waitForExistence(timeout: 10), "end screen did not appear")

        let right = app.buttons["activation.feedback.right"]
        XCTAssertTrue(right.waitForExistence(timeout: 5))
        right.tap()
        XCTAssertTrue(app.descendants(matching: .any)["activation.progress"].waitForExistence(timeout: 10))

        let finish = app.buttons["activation.finish"]
        XCTAssertTrue(finish.waitForExistence(timeout: 5))
        finish.tap()
        // Back on the companion screen: the activation section lists today's sessions.
        XCTAssertTrue(app.descendants(matching: .any)["activation.section"].waitForExistence(timeout: 10))
    }

    func testOverviewAccessibilityAudit() throws {
        let app = launch()
        XCTAssertTrue(app.descendants(matching: .any)["screen.\(scenario)"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.descendants(matching: .any)["activation.overview"].waitForExistence(timeout: 10))
        // Let the full-screen presentation finish (see AccessibilityTests).
        Thread.sleep(forTimeInterval: 3)
        try AuditPolicy.run(app, name: scenario)
    }
}
