import XCTest

/// Companion ("Begleiter") test views: the screen with a briefing from test data, and the wake-up flow.
@MainActor
final class CompanionTests: XCTestCase {
    override func setUp() async throws {
        continueAfterFailure = false
    }

    private func launch(_ scenario: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "YES", "-uiTestScenario", scenario, "-AppleLanguages", "(de)",
                               "-AppleLocale", "de_DE"]
        app.launch()
        return app
    }

    func testCompanionShowsBriefing() throws {
        let app = launch("companion")
        XCTAssertTrue(app.descendants(matching: .any)["screen.companion"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.descendants(matching: .any)["testBanner"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["companion.alarm"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["companion.headline"].waitForExistence(timeout: 15),
                      "briefing headline did not appear")
    }

    /// Codex P1-005: an answer revises the interpretation and is logged; the measured block stays.
    func testInsightAnswerRevisesInterpretation() throws {
        let app = launch("insightNights")
        XCTAssertTrue(app.descendants(matching: .any)["screen.insightNights"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.descendants(matching: .any)["testBanner"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["insight.header"].waitForExistence(timeout: 10))
        let answer = app.buttons["insight.answer.training.Ja"]
        XCTAssertTrue(answer.waitForExistence(timeout: 10))
        for _ in 0..<6 where !answer.isHittable { app.swipeUp() }
        answer.tap()
        let revisions = app.descendants(matching: .any)["insight.revisions"]
        for _ in 0..<6 where !revisions.exists { app.swipeUp() }
        XCTAssertTrue(revisions.waitForExistence(timeout: 10))
    }

    func testWakeUpFlowRevealsBriefing() throws {
        let app = launch("companionWake")
        XCTAssertTrue(app.descendants(matching: .any)["screen.companionWake"].waitForExistence(timeout: 15))
        let confirm = app.buttons["wake.confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 10))
        confirm.tap()
        XCTAssertTrue(app.descendants(matching: .any)["wake.headline"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.buttons["wake.done"].waitForExistence(timeout: 10))
    }

    /// The expert round opens with the stored sample round; asking again runs offline through the test
    /// transport after the preview was confirmed.
    func testConferenceShowsStoredRoundAndRunsOffline() throws {
        let app = launch("companionConference")
        XCTAssertTrue(app.descendants(matching: .any)["screen.companionConference"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.descendants(matching: .any)["testBanner"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["conference.disclaimer"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["conference.synthesis"].waitForExistence(timeout: 10),
                      "stored sample round did not appear")

        let ask = app.buttons["conference.ask"]
        XCTAssertTrue(ask.waitForExistence(timeout: 10))
        ask.tap()
        let send = app.buttons["conference.send"]
        XCTAssertTrue(send.waitForExistence(timeout: 10), "send preview did not appear")
        XCTAssertTrue(app.descendants(matching: .any)["conference.facts"].exists)
        send.tap()
        XCTAssertTrue(app.descendants(matching: .any)["conference.synthesis"].waitForExistence(timeout: 20))
        XCTAssertFalse(app.descendants(matching: .any)["conference.error"].exists)
    }

    func testCompanionAccessibilityAudit() throws {
        let app = launch("companion")
        XCTAssertTrue(app.descendants(matching: .any)["screen.companion"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.descendants(matching: .any)["companion.headline"].waitForExistence(timeout: 15))
        // Let the launch transition finish (see AccessibilityTests).
        Thread.sleep(forTimeInterval: 3)
        // Shared exclusions (bar glass incl. the scroll-edge blur above the tab bar, run 64), see AuditPolicy.
        try AuditPolicy.run(app, name: "companion")
    }
}
