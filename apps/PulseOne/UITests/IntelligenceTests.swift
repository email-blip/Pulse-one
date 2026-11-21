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

    /// The evening note suggests tags from the sentence; the saved card shows tags, not the text.
    func testEveningNoteSuggestsTags() {
        let app = launch("today")
        let open = app.buttons["eveningNote.open"]
        XCTAssertTrue(open.waitForExistence(timeout: 15))
        open.tap()
        let field = app.textFields["eveningNote.text"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText("Stressiger Tag")
        let stress = app.buttons["eveningNote.tag.stress"]
        XCTAssertTrue(stress.waitForExistence(timeout: 5))
        XCTAssertTrue(stress.isSelected)
        app.buttons["Speichern"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Stress")).firstMatch.waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Stressiger Tag"].exists)
    }
}
