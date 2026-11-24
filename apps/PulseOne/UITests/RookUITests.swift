import XCTest

/// ROOK (team 04): the two demonstration cases, a correction that changes the advice locally and without
/// network, and "Warum?" with its measurements. Test scenarios never call Claude.
@MainActor
final class RookUITests: XCTestCase {
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

    private func insight(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["rook.insight"]
    }

    /// Routine sentences ROOK never says (plan §9), as the M1 walkthrough checks them too.
    private func assertClean(_ text: String, file: StaticString = #filePath, line: UInt = #line) {
        for fragment in ["lernt noch", "Basislinie", "kein Arzt", "nicht lesen", "fehlende Daten", "Synchronisier"] {
            XCTAssertFalse(text.localizedCaseInsensitiveContains(fragment), "\"\(fragment)\" in: \(text)", file: file, line: line)
        }
    }

    func testPositiveDevelopmentAndIllnessCorrection() throws {
        let app = launch("rookPositive")
        XCTAssertTrue(app.descendants(matching: .any)["screen.rookPositive"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.descendants(matching: .any)["testBanner"].exists)
        let statement = insight(app)
        XCTAssertTrue(statement.waitForExistence(timeout: 15))
        let before = statement.label
        XCTAssertTrue(before.contains("Rhythmus"), before)
        assertClean(before)
        XCTAssertTrue(app.descendants(matching: .any)["orb"].exists)
        XCTAssertTrue(app.buttons["rook.action"].exists)

        app.buttons["rook.correct"].tap()
        let sick = app.buttons["correction.sick"]
        XCTAssertTrue(sick.waitForExistence(timeout: 10))
        sick.tap()
        let changed = NSPredicate(format: "label != %@", before)
        expectation(for: changed, evaluatedWith: statement)
        waitForExpectations(timeout: 20)
        XCTAssertTrue(statement.label.contains("Erholung"), statement.label)
        assertClean(statement.label)
        // Still a startable, gentle unit.
        XCTAssertEqual(app.buttons["rook.action"].label, "Sanfte 10 Minuten")
    }

    func testClearChangeAdvisesCheckAndExplainsWhy() throws {
        let app = launch("rookClarify")
        XCTAssertTrue(app.descendants(matching: .any)["screen.rookClarify"].waitForExistence(timeout: 20))
        let statement = insight(app)
        XCTAssertTrue(statement.waitForExistence(timeout: 15))
        XCTAssertTrue(statement.label.contains("abklären"), statement.label)
        assertClean(statement.label)

        app.buttons["rook.why"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["screen.why"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["why.evidence.0"].waitForExistence(timeout: 10))
        // Alternatives carry a fit in words, never a percentage.
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "passt")).firstMatch.exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Wahrscheinlichkeit")).firstMatch.exists)
        app.buttons["why.close"].tap()
        XCTAssertTrue(statement.waitForExistence(timeout: 10))
    }
}
