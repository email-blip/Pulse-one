import XCTest

/// Runs Apple's built-in accessibility audit (contrast, hit regions, labels, Dynamic Type clipping …).
@MainActor
final class AccessibilityTests: XCTestCase {
    func testStartAudit() throws { try audit(scenario: "start") }
    func testScanningAudit() throws { try audit(scenario: "scanning") }
    func testLiveAudit() throws { try audit(scenario: "live") }
    func testDevicesAudit() throws { try audit(scenario: "devices") }
    func testOnboardingAudit() throws { try audit(scenario: "onboarding") }
    /// Dashboards are longer than the screen: audited once per tile row, each row at the top (`auditTileRows`).
    func testDashboardAudit() throws { try auditTileRows(scenario: "dashboard") }
    /// The tile editor (team 03): arrows, size menu and on/off switch per tile.
    func testDashboardEditAudit() throws { try auditTileRows(scenario: "dashboardEdit", screen: "dashboard") }
    func testTimelineAudit() throws { try audit(scenario: "timeline") }
    /// ROOK's "Warum?" from the dashboard, with the numbers behind the statement.
    func testWhyAudit() throws {
        try audit(scenario: "dashboard", screen: "why") { app in
            let why = app.buttons["rook.why"]
            XCTAssertTrue(why.waitForExistence(timeout: 15))
            why.tap()
        }
    }
    func testIntelligenceAudit() throws { try audit(scenario: "intelligence") }
    func testCoachAudit() throws { try audit(scenario: "coach") }
    /// ROOK's two demonstration cases (team 04) and the "Warum?" sheet.
    func testRookPositiveAudit() throws { try audit(scenario: "rookPositive") }
    func testRookClarifyAudit() throws { try audit(scenario: "rookClarify") }
    func testRookWhyAudit() throws {
        try audit(scenario: "rookClarify", screen: "why") { app in
            let why = app.buttons["rook.why"]
            XCTAssertTrue(why.waitForExistence(timeout: 15))
            why.tap()
        }
    }
    func testInsightNormalAudit() throws { try audit(scenario: "insightNormal") }
    func testInsightNightsAudit() throws { try audit(scenario: "insightNights") }
    func testInsightGapAudit() throws { try audit(scenario: "insightGap") }
    /// DesignKit component preview (team 02): tokens, tile, buttons, chips, orb states.
    func testDesignKitAudit() throws { try audit(scenario: "designKit") }

    /// Scenarios whose start screen identifier differs from the scenario name.
    private static let startScreens = ["dashboardEdit": "dashboard"]

    // Rebuild M1 screens (team 06). Skipped until integrated; failures once `PULSE_M1_STRICT=1`.
    func testM1DashboardAudit() throws { try auditM1(.dashboard) }
    func testM1DashboardEditAudit() throws { try auditM1(.dashboardEdit) }
    func testM1TimelineAudit() throws { try auditM1(.timeline) }
    func testM1HypnogramAudit() throws { try auditM1(.hypnogram) }
    func testM1WhyAudit() throws { try auditM1(.why) }
    func testM1WorkoutAudit() throws { try auditM1(.workout) }
    func testM1WorkoutSummaryAudit() throws { try auditM1(.workoutSummary) }
    /// Build 19: the owner reads with large text. The dashboard audited at accessibility3 (`xxxl`), where Build 18
    /// broke tile titles and cut numbers; the audit's own Dynamic Type check starts from that size.
    /// The Verlauf follows with team 03's Build 19 charts.
    func testM1DashboardAuditAX3() throws { try auditM1(.dashboard, dynamicType: "xxxl") }

    private func auditM1(_ place: M1.Place, dynamicType: String = "default") throws {
        let app = M1.launch(dynamicType: dynamicType)
        try M1.skipIfMissing { try M1.open(place, in: app) }
        // Same settle time as the other screens: text must not be measured mid-fade.
        Thread.sleep(forTimeInterval: 2)
        let suffix = dynamicType == "default" ? "" : "-\(dynamicType)"
        try AuditPolicy.run(app, name: "m1-\(place.rawValue)\(suffix)")
    }

    /// No Dynamic Type override here: the audit changes the text size itself to find clipping.
    @discardableResult
    private func audit(scenario: String, screen: String? = nil, name: String? = nil, extraArguments: [String] = [],
                       prepare: ((XCUIApplication) -> Void)? = nil) throws -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "YES", "-uiTestScenario", scenario] + extraArguments
        app.launch()
        let start = prepare == nil ? (screen ?? scenario) : (Self.startScreens[scenario] ?? scenario)
        XCTAssertTrue(app.descendants(matching: .any)["screen.\(start)"].waitForExistence(timeout: 15))
        if let prepare {
            prepare(app)
            XCTAssertTrue(app.descendants(matching: .any)["screen.\(screen ?? scenario)"].waitForExistence(timeout: 15))
        }
        // Let the launch transition finish: run 4 reported contrast on text that is still fading in.
        // Tab screens load SwiftData queries and charts first; 1.5 s still caught text mid-fade on them (run 36).
        Thread.sleep(forTimeInterval: 3)
        let extra: (XCUIAccessibilityAuditIssue, [CGRect]) -> Bool = { issue, barFrames in
            // Only on the nutrition screen: a contrast finding without element (frame 0×0) seen once on a slow
            // runner (PR #32). Scoped to this screen so element-less findings elsewhere still fail.
            scenario == "nutrition" && issue.auditType == .contrast && issue.element == nil && !barFrames.isEmpty
        }
        try AuditPolicy.run(app, name: name ?? scenario, extra: extra)
        return app
    }

    /// Audits a dashboard without scrolling: scrolled positions always cut content at the top edge (run 217), and
    /// below the ROOK card no tile fits above the tab bar region the policy leaves out. So the first launch audits
    /// the screen as it is (ROOK card, header, first tiles); further launches leave out the ROOK card
    /// (`-dashboardTilesOnly YES`) and start the tile list at the first tile not yet audited fully visible
    /// (`-dashboardStartIndex N`). Both switches work only in test scenarios and are never saved.
    private func auditTileRows(scenario: String, screen: String? = nil) throws {
        var covered: Set<String> = []
        var startIndex = 0
        var all: [String] = []
        for launch in 1...6 {
            let extra = launch == 1 ? [] : ["-dashboardTilesOnly", "YES", "-dashboardStartIndex", "\(startIndex)"]
            let app = try audit(scenario: scenario, screen: screen, name: launch == 1 ? scenario : "\(scenario)#\(startIndex)",
                                extraArguments: extra)
            let tiles = tileFrames(app)
            if all.isEmpty { all = tiles.map(\.id) }
            // Fully visible: below the top edge and above the tab bar region the audit policy leaves out.
            let tabTop = app.tabBars.firstMatch.exists ? app.tabBars.firstMatch.frame.minY - 72 : app.frame.maxY
            covered.formUnion(tiles.filter { $0.frame.minY >= 0 && $0.frame.maxY <= tabTop }.map(\.id))
            app.terminate()
            // On screen the tiles follow the list rotated by `startIndex`: the first uncovered one opens the next launch.
            guard let next = tiles.first(where: { !covered.contains($0.id) }) else { break }
            if launch > 1, next.index == 0 {
                XCTFail("Kachel \(next.id) passt nicht über die Tab-Leiste, nie voll sichtbar geprüft")
                break
            }
            startIndex = (startIndex + next.index) % tiles.count
        }
        let missing = all.filter { !covered.contains($0) }
        XCTAssertTrue(missing.isEmpty, "Kacheln nie voll sichtbar geprüft: \(missing)")
        print("AUDIT[\(scenario)] Kacheln voll sichtbar geprüft: \(covered.count) von \(all.count)")
    }

    /// Tile roots (`tile.<id>`, without the move buttons) with their frame and their position in reading order.
    private func tileFrames(_ app: XCUIApplication) -> [(id: String, frame: CGRect, index: Int)] {
        var placed: [(id: String, frame: CGRect)] = []
        let tiles = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "tile.")).allElementsBoundByIndex
        for tile in tiles {
            let id = tile.identifier
            if id.hasSuffix(".moveDown") || id.hasSuffix(".moveUp") || placed.contains(where: { $0.id == id }) { continue }
            placed.append((id: id, frame: tile.frame))
        }
        placed.sort { abs($0.frame.minY - $1.frame.minY) <= 4 ? $0.frame.minX < $1.frame.minX : $0.frame.minY < $1.frame.minY }
        return placed.enumerated().map { (id: $0.element.id, frame: $0.element.frame, index: $0.offset) }
    }
}
