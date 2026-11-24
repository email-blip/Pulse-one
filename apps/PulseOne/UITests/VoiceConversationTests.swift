import XCTest

/// Talking with ROOK without a real microphone: `-uiTestVoice` feeds two utterances word by word, the second one
/// into ROOK's answer. Checks the live transcript, ROOK answering, the interruption and ending the conversation.
@MainActor
final class VoiceConversationTests: XCTestCase {
    func testConversationListensAnswersAndCanBeInterrupted() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "YES", "-uiTestScenario", "coach",
                               "-uiTestVoice", "Wie war meine Nacht|Warte mal, wie ist mein Puls gerade"]
        app.launch()

        let mic = app.buttons["rook.voice"]
        XCTAssertTrue(mic.waitForExistence(timeout: 15))
        XCTAssertEqual(mic.label, "Mit ROOK sprechen")
        mic.tap()

        // The person's words appear live, then ROOK answers.
        XCTAssertTrue(element(containing: "Wie war meine Nacht", in: app).waitForExistence(timeout: 10))
        let rookTurns = app.descendants(matching: .any).matching(identifier: "rook.voice.turn.rook")
        XCTAssertTrue(rookTurns.firstMatch.waitForExistence(timeout: 10))
        // The second utterance cuts into the answer and gets its own answer.
        XCTAssertTrue(element(containing: "Warte mal, wie ist mein Puls gerade", in: app).waitForExistence(timeout: 15))
        // The interruption really stopped ROOK (counted when the answer was cut, independent of query timing).
        let status = app.descendants(matching: .any)["rook.voice.status"]
        let interrupted = expectation(for: NSPredicate(format: "value CONTAINS %@", "Unterbrochen: 1"), evaluatedWith: status)
        wait(for: [interrupted], timeout: 10)
        // ROOK answers the new question too (text depends on ROOK's brain, so only the turn is checked).
        let second = NSPredicate(format: "count >= 2")
        expectation(for: second, evaluatedWith: rookTurns)
        waitForExpectations(timeout: 15)

        XCTAssertEqual(app.buttons["rook.voice"].label, "Gespräch beenden")
        app.buttons["rook.voice"].tap()
        XCTAssertTrue(app.staticTexts["Tippen und einfach losreden. Ich antworte laut."].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["rook.voice"].label, "Mit ROOK sprechen")
    }

    private func element(containing text: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }
}
