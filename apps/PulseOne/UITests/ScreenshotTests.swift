import XCTest

/// Captures the visual QA matrix. Attachment names become file names on the ci-screenshots branch.
/// PULSE ONE is dark-only until the design profiles land, so the matrix is dark × Dynamic Type.
@MainActor
final class ScreenshotTests: XCTestCase {
    static let scenarios = ["start", "scanning", "connected", "live", "failed", "reconnecting", "heart", "devices",
                            "onboarding", "dashboard", "dashboardEdit", "timeline", "timelineHypnogram", "profile", "intelligence", "coach",
                            "companion", "companionWake", "companionConference", "companionActivation",
                            "insightNormal", "insightNights", "insightGap", "designKit"]

    /// Scenarios that start on a shared screen (its identifier does not carry the scenario name).
    static let screens = ["dashboardEdit": "screen.dashboard", "timelineHypnogram": "screen.timeline"]

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
        for scenario in ["insightNormal", "insightNights", "insightGap", "designKit", "dashboard", "timeline"] {
            capture(scenario: scenario, dynamicType: "default", reduceMotion: true)
        }
        // A contradicting answer revises the interpretation; the measurements above stay as they were.
        for type in ["default", "xxxl"] {
            capture(scenario: "insightNights", dynamicType: type, reduceMotion: false, name: "insightNightsAnswered",
                    expectedScreen: "insight.revisions") { app in
                let answer = app.buttons["insight.answer.training.Ja"]
                for _ in 0..<6 where !answer.isHittable { app.swipeUp() }
                if answer.waitForExistence(timeout: 10) { answer.tap() }
                for _ in 0..<6 where !app.descendants(matching: .any)["insight.revisions"].exists { app.swipeUp() }
            }
        }
        for type in ["default", "xxxl"] {
            capture(scenario: "intelligence", dynamicType: type, reduceMotion: false, name: "consultation") { app in
                let row = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Seit ein paar Tagen müde")).firstMatch
                if row.waitForExistence(timeout: 10) { row.tap() }
            }
            // Team 03: "Warum?" under ROOK's statement, and a picked sleep phase in the hypnogram.
            capture(scenario: "dashboard", dynamicType: type, reduceMotion: false, name: "why") { app in
                let why = app.buttons["rook.why"]
                if why.waitForExistence(timeout: 10) { why.tap() }
            }
            capture(scenario: "timelineHypnogram", dynamicType: type, reduceMotion: false, name: "hypnogramSelection",
                    expectedScreen: "hypnogram.selection") { app in
                let segment = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "hypnogram.segment.")).element(boundBy: 2)
                if segment.waitForExistence(timeout: 10) { segment.tap() }
            }
        }
    }

    /// `prepare` navigates to a screen below the scenario's start screen, captured as `name`.
    private func capture(scenario: String, dynamicType: String, reduceMotion: Bool, name: String? = nil,
                         expectedScreen: String? = nil, prepare: ((XCUIApplication) -> Void)? = nil) {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "YES", "-uiTestScenario", scenario, "-AppleLanguages", "(de)", "-AppleLocale", "de_DE",
                               "-dynamicType", dynamicType, "-reduceMotion", reduceMotion ? "YES" : "NO"]
        app.launch()
        let screenID = Self.screens[scenario] ?? "screen.\(scenario)"
        let screen = app.descendants(matching: .any)[screenID]
        XCTAssertTrue(screen.waitForExistence(timeout: 15), "\(screenID) did not appear")
        if let prepare, let name {
            prepare(app)
            let target = expectedScreen ?? "screen.\(name)"
            XCTAssertTrue(app.descendants(matching: .any)[target].waitForExistence(timeout: 15), "\(target) did not appear")
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
