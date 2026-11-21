import XCTest

/// Captures the visual QA matrix. Attachment names become file names on the ci-screenshots branch.
/// PULSE ONE is dark-only until the design profiles land, so the matrix is dark × Dynamic Type.
@MainActor
final class ScreenshotTests: XCTestCase {
    static let scenarios = ["start", "scanning", "connected", "live", "failed", "reconnecting", "heart", "devices",
                            "onboarding", "today", "health", "healthDetail", "profile", "intelligence", "coach", "nutrition",
                            "companion", "companionWake", "companionConference", "companionActivation"]

    override func setUp() async throws {
        continueAfterFailure = true   // one broken cell must not hide the others
    }

    func testCaptureMatrix() throws {
        for scenario in Self.scenarios {
            for type in ["default", "xxxl"] {
                capture(scenario: scenario, dynamicType: type, reduceMotion: false)
            }
        }
        capture(scenario: "live", dynamicType: "default", reduceMotion: true)
        capture(scenario: "heart", dynamicType: "default", reduceMotion: true)
        for type in ["default", "xxxl"] {
            capture(scenario: "intelligence", dynamicType: type, reduceMotion: false, name: "consultation") { app in
                let row = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Seit ein paar Tagen müde")).firstMatch
                if row.waitForExistence(timeout: 10) { row.tap() }
            }
        }
    }

    /// `prepare` navigates to a screen below the scenario's start screen, captured as `name`.
    private func capture(scenario: String, dynamicType: String, reduceMotion: Bool, name: String? = nil,
                         prepare: ((XCUIApplication) -> Void)? = nil) {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "YES", "-uiTestScenario", scenario, "-AppleLanguages", "(de)", "-AppleLocale", "de_DE",
                               "-dynamicType", dynamicType, "-reduceMotion", reduceMotion ? "YES" : "NO"]
        app.launch()
        let screen = app.descendants(matching: .any)["screen.\(scenario)"]
        XCTAssertTrue(screen.waitForExistence(timeout: 15), "screen.\(scenario) did not appear")
        if let prepare, let name {
            prepare(app)
            XCTAssertTrue(app.descendants(matching: .any)["screen.\(name)"].waitForExistence(timeout: 15), "screen.\(name) did not appear")
            Thread.sleep(forTimeInterval: 1)
        }
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = [name ?? scenario, "dark", dynamicType, reduceMotion ? "reduced" : nil]
            .compactMap { $0 }.joined(separator: "__")
        attachment.lifetime = .keepAlways
        add(attachment)
        app.terminate()
    }
}
