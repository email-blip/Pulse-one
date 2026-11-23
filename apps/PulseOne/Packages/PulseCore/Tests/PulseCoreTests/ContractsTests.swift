import Foundation
import Testing
@testable import PulseCore

@Suite("Rebuild contracts")
struct ContractsTests {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func segment(_ phase: SleepPhase, _ fromMinute: Double, _ toMinute: Double, session: UUID) -> SleepSegment {
        SleepSegment(subjectID: nil, sessionID: session, rawCode: 0, phase: phase,
                     start: t0.addingTimeInterval(fromMinute * 60), end: t0.addingTimeInterval(toMinute * 60),
                     source: .colmiRing, deviceID: "R03", firmware: nil)
    }

    @Test func colmiCodesMapAndUnknownStaysUnknown() {
        #expect(SleepPhase.colmi(code: 2) == .light)
        #expect(SleepPhase.colmi(code: 3) == .deep)
        #expect(SleepPhase.colmi(code: 4) == .rem)
        #expect(SleepPhase.colmi(code: 5) == .awake)
        #expect(SleepPhase.colmi(code: 9) == .unknown)
    }

    @Test func nightSeparatesInBedAsleepAndGaps() {
        let id = UUID()
        let night = SleepNight(sessionID: id, segments: [
            segment(.deep, 30, 60, session: id),
            segment(.light, 0, 30, session: id),
            segment(.awake, 60, 70, session: id),
            segment(.unknown, 90, 100, session: id),
        ])
        #expect(abs((night.inBed?.duration ?? 0) - 6000) < 0.001)
        #expect(night.asleep == 60 * 60)
        #expect(night.duration(of: .awake) == 10 * 60)
        #expect(night.gaps == [DateInterval(start: t0.addingTimeInterval(70 * 60), end: t0.addingTimeInterval(90 * 60))])
    }

    @Test func cursorInAGapSelectsNothing() {
        let points = [0.0, 300, 1800].map { offset in
            MeasurementPoint(id: UUID(), subjectID: nil, deviceID: "R03", source: .colmiRing, kind: .heartRate,
                             value: 60, unit: .beatsPerMinute, method: .deviceHistory, measuredAt: t0.addingTimeInterval(offset),
                             receivedAt: t0, importedAt: t0, quality: .valid, originalReference: "\(offset)")
        }
        #expect(TimelineState.nearest(to: t0.addingTimeInterval(320), in: points, tolerance: 150)?.originalReference == "300.0")
        #expect(TimelineState.nearest(to: t0.addingTimeInterval(1000), in: points, tolerance: 150) == nil)
    }

    @Test func workoutTimerSurvivesPauseAndSuspension() {
        var session = WorkoutSession(programID: "demo", steps: [
            WorkoutStep(id: "a", exerciseID: "squat", title: "Kniebeuge", variant: nil, workSeconds: 40,
                        repetitions: nil, restSeconds: 20),
            WorkoutStep(id: "b", exerciseID: "plank", title: "Unterarmstütz", variant: nil, workSeconds: 30,
                        repetitions: nil, restSeconds: 0),
        ])
        session.start(at: t0)
        #expect(session.remaining(at: t0.addingTimeInterval(10)) == 30)
        session.pause(at: t0.addingTimeInterval(10))
        #expect(session.announcement == .silent)
        #expect(session.remaining(at: t0.addingTimeInterval(100)) == 30)
        session.resume(at: t0.addingTimeInterval(100))
        #expect(session.scheduledPhaseEnd == t0.addingTimeInterval(130))
        // App was locked: catch up through work end (130), rest end (150) and plank end (180).
        session.catchUp(to: t0.addingTimeInterval(200))
        #expect(session.state == .finished)
        #expect(session.endedAt == t0.addingTimeInterval(180))
    }

    @Test func correctionKeepsTheOldInterpretation() {
        var insight = CoachInsight(subjectID: nil, createdAt: t0, observation: "Ruhepuls 6 über üblich",
                                   interpretation: "Heute Druck raus.", direction: .strained, evidence: [],
                                   action: CoachAction(kind: .rest, title: "Ruhiger Tag"), priority: 1,
                                   valid: DateInterval(start: t0, duration: 86_400), recheckAt: nil)
        insight.revise(with: UserCorrection(at: t0, text: "Ich bin krank"),
                       newInterpretation: "Dann heute nur Erholung.", reason: "Nutzer krank")
        #expect(insight.interpretation == "Dann heute nur Erholung.")
        #expect(insight.revisions.first?.interpretation == "Heute Druck raus.")
        #expect(insight.corrections.count == 1)
    }

    @Test func dashboardMovesAndKeepsIDsUnique() {
        var layout = DashboardLayout(subjectID: nil, tiles: [.metric(.heartRate), .metric(.steps), .metric(.heartRate)])
        #expect(layout.tiles.count == 2)
        layout.move(id: "metric.steps", to: 0)
        #expect(layout.tiles.map(\.id) == ["metric.steps", "metric.heart_rate"])
        layout.appendMissing([DashboardTile(id: "sleep")])
        layout.setVisible("metric.steps", false)
        #expect(layout.visibleTiles.map(\.id) == ["metric.heart_rate", "sleep"])
    }
}
