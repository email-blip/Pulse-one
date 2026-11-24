import XCTest

/// M1 "Durchstich" (plan §8): the whole walkthrough in one test, recorded as a screen video in CI
/// (`scripts/qa/run-durchstich.sh`). Every step attaches a screenshot `durchstich__NN-<step>` and the
/// test writes `durchstich-report.md` (step, result, what was seen).
///
/// Until 00 integrates the M1 screens, the test stops with a skip at the first missing screen and the
/// report names it. With `PULSE_M1_STRICT=1` a missing screen is a failure (switched on by 00 for M1).
@MainActor
final class DurchstichTests: XCTestCase {
    private var app: XCUIApplication!
    private var report: [(step: String, result: String, note: String)] = []
    private var stepNumber = 0

    /// Phrases ROOK never says in normal use (plan §9).
    static let forbidden = ["lernt noch", "Basislinie", "kein Arzt", "nicht lesen", "fehlende Daten", "Synchronisier"]

    override func setUp() async throws {
        // A failed check is recorded as ✗ in the report and the walkthrough goes on, so one run shows
        // every broken step. A missing screen still ends the run (skip, or failure when strict).
        continueAfterFailure = true
    }

    override func tearDown() async throws {
        var text = "# Durchstich M1\n\n| # | Schritt | Ergebnis | Beobachtet |\n|---|---|---|---|\n"
        for (index, row) in report.enumerated() {
            text += "| \(index + 1) | \(row.step) | \(row.result) | \(row.note.replacingOccurrences(of: "|", with: "/")) |\n"
        }
        text += "\nStrikt: \(M1.strict ? "ja" : "nein (fehlende Bildschirme = übersprungen)")\n"
        let attachment = XCTAttachment(data: Data(text.utf8), uniformTypeIdentifier: "net.daringfireball.markdown")
        attachment.name = "durchstich-report.md"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testWalkthrough() throws {
        app = M1.launch(liveMotion: true, extraArguments: M1.Voice.launchArguments)

        try step("App öffnen, ROOK-Beitrag sichtbar") {
            try M1.require(app, M1.Screen.dashboard, step: "Dashboard")
            XCTAssertTrue(M1.element(app, "testBanner").exists, "Testansicht-Banner fehlt")
            let insight = try M1.require(app, M1.Rook.insight, step: "ROOK-Beitrag")
            let insightBefore = insight.label
            XCTAssertFalse(insightBefore.isEmpty, "ROOK-Beitrag ohne Text")
            for phrase in Self.forbidden {
                XCTAssertFalse(insightBefore.localizedCaseInsensitiveContains(phrase), "Verbotener Satz: \(phrase)")
            }
            return insightBefore
        }

        try step("Vorlesen und Stoppen") {
            let speak = try M1.require(app, M1.Rook.speak, step: "Vorlesen")
            speak.tap()
            Thread.sleep(forTimeInterval: 1.5)
            speak.tap()
            return speak.label
        }

        var orderAfterMove: [String] = []
        try step("Kachel verschieben") {
            let edit = try M1.require(app, M1.Dashboard.edit, step: "Kacheln anordnen")
            M1.reveal(edit, in: app)
            edit.tap()
            let before = M1.tileOrder(app)
            guard let first = before.first?.dropFirst(M1.Dashboard.tilePrefix.count) else {
                XCTFail("Keine Kachel sichtbar"); return ""
            }
            let down = try M1.require(app, M1.Dashboard.moveDown(String(first)), step: "Kachel nach unten")
            down.tap()
            try M1.require(app, M1.Dashboard.editDone, step: "Anordnen fertig").tap()
            orderAfterMove = M1.tileOrder(app)
            XCTAssertNotEqual(Array(before.prefix(2)), Array(orderAfterMove.prefix(2)), "Reihenfolge hat sich nicht geändert")
            XCTAssertEqual(orderAfterMove.dropFirst().first, before.first, "Kachel ist nicht eine Stelle nach unten gerückt")
            return orderAfterMove.prefix(3).joined(separator: ", ")
        }

        try step("Neustart, Reihenfolge bleibt") {
            app.terminate()
            app = M1.launch(liveMotion: true, extraArguments: M1.Voice.launchArguments)
            try M1.require(app, M1.Screen.dashboard, step: "Dashboard nach Neustart")
            let firstTile = app.descendants(matching: .any)
                .matching(NSPredicate(format: "identifier BEGINSWITH %@", M1.Dashboard.tilePrefix)).firstMatch
            M1.reveal(firstTile, in: app)
            let order = M1.tileOrder(app)
            XCTAssertEqual(Array(order.prefix(2)), Array(orderAfterMove.prefix(2)), "Reihenfolge nach Neustart verloren")
            return order.prefix(3).joined(separator: ", ")
        }

        try step("Kachel öffnet Verlauf") {
            let tile = try M1.require(app, M1.Dashboard.heartRateTile, step: "Puls-Kachel")
            M1.reveal(tile, in: app)
            tile.tap()
            try M1.require(app, M1.Screen.timeline, step: "Verlauf")
            return "Verlauf offen"
        }

        var firstSelection = ""
        try step("Cursor durch die Spuren") {
            let chart = try M1.require(app, M1.Timeline.chart, step: "Spuren")
            chart.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.4))
                .press(forDuration: 0.4, thenDragTo: chart.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.4)))
            let selection = try M1.require(app, M1.Timeline.selection, step: "Cursor-Anzeige", timeout: 5)
            firstSelection = selection.label
            XCTAssertTrue(containsClockTime(firstSelection), "Cursor zeigt keine Uhrzeit: \(firstSelection)")
            XCTAssertNotNil(firstSelection.rangeOfCharacter(from: .decimalDigits), "Cursor zeigt keinen Wert")
            return firstSelection
        }

        try step("Originalpunkt antippen") {
            let chart = M1.element(app, M1.Timeline.chart)
            chart.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.4)).tap()
            let selection = M1.element(app, M1.Timeline.selection)
            XCTAssertTrue(selection.waitForExistence(timeout: 5), "Auswahl verschwunden")
            XCTAssertTrue(containsClockTime(selection.label), "Originalpunkt ohne Messzeit: \(selection.label)")
            XCTAssertNotEqual(selection.label, firstSelection, "Antippen an anderer Stelle wählt denselben Punkt")
            return selection.label
        }

        try step("Hypnogramm-Abschnitt antippen") {
            try M1.tapFirstSleepSegment(app)
            let section = try M1.require(app, M1.Timeline.hypnogramSelection, step: "Schlafabschnitt", timeout: 5)
            XCTAssertTrue(containsClockTime(section.label), "Schlafabschnitt ohne Uhrzeit: \(section.label)")
            return section.label
        }

        try step("„Warum?“ zeigt Belege") {
            app.tabBars.buttons[M1.tabDashboard].tap()
            try M1.require(app, M1.Screen.dashboard, step: "zurück zum Dashboard")
            let why = try M1.require(app, M1.Rook.why, step: "Warum?")
            why.tap()
            try M1.require(app, M1.Screen.why, step: "Warum-Ansicht")
            let evidence = app.descendants(matching: .any)
                .matching(NSPredicate(format: "identifier BEGINSWITH %@", M1.Why.evidencePrefix))
            XCTAssertGreaterThan(evidence.count, 0, "Keine Belege hinter „Warum?“")
            let note = "\(evidence.count) Belege"
            let close = M1.element(app, M1.Why.close)
            if close.exists { close.tap() } else { app.swipeDown(velocity: .fast) }
            return note
        }

        try step("Korrektur „Ich bin krank“") {
            let insight = try M1.require(app, M1.Rook.insight, step: "ROOK-Beitrag")
            let before = insight.label
            try M1.require(app, M1.Rook.correct, step: "Korrigieren").tap()
            try M1.require(app, M1.Rook.correctionSick, step: "Ich bin krank").tap()
            let changed = expectation(for: NSPredicate(format: "label != %@", before), evaluatedWith: insight)
            wait(for: [changed], timeout: 20)
            return M1.element(app, M1.Rook.insight).label
        }

        var remainingPaused = ""
        try step("Einheit starten") {
            let action = try M1.require(app, M1.Rook.action, step: "Einheit starten")
            action.tap()
            try M1.require(app, M1.Screen.workout, step: "Trainingsansicht")
            try M1.require(app, M1.Workout.start, step: "Start").tap()
            try expectState("running")
            return M1.element(app, M1.Workout.remaining).label
        }

        try step("Pause") {
            try M1.require(app, M1.Workout.pause, step: "Pause").tap()
            try expectState("paused")
            remainingPaused = M1.element(app, M1.Workout.remaining).label
            Thread.sleep(forTimeInterval: 2.5)
            XCTAssertEqual(M1.element(app, M1.Workout.remaining).label, remainingPaused, "Timer läuft in der Pause weiter")
            return remainingPaused
        }

        try step("Fortsetzen") {
            try M1.require(app, M1.Workout.resume, step: "Fortsetzen").tap()
            try expectState("running")
            Thread.sleep(forTimeInterval: 2.5)
            let now = M1.element(app, M1.Workout.remaining).label
            // A repetition step shows "10 Wiederholungen" (no clock); only a timed phase must count down.
            if containsClockTime(remainingPaused) {
                XCTAssertNotEqual(now, remainingPaused, "Timer läuft nach dem Fortsetzen nicht")
            }
            return now
        }

        try step("Abschluss mit Anstrengung") {
            try M1.require(app, M1.Workout.finish, step: "Beenden").tap()
            try M1.require(app, M1.Screen.workoutSummary, step: "Zusammenfassung")
            let six = try M1.require(app, M1.Workout.exertion(6), step: "Anstrengung 6")
            M1.reveal(six, in: app)
            six.tap()
            let save = try M1.require(app, M1.Workout.save, step: "Speichern")
            M1.reveal(save, in: app)
            save.tap()
            return "Anstrengung 6"
        }

        try step("Eintrag im Verlauf") {
            app.tabBars.buttons[M1.tabTimeline].tap()
            try M1.require(app, M1.Screen.timeline, step: "Verlauf")
            let entry = try M1.require(app, M1.Timeline.workoutEntry, step: "Trainingseintrag")
            return entry.label
        }

        // Talking with ROOK (team 05, owner's explicit wish for the video). The simulator has no microphone:
        // -uiTestVoice speaks the first sentence word by word after the tap and the second one into ROOK's answer.
        try step("Sprachgespräch mit ROOK") {
            app.tabBars.buttons[M1.tabCoach].tap()
            let mic = try M1.require(app, M1.Voice.button, step: "Mit ROOK sprechen")
            M1.reveal(mic, in: app)
            XCTAssertEqual(mic.label, "Mit ROOK sprechen")
            mic.tap()

            // Listening → thinking → speaking, read from the status line while it happens.
            let status = try M1.require(app, M1.Voice.status, step: "Gesprächsstatus", timeout: 5)
            let seen = observePhases(status, until: M1.Voice.speaking, timeout: 25)
            let order = [M1.Voice.listening, M1.Voice.thinking, M1.Voice.speaking]
            let positions = order.map { phase in seen.firstIndex { $0.hasPrefix(phase) } }
            for (phase, position) in zip(order, positions) {
                XCTAssertNotNil(position, "Status „\(phase)“ nicht gesehen, gesehen: \(seen)")
            }
            let found = positions.compactMap { $0 }
            XCTAssertEqual(found, found.sorted(), "Status in falscher Reihenfolge: \(seen)")

            // The person's words in the transcript, ROOK's answer to them.
            let firstPerson = app.descendants(matching: .any).matching(identifier: M1.Voice.personTurn)
                .matching(NSPredicate(format: "label CONTAINS %@", M1.Voice.first)).firstMatch
            XCTAssertTrue(firstPerson.waitForExistence(timeout: 5), "Erste Äußerung nicht im Transkript")
            let rookTurns = app.descendants(matching: .any).matching(identifier: M1.Voice.rookTurn)
            XCTAssertTrue(rookTurns.firstMatch.waitForExistence(timeout: 10), "ROOK antwortet nicht")
            let firstAnswer = rookTurns.firstMatch.label

            // Barge-in: the second sentence cuts into the answer. Its live line exists only while ROOK listens,
            // so seeing it with the status "Ich höre zu" means ROOK stopped talking.
            let secondPerson = app.descendants(matching: .any).matching(identifier: M1.Voice.personTurn)
                .matching(NSPredicate(format: "label CONTAINS %@", "Warte mal")).firstMatch
            XCTAssertTrue(secondPerson.waitForExistence(timeout: 15), "Zweite Äußerung (Unterbrechung) nicht im Transkript")
            XCTAssertTrue(M1.element(app, M1.Voice.status).label.hasPrefix(M1.Voice.listening) ||
                          M1.element(app, M1.Voice.status).label.hasPrefix(M1.Voice.thinking),
                          "ROOK hört bei der Unterbrechung nicht zu: \(M1.element(app, M1.Voice.status).label)")
            M1.attachScreenshot(self, name: String(format: "durchstich__%02d-unterbrechung", stepNumber))
            // ROOK answers the new question with its own turn.
            let second = expectation(for: NSPredicate(format: "count >= 2"), evaluatedWith: rookTurns)
            wait(for: [second], timeout: 20)
            Thread.sleep(forTimeInterval: 1.5)   // let the answer be seen in the video

            let end = M1.element(app, M1.Voice.button)
            XCTAssertEqual(end.label, "Gespräch beenden")
            end.tap()
            let idle = expectation(for: NSPredicate(format: "label == %@", "Mit ROOK sprechen"), evaluatedWith: end)
            wait(for: [idle], timeout: 5)
            return "Status: \(seen.joined(separator: " → ")) · erste Antwort: \(firstAnswer.prefix(60))"
        }
    }

    // MARK: - Helpers

    /// Runs one step, attaches a screenshot and records the result. Strict: a missing screen fails the step and
    /// the walkthrough continues. Lenient: a missing screen skips the rest.
    private func step(_ name: String, _ body: () throws -> String) throws {
        stepNumber += 1
        let failuresBefore = testRun?.failureCount ?? 0
        do {
            let note = try body()
            let failed = (testRun?.failureCount ?? 0) > failuresBefore
            report.append((name, failed ? "✗" : "✓", note))
        } catch let missing as M1Missing {
            report.append((name, M1.strict ? "✗ fehlt" : "nicht integriert", missing.message))
            M1.attachScreenshot(self, name: String(format: "durchstich__%02d-fehlt", stepNumber))
            // Strict: `require` already recorded the failure; the walkthrough goes on so the later steps
            // (e.g. the voice conversation) still run and appear in the video. Lenient: skip as before.
            if M1.strict { return }
            throw XCTSkip("Noch nicht integriert – \(missing.message)")
        } catch {
            report.append((name, "✗", "\(error)"))
            M1.attachScreenshot(self, name: String(format: "durchstich__%02d-fehler", stepNumber))
            throw error
        }
        M1.attachScreenshot(self, name: String(format: "durchstich__%02d", stepNumber))
        // Short pause so each state is visible in the video.
        Thread.sleep(forTimeInterval: 0.8)
    }

    /// Distinct status lines in the order they appeared, sampled until one starts with `target`.
    private func observePhases(_ status: XCUIElement, until target: String, timeout: TimeInterval) -> [String] {
        var seen: [String] = []
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let label = status.label
            if seen.last != label { seen.append(label) }
            if label.hasPrefix(target) { break }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return seen
    }

    private func expectState(_ state: String) throws {
        let element = try M1.require(app, M1.Workout.state, step: "Trainingsstatus", timeout: 5)
        let reached = expectation(for: NSPredicate(format: "value == %@", state), evaluatedWith: element)
        wait(for: [reached], timeout: 5)
    }
}
