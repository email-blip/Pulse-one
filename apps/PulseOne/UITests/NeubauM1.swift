import XCTest

/// Shared pieces of the M1 walkthrough tests (team 06): launch, the accessibility identifiers the new
/// screens must carry, and the "not integrated yet" gate.
///
/// Identifier contract for teams 02–05 (also in docs/neubau/PRUEFLISTE.md, "Kennungen"). A screen root
/// carries its `screen.*` id always, not only in a test scenario.
enum M1 {
    enum Screen {
        static let dashboard = "screen.dashboard"
        static let timeline = "screen.timeline"
        static let why = "screen.why"
        static let workout = "screen.workout"
        static let workoutSummary = "screen.workoutSummary"
    }

    /// Team 03/04: the ROOK block at the top of the dashboard.
    enum Rook {
        /// Headline + interpretation (one element; its label is the visible text).
        static let insight = "rook.insight"
        static let speak = "rook.speak"
        static let why = "rook.why"
        /// Primary action, e.g. "Meine Einheit starten".
        static let action = "rook.action"
        /// Opens the correction choices; each choice is `correction.<id>`.
        static let correct = "rook.correct"
        static let correctionSick = "correction.sick"
    }

    /// Team 03: dashboard tiles and the editor.
    enum Dashboard {
        static let edit = "dashboard.edit"
        static let editDone = "dashboard.editDone"
        static let tilePrefix = "tile."
        /// Accessible alternative to dragging (visible in edit mode): `tile.<id>.moveDown` / `.moveUp`.
        static func moveDown(_ tileID: String) -> String { "tile.\(tileID).moveDown" }
        static func moveUp(_ tileID: String) -> String { "tile.\(tileID).moveUp" }
        static let heartRateTile = "tile.metric.heart_rate"
    }

    /// Team 03: the history with synchronous tracks.
    enum Timeline {
        /// The scrubbable chart area (one element spanning all tracks).
        static let chart = "timeline.chart"
        /// Shared cursor read-out; label contains value, unit and the original measuring time "HH:mm".
        static let selection = "timeline.selection"
        static let sleepTrack = "timeline.track.sleep"
        /// Each sleep section in the track is its own element `hypnogram.segment.<n>` (phase + time in the label).
        static let segmentPrefix = "hypnogram.segment."
        /// Read-out of the tapped hypnogram section; label contains the phase and "HH:mm–HH:mm".
        static let hypnogramSelection = "hypnogram.selection"
        /// A finished workout in the timeline (training track or event marker).
        static let workoutEntry = "timeline.event.workout"
    }

    /// Team 04: "Warum?" sheet.
    enum Why {
        /// One element per piece of evidence (`why.evidence.<n>`), at least one.
        static let evidencePrefix = "why.evidence."
        static let close = "why.close"
    }

    /// Team 05: training session.
    enum Workout {
        static let start = "workout.start"
        static let pause = "workout.pause"
        static let resume = "workout.resume"
        static let finish = "workout.finish"
        /// accessibilityValue = `WorkoutRunState.rawValue` ("running", "paused", "finished" …).
        static let state = "workout.state"
        /// Remaining time of the phase; label like "0:42".
        static let remaining = "workout.remaining"
        /// Perceived exertion buttons `workout.exertion.1` … `.10`.
        static func exertion(_ value: Int) -> String { "workout.exertion.\(value)" }
        static let save = "workout.save"
    }

    /// Team 05: talking with ROOK in the Coach tab. Without a microphone in the simulator, `-uiTestVoice "A|B"`
    /// speaks A after the tap and B into ROOK's answer (barge-in).
    enum Voice {
        static let button = "rook.voice"
        static let status = "rook.voice.status"
        static let transcript = "rook.voice.transcript"
        static let personTurn = "rook.voice.turn.person"
        static let rookTurn = "rook.voice.turn.rook"
        static let first = "Wie war meine Nacht"
        static let second = "Warte mal, wie ist mein Puls gerade"
        static var launchArguments: [String] { ["-uiTestVoice", "\(first)|\(second)"] }
        // Status lines of RookVoicePanel.statusLine.
        static let listening = "Ich höre zu"
        static let thinking = "Ich denke nach"
        static let speaking = "ROOK spricht"
    }

    static let tabCoach = "Coach"
    static let tabTimeline = "Verlauf"
    static let tabDashboard = "Dashboard"

    /// Before 00 integrates the M1 screens the tests skip at the first missing screen and say which one.
    /// With `PULSE_M1_STRICT=1` (CI passes `TEST_RUNNER_PULSE_M1_STRICT`) a missing screen fails instead.
    static var strict: Bool { ProcessInfo.processInfo.environment["PULSE_M1_STRICT"] == "1" }

    @MainActor
    static func launch(_ scenario: String = "neubauM1", dynamicType: String = "default", reduceMotion: Bool = false,
                       liveMotion: Bool = false, extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "YES", "-scenario", scenario, "-AppleLanguages", "(de)", "-AppleLocale", "de_DE",
                               "-dynamicType", dynamicType, "-reduceMotion", reduceMotion ? "YES" : "NO",
                               "-liveMotion", liveMotion ? "YES" : "NO"] + extraArguments
        app.launch()
        return app
    }

    @MainActor
    static func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id]
    }

    /// Waits for `id`. If it never appears it throws `M1Missing`; in strict mode it also records a failure.
    /// Callers outside the walkthrough turn it into a skip with `M1.skipIfMissing`.
    @MainActor
    @discardableResult
    static func require(_ app: XCUIApplication, _ id: String, step: String, timeout: TimeInterval = 15,
                        file: StaticString = #filePath, line: UInt = #line) throws -> XCUIElement {
        let found = element(app, id)
        if found.waitForExistence(timeout: timeout) { return found }
        let message = "\(step): \(id) fehlt"
        if strict { XCTFail(message, file: file, line: line) }
        throw M1Missing(message: message)
    }

    /// Runs `body`; a missing screen becomes a skip ("noch nicht integriert") unless strict.
    @MainActor
    @discardableResult
    static func skipIfMissing<T>(_ body: () throws -> T) throws -> T {
        do {
            return try body()
        } catch let missing as M1Missing where !strict {
            throw XCTSkip("Noch nicht integriert – \(missing.message)")
        }
    }

    /// Scrolls the current screen until `element` is hittable (at most `swipes` times).
    @MainActor
    static func reveal(_ element: XCUIElement, in app: XCUIApplication, swipes: Int = 6) {
        for _ in 0..<swipes where !(element.exists && element.isHittable) { app.swipeUp() }
    }

    /// Visible tile ids in reading order (top to bottom, then left to right).
    @MainActor
    static func tileOrder(_ app: XCUIApplication) -> [String] {
        let tiles = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", Dashboard.tilePrefix)).allElementsBoundByIndex
        var placed: [(id: String, frame: CGRect)] = []
        for tile in tiles {
            let id = tile.identifier
            if id.hasSuffix(".moveDown") || id.hasSuffix(".moveUp") { continue }
            placed.append((id: id, frame: tile.frame))
        }
        placed.sort { lhs, rhs in
            let sameRow = abs(lhs.frame.minY - rhs.frame.minY) <= 4
            return sameRow ? lhs.frame.minX < rhs.frame.minX : lhs.frame.minY < rhs.frame.minY
        }
        var order: [String] = []
        for entry in placed where !order.contains(entry.id) { order.append(entry.id) }
        return order
    }

    /// M1 screens the screenshot matrix and the audits visit (`M1.open`).
    enum Place: String, CaseIterable {
        case dashboard, dashboardEdit, timeline, hypnogram, why, workout, workoutPaused, workoutSummary
    }

    /// From a fresh launch of `neubauM1`, goes to `place` through the same controls a person uses.
    @MainActor
    static func open(_ place: Place, in app: XCUIApplication) throws {
        try require(app, Screen.dashboard, step: "Dashboard", timeout: 30)
        switch place {
        case .dashboard:
            break
        case .dashboardEdit:
            let edit = try require(app, Dashboard.edit, step: "Kacheln anordnen")
            reveal(edit, in: app)
            edit.tap()
            try require(app, Dashboard.editDone, step: "Anordnen fertig")
        case .timeline, .hypnogram:
            let tile = try require(app, Dashboard.heartRateTile, step: "Puls-Kachel")
            reveal(tile, in: app)
            tile.tap()
            let chart = try require(app, Timeline.chart, step: "Spuren")
            if place == .timeline {
                chart.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4)).tap()
                try require(app, Timeline.selection, step: "Cursor-Anzeige", timeout: 5)
            } else {
                try tapFirstSleepSegment(app)
                try require(app, Timeline.hypnogramSelection, step: "Schlafabschnitt", timeout: 5)
            }
        case .why:
            try require(app, Rook.why, step: "Warum?").tap()
            try require(app, Screen.why, step: "Warum-Ansicht")
        case .workout, .workoutPaused, .workoutSummary:
            let action = try require(app, Rook.action, step: "Einheit starten")
            reveal(action, in: app)
            action.tap()
            try require(app, Screen.workout, step: "Trainingsansicht")
            try require(app, Workout.start, step: "Start").tap()
            if place == .workoutPaused { try require(app, Workout.pause, step: "Pause").tap() }
            if place == .workoutSummary {
                try require(app, Workout.finish, step: "Beenden").tap()
                try require(app, Screen.workoutSummary, step: "Zusammenfassung")
            }
        }
        // Let transitions and chart layout settle before a screenshot or an audit.
        Thread.sleep(forTimeInterval: 1)
    }

    /// Taps the first sleep section. The track's middle is "now − 12 h" and often not in the night, so the test
    /// taps a section element instead of a position (agreed with team 03).
    @MainActor
    static func tapFirstSleepSegment(_ app: XCUIApplication) throws {
        let sleep = try require(app, Timeline.sleepTrack, step: "Schlafspur")
        reveal(sleep, in: app)
        let segment = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", Timeline.segmentPrefix)).firstMatch
        guard segment.waitForExistence(timeout: 5) else {
            let message = "Schlafabschnitt: \(Timeline.segmentPrefix)* fehlt (Schlafsegmente im Szenario?)"
            if strict { XCTFail(message) }
            throw M1Missing(message: message)
        }
        segment.tap()
    }

    /// Screenshot attachment kept in the result bundle (exported to ci-screenshots/<branch>).
    @MainActor
    static func attachScreenshot(_ test: XCTestCase, name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        test.add(attachment)
    }
}

struct M1Missing: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}

/// "HH:mm" or "H:mm" anywhere in a label: the original measuring time.
func containsClockTime(_ text: String) -> Bool {
    text.range(of: "\\b\\d{1,2}:\\d{2}\\b", options: .regularExpression) != nil
}
