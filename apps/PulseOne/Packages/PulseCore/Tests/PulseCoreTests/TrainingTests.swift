import Foundation
import Testing
@testable import PulseCore

@Suite("Team 05: training session, cues, voice, notifications")
struct TrainingTests {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        return calendar
    }

    func twoTimedSteps() -> WorkoutSession {
        WorkoutSession(programID: "test", steps: [
            WorkoutStep(id: "a", exerciseID: "side-plank", title: "Seitstütz", variant: "links", workSeconds: 60,
                        repetitions: nil, restSeconds: 30),
            WorkoutStep(id: "b", exerciseID: "squat", title: "Kniebeuge", variant: nil, workSeconds: 60,
                        repetitions: nil, restSeconds: 0),
        ])
    }

    // MARK: Acceptance: pause → no announcement

    @Test func pauseSilencesPendingAndQueuedCues() {
        var session = twoTimedSteps()
        session.start(at: t0)
        let cue = WorkoutCuePlanner.cue(for: session, at: t0)
        #expect(cue?.text == "Los geht's. Seitstütz links. Eine Minute.")
        let token = cue?.token ?? session.cueToken()
        session.pause(at: t0.addingTimeInterval(1))
        #expect(!session.accepts(token))
        #expect(WorkoutCuePlanner.cue(for: session, at: t0.addingTimeInterval(2)) == nil)
        #expect(WorkoutCuePlanner.countdown(for: session, at: t0.addingTimeInterval(55), alreadySpoken: []) == nil)
        session.resume(at: t0.addingTimeInterval(20))
        // The stale cue stays silent after resuming; the screen shows the state, the voice does not drive on.
        #expect(WorkoutCuePlanner.cue(for: session, at: t0.addingTimeInterval(21)) == nil)
    }

    @Test func skipDropsTheOldCueAndAnnouncesTheNewStep() {
        var session = twoTimedSteps()
        session.start(at: t0)
        let old = session.cueToken()
        session.skip(at: t0.addingTimeInterval(5))
        #expect(!session.accepts(old))
        #expect(session.currentStep?.id == "b")
        #expect(WorkoutCuePlanner.cue(for: session, at: t0.addingTimeInterval(5))?.text == "Kniebeuge. Eine Minute.")
    }

    @Test func queueDropsTrainingCuesTheSessionNoLongerAccepts() {
        var session = twoTimedSteps()
        session.start(at: t0)
        var queue = SpeechQueue()
        queue.enqueue(SpeechItem(text: "Seitstütz", channel: .training, isSensitive: false, workoutToken: session.cueToken()))
        session.pause(at: t0.addingTimeInterval(1))
        var spoken: [String] = []
        while let item = queue.next() {
            if let token = item.workoutToken, !session.accepts(token) { continue }
            spoken.append(item.text)
        }
        #expect(spoken.isEmpty)
    }

    // MARK: Acceptance: lock 2 minutes → right remaining time

    @Test func lockedTwoMinutesCatchesUpToTheRightRemainingTime() {
        var session = twoTimedSteps()
        session.start(at: t0)
        let back = t0.addingTimeInterval(130)
        session.catchUp(to: back)
        // Work 0–60, rest 60–90, second work from 90: 40 s done, 20 s left.
        #expect(session.stepIndex == 1)
        #expect(session.phase == .work)
        #expect(session.remaining(at: back) == 20)
        #expect(WorkoutCuePlanner.cue(for: session, at: back)?.text == "Kniebeuge. Noch 20 Sekunden.")
    }

    @Test func pauseWhileLockedKeepsTheTimeStill() {
        var session = twoTimedSteps()
        session.start(at: t0)
        session.pause(at: t0.addingTimeInterval(10))
        session.catchUp(to: t0.addingTimeInterval(130))
        #expect(session.stepIndex == 0)
        #expect(session.remaining(at: t0.addingTimeInterval(130)) == 50)
        session.resume(at: t0.addingTimeInterval(130))
        #expect(session.scheduledPhaseEnd == t0.addingTimeInterval(180))
    }

    @Test func phaseEndNoticeNamesTheNextAction() {
        var session = twoTimedSteps()
        session.start(at: t0)
        let notice = WorkoutCuePlanner.phaseEndNotice(for: session)
        #expect(notice?.title == "Seitstütz geschafft")
        #expect(notice?.body == "Jetzt 30 Sekunden Pause. Danach: Kniebeuge.")
        session.pause(at: t0.addingTimeInterval(5))
        #expect(WorkoutCuePlanner.phaseEndNotice(for: session) == nil)
    }

    @Test func countdownOncePerPhase() {
        var session = twoTimedSteps()
        session.start(at: t0)
        let cue = WorkoutCuePlanner.countdown(for: session, at: t0.addingTimeInterval(51), alreadySpoken: [])
        #expect(cue?.text == "Noch zehn Sekunden.")
        let again = WorkoutCuePlanner.countdown(for: session, at: t0.addingTimeInterval(52),
                                                alreadySpoken: [cue?.token ?? session.cueToken("x")])
        #expect(again == nil)
        #expect(WorkoutCuePlanner.countdown(for: session, at: t0.addingTimeInterval(58), alreadySpoken: []) == nil)
    }

    // MARK: Acceptance: finish appears in the day's timeline

    @Test func finishedSessionAppearsOnTheTrainingTrack() {
        var session = twoTimedSteps()
        session.start(at: t0)
        session.catchUp(to: t0.addingTimeInterval(200))
        #expect(session.state == .finished)
        #expect(WorkoutCuePlanner.cue(for: session, at: t0.addingTimeInterval(200))?.kind == .announcingFinish)
        session.perceivedExertion = 6
        let summary = WorkoutSummary.make(from: session, title: "Krafttraining", skippedStepIDs: [])
        #expect(summary?.completedSteps == 2)
        #expect(summary?.minutes == 3)
        #expect(summary?.load == 18)
        let day = DateInterval(start: utc.startOfDay(for: t0), duration: 24 * 3600)
        let entries = WorkoutSummary.timelineEntries([summary].compactMap { $0 }, in: day)
        #expect(entries.count == 1)
        #expect(entries.first?.track == .training)
        #expect(entries.first?.interval.start == t0)
        #expect(entries.first?.detail.contains("Anstrengung 6/10") == true)
        let otherDay = DateInterval(start: day.end.addingTimeInterval(3600), duration: 3600)
        #expect(WorkoutSummary.timelineEntries([summary].compactMap { $0 }, in: otherDay).isEmpty)
    }

    @Test func earlyEndCountsOnlyFinishedSteps() {
        var session = twoTimedSteps()
        session.start(at: t0)
        session.cancel(at: t0.addingTimeInterval(20))
        let summary = WorkoutSummary.make(from: session, title: "Test", skippedStepIDs: [])
        #expect(summary?.completedSteps == 0)
        #expect(summary?.finishedAsPlanned == false)
        #expect(summary?.executionText == "0 von 2 Abschnitten, früher beendet")
    }

    @Test func reactionUsesOnlyPulseInsideTheSession() {
        let window = DateInterval(start: t0, duration: 600)
        let values: [(date: Date, bpm: Double)] = [(t0.addingTimeInterval(-60), 60), (t0.addingTimeInterval(60), 110),
                                                   (t0.addingTimeInterval(300), 130), (t0.addingTimeInterval(900), 70)]
        let reaction = WorkoutReaction.measure(heartRate: values, during: window)
        #expect(reaction?.sampleCount == 2)
        #expect(reaction?.averageHeartRate == 120)
        #expect(reaction?.maxHeartRate == 130)
        #expect(WorkoutReaction.measure(heartRate: [], during: window) == nil)
    }

    // MARK: Plan → session

    @Test func dosesParse() {
        #expect(ExerciseDose.parse("3 × 10") == ExerciseDose(sets: 3, repetitions: 10, seconds: nil, perSide: false))
        #expect(ExerciseDose.parse("je Seite 30 s") == ExerciseDose(sets: 1, repetitions: nil, seconds: 30, perSide: true))
        #expect(ExerciseDose.parse("2 min") == ExerciseDose(sets: 1, repetitions: nil, seconds: 120, perSide: false))
        #expect(ExerciseDose.parse("8 ×") == ExerciseDose(sets: 1, repetitions: 8, seconds: nil, perSide: false))
        #expect(ExerciseDose.parse("3 × 20 s je Seite") == ExerciseDose(sets: 3, repetitions: nil, seconds: 20, perSide: true))
        #expect(ExerciseDose.parse("3 × 8 je Seite") == ExerciseDose(sets: 3, repetitions: 8, seconds: nil, perSide: true))
        #expect(ExerciseDose.parse("je Richtung 10 ×") == ExerciseDose(sets: 1, repetitions: 10, seconds: nil, perSide: false))
    }

    @Test func everyLibraryDoseGivesAPlayableStep() {
        let steps = WorkoutBuilder.steps(for: ExerciseLibrary.all, intensity: .moderate)
        #expect(steps.allSatisfy { ($0.workSeconds ?? 0) > 0 || ($0.repetitions ?? 0) > 0 })
        #expect(Set(steps.map(\.id)).count == steps.count)
        #expect(steps.last?.restSeconds == 0)
    }

    @Test func sidePlankRunsPerSideAndSet() throws {
        let plank = try #require(ExerciseLibrary.exercise("side-plank"))
        let steps = WorkoutBuilder.steps(for: [plank], intensity: .easy)
        #expect(steps.count == 6)
        #expect(steps.first?.variant == "links · Satz 1 von 3")
        #expect(steps.first?.restSeconds == 30)
        #expect(steps.last?.restSeconds == 0)
    }

    @Test func blockWithoutExercisesBecomesOneTimedStep() {
        let block = DayBlock(id: "main", kind: .mainWorkout, title: "Laufen", minutes: 30, intensity: .easy,
                             detail: "", exercises: [], reason: nil)
        let session = WorkoutBuilder.session(for: block)
        #expect(session?.steps.count == 1)
        #expect(session?.steps.first?.workSeconds == 1800)
        let rest = DayBlock(id: "main", kind: .recovery, title: "Ruhetag", minutes: 0, intensity: nil, detail: "",
                            exercises: [], reason: nil)
        #expect(WorkoutBuilder.session(for: rest) == nil)
    }

    // MARK: Pronunciation

    @Test func pronunciation() {
        #expect(SpokenGerman.prepare("HRV 42 ms") == "Ha Er Vau 42 Millisekunden")
        #expect(SpokenGerman.prepare("Puls 52 bpm um 07:30 Uhr") == "Puls 52 Schläge pro Minute um 7 Uhr 30")
        #expect(SpokenGerman.prepare("Wecker 07:00") == "Wecker 7 Uhr")
        #expect(SpokenGerman.prepare("23:05") == "23 Uhr 5")
        #expect(SpokenGerman.prepare("3 × 10") == "3 mal 10")
        #expect(SpokenGerman.prepare("je Seite 30 s") == "je Seite 30 Sekunden")
        #expect(SpokenGerman.prepare("1 min gehen") == "eine Minute gehen")
        #expect(SpokenGerman.prepare("2 min") == "2 Minuten")
        #expect(SpokenGerman.prepare("SpO₂ 97 %") == "Sauerstoffsättigung 97 %")
        #expect(SpokenGerman.prepare("Hüftöffner 90/90") == "Hüftöffner neunzig neunzig")
        #expect(SpokenGerman.prepare("Nordic Hamstrings (mit Partner)") == "Nordik Hämstrings (mit Partner)")
        #expect(SpokenGerman.prepare("40–50 Jahre") == "40 bis 50 Jahre")
        #expect(SpokenGerman.prepare("ca. 5 km") == "circa 5 Kilometer")
        #expect(SpokenGerman.prepare("Mallorca.") == "Mallorca.")
        #expect(SpokenGerman.prepare("Satz 3:1") == "Satz 3:1")
    }

    @Test func everyExerciseNameStaysReadable() {
        for exercise in ExerciseLibrary.all {
            let spoken = SpokenGerman.prepare(exercise.name)
            #expect(!spoken.isEmpty)
            #expect(!spoken.contains("×"))
        }
    }

    // MARK: Speech queue and greeting

    @Test func queueOrder() {
        var queue = SpeechQueue()
        queue.enqueue(SpeechItem(text: "Hallo", channel: .greeting, isSensitive: false))
        queue.enqueue(SpeechItem(text: "Hallo nochmal", channel: .greeting, isSensitive: false))
        queue.enqueue(SpeechItem(text: "Deutung", channel: .interpretation, isSensitive: true))
        queue.enqueue(SpeechItem(text: "Alt", channel: .training, isSensitive: false))
        queue.enqueue(SpeechItem(text: "Neu", channel: .training, isSensitive: false))
        queue.enqueue(SpeechItem(text: "Achtung", channel: .alert, isSensitive: true))
        #expect(queue.pending.map(\.text) == ["Achtung", "Neu", "Hallo", "Deutung"])
        queue.removeAll { $0.isSensitive }
        #expect(queue.pending.map(\.text) == ["Neu", "Hallo"])
    }

    @Test func greetingNotOnEveryTabChange() {
        #expect(GreetingPolicy.shouldGreet(lastGreeting: nil, now: t0, calendar: utc))
        #expect(!GreetingPolicy.shouldGreet(lastGreeting: t0, now: t0.addingTimeInterval(600), calendar: utc))
        #expect(GreetingPolicy.shouldGreet(lastGreeting: t0, now: t0.addingTimeInterval(5 * 3600), calendar: utc))
        #expect(GreetingPolicy.shouldGreet(lastGreeting: t0, now: t0.addingTimeInterval(26 * 3600), calendar: utc))
    }

    // MARK: Corrections from ROOK (team 04)

    @Test func correctionsChangeTheDay() {
        let sick = CoachCorrections.effect(of: [UserCorrection(at: t0, text: "Ich bin krank")], on: t0, calendar: utc)
        #expect(sick.feelsSick)
        #expect(sick.intents.isEmpty)
        #expect(CoachRules.decide(signals: [], subjective: sick.merged(into: nil)) == .rest)

        let short = CoachCorrections.effect(of: [UserCorrection(at: t0, text: "Heute nur 15 Minuten, bin müde")], on: t0, calendar: utc)
        #expect(short.minutesLimit == 15)
        #expect(short.easier)
        #expect(short.intents == [.easier, .timeLimit(minutes: 15)])

        let knee = CoachCorrections.effect(of: [UserCorrection(at: t0, text: "Mein Knie zwickt")], on: t0, calendar: utc)
        #expect(knee.merged(into: nil)?.painRegions == [.knee])

        let yesterday = CoachCorrections.effect(of: [UserCorrection(at: t0.addingTimeInterval(-86_400), text: "krank")],
                                                on: t0, calendar: utc)
        #expect(yesterday.isEmpty)
    }

    // MARK: Notifications

    @Test func notificationRules() {
        let calendar = utc
        let day = calendar.startOfDay(for: t0)
        let noon = day.addingTimeInterval(12 * 3600)
        let late = day.addingTimeInterval(23 * 3600)
        let rules = NotificationRules()
        let move = NotificationCandidate(topic: "nudge.movement", fireAt: noon, fingerprint: "Kurz bewegen")
        #expect(NotificationPolicy.allows(move, rules: rules, history: [], calendar: calendar))
        #expect(!NotificationPolicy.allows(NotificationCandidate(topic: "nudge.movement", fireAt: late, fingerprint: "x"),
                                           rules: rules, history: [], calendar: calendar))
        #expect(!NotificationPolicy.allows(NotificationCandidate(topic: "nudge.movement", fireAt: noon, fingerprint: "x", isDone: true),
                                           rules: rules, history: [], calendar: calendar))
        let sent = SentNotification(topic: "nudge.movement", fingerprint: "Kurz bewegen", at: noon.addingTimeInterval(-3600))
        #expect(!NotificationPolicy.allows(move, rules: rules, history: [sent], calendar: calendar))
        let changed = NotificationCandidate(topic: "nudge.movement", fireAt: noon, fingerprint: "Neuer Stand")
        #expect(NotificationPolicy.allows(changed, rules: rules, history: [sent], calendar: calendar))
        let paused = NotificationRules(pausedUntil: NotificationPolicy.endOfToday(noon, calendar: calendar))
        #expect(!NotificationPolicy.allows(changed, rules: paused, history: [], calendar: calendar))
        let phaseEnd = NotificationCandidate(topic: "training.phase", fireAt: late, fingerprint: "a", isRequestedByPerson: true)
        #expect(NotificationPolicy.allows(phaseEnd, rules: paused, history: [], calendar: calendar))
    }

    // MARK: Coach lead

    @Test func headlineTone() {
        let rest = DailyPlan(day: t0, decision: .rest, signals: [], planned: .rest, suggested: .rest, blocks: [], notes: [])
        let lead = CoachHeadline.make(plan: rest, doneToday: [], canStart: false)
        #expect(lead.actionTitle == nil)
        let banned = ["lernt noch", "Basislinie", "kein Arzt", "fehlt", "unbekannt"]
        let session = PlannedSession(kind: .main, sport: .strength, minutes: 30, intensity: .moderate)
        for decision in [ReadinessDecision.asPlanned, .offerLighter, .easyOrRecovery, .rest, .seekHelp] {
            let plan = DailyPlan(day: t0, decision: decision, signals: [], planned: session, suggested: session, blocks: [], notes: [])
            let text = CoachHeadline.make(plan: plan, doneToday: [], canStart: true)
            #expect(!banned.contains { text.headline.contains($0) || text.line.contains($0) })
        }
    }
}
