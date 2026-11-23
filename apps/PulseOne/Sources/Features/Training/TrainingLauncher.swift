import Foundation
import PulseCore
import SwiftData

extension TrainingController {
    /// Opens today's session from the coach plan, for ROOK's action on the dashboard (`CoachAction.startWorkout`)
    /// and the Coach tab. An open session is shown again instead. Rest days open nothing. Without a coach setup a short, easy
    /// movement session from the library is offered, so the action never leads nowhere.
    func openToday(context: ModelContext, profileID: UUID?, now: Date) {
        if hasOpenSession {
            reopen()
            return
        }
        // UI tests (M1 walkthrough video): a fixed session that starts with a timed phase, so pause and resume
        // visibly stop and continue the clock. Never used outside `-uiTesting YES`.
        if LaunchOptions.current.isUITesting {
            open(Self.testSession(), title: "Testeinheit")
            return
        }
        if let snapshot = CoachRepository(context: context).snapshot(now: now, profileID: profileID) {
            // Rest and "bitte abklären" days have no session; nothing opens.
            if let block = WorkoutBuilder.primaryBlock(of: snapshot.plan), let session = WorkoutBuilder.session(for: block) {
                open(session, title: block.title)
            }
            return
        }
        let exercises = ExerciseLibrary.pick(.activation, count: 3, preferences: CoachPreferences(), dayIndex: 0)
        open(WorkoutSession(programID: "coach.fallback", steps: WorkoutBuilder.steps(for: exercises, intensity: .easy)),
             title: "Kurz bewegen")
    }

    /// 40 s timed hold, 20 s rest, then a repetition set.
    static func testSession() -> WorkoutSession {
        WorkoutSession(programID: "test.m1", steps: [
            WorkoutStep(id: "test.plank", exerciseID: "side-plank", title: "Seitstütz", variant: "links", workSeconds: 40,
                        repetitions: nil, restSeconds: 20),
            WorkoutStep(id: "test.squat", exerciseID: "squat", title: "Kniebeuge", variant: nil, workSeconds: nil,
                        repetitions: 10, restSeconds: 0),
        ])
    }
}
