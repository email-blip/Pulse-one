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
}
