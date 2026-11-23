import XCTest

/// Analyse tab in the test scenario: canned Claude replies, fake key in memory, never a real call.
@MainActor
final class IntelligenceTests: XCTestCase {
    private func launch(_ scenario: String = "intelligence") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "YES", "-uiTestScenario", scenario]
        app.launch()
        return app
    }

    /// A report needs the visible preview first, then shows checked statements with their type.
    func testWeeklyReportGoesThroughPreview() {
        let app = launch()
        XCTAssertTrue(app.descendants(matching: .any)["screen.intelligence"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.descendants(matching: .any)["testBanner"].exists)
        let weekly = app.buttons["intelligence.report.weekly"]
        XCTAssertTrue(weekly.waitForExistence(timeout: 10))
        weekly.tap()
        let send = app.buttons["intelligence.send"]
        XCTAssertTrue(send.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Vor dem Senden"].exists || app.navigationBars["Vor dem Senden"].exists)
        send.tap()
        let summary = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Ruhepuls")).firstMatch
        XCTAssertTrue(summary.waitForExistence(timeout: 15))
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "gemessen")).firstMatch.exists)
    }

    /// Acute symptoms are answered locally with the emergency numbers; nothing is offered for sending.
    func testEmergencyQuestionStaysOnPhone() {
        let app = launch()
        let field = app.textFields["intelligence.question"]
        XCTAssertTrue(field.waitForExistence(timeout: 15))
        field.tap()
        field.typeText("Ich habe Brustschmerzen")
        app.buttons["Fragen"].tap()
        let reply = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "112")).firstMatch
        XCTAssertTrue(reply.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["intelligence.send"].exists)
    }

    /// The key is shown masked only; the settings live in the profile sheet.
    func testSettingsShowMaskedKey() {
        let app = launch()
        let profile = app.buttons["openProfile"].firstMatch
        XCTAssertTrue(profile.waitForExistence(timeout: 15))
        profile.tap()
        let provider = app.buttons["KI-Anbieter"].firstMatch
        XCTAssertTrue(provider.waitForExistence(timeout: 10))
        provider.tap()
        let stored = app.descendants(matching: .any)["intelligence.keyStored"]
        XCTAssertTrue(stored.waitForExistence(timeout: 10))
        XCTAssertTrue(stored.label.contains("…1234"))
        XCTAssertFalse(stored.label.contains("0000000000"))
    }

    /// The consultation: preview before the first send, then possible diagnoses with their fit and
    /// questions; a follow-up goes without a second preview and gets its own answer.
    func testConsultationConversation() {
        let app = launch()
        let start = app.buttons["intelligence.consultation.new"]
        XCTAssertTrue(start.waitForExistence(timeout: 15))
        start.tap()
        let input = app.textFields["consultation.input"]
        XCTAssertTrue(input.waitForExistence(timeout: 10))
        input.tap()
        input.typeText("Seit drei Tagen müde")
        app.buttons["consultation.send"].tap()
        let send = app.buttons["intelligence.send"]
        XCTAssertTrue(send.waitForExistence(timeout: 10))
        send.tap()
        XCTAssertTrue(app.descendants(matching: .any)["consultation.differentials"].waitForExistence(timeout: 15))
        // No percentages (owner decision 2026-11-22): the fit is shown in words.
        XCTAssertTrue(app.staticTexts["passt gut"].exists)
        XCTAssertFalse(app.staticTexts["55 %"].exists)
        let field = app.textFields["consultation.input"]
        field.tap()
        field.typeText("Kein Fieber")
        app.buttons["consultation.send"].tap()
        XCTAssertFalse(app.buttons["intelligence.send"].waitForExistence(timeout: 2))
        let followUp = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Danke, das hilft")).firstMatch
        XCTAssertTrue(followUp.waitForExistence(timeout: 15))
    }
}
