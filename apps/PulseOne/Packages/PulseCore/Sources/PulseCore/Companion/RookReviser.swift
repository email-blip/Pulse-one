import Foundation

/// The person's quick answers change ROOK's advice at once and locally (Auftrag 04, point 5). Measurements
/// never change; the old interpretation stays as a `CoachRevision` (contract `CoachInsight.revise`).
/// Training actions carry a `RookWorkoutRequest` payload for team 05.
public enum RookReviser {
    /// Applies `feedback`. "Warum?" changes nothing (the screen opens the reasons instead).
    public static func apply(_ feedback: RookFeedback, to statement: RookStatement, at date: Date) -> RookStatement {
        guard feedback != .why else { return statement }
        let serious = statement.insight.direction.severity >= CoachDirection.clarify.severity
        let strained = statement.insight.direction.severity >= CoachDirection.watch.severity
        let text: String
        let action: CoachAction
        let reason: String
        switch feedback {
        case .sick:
            reason = "Du fühlst dich krank"
            if serious {
                text = "Danke, das passt ins Bild. Heute keine Einheit, viel trinken, und lass die Veränderung zeitnah ansehen. "
                    + "Bei Atemnot, Brustschmerz oder hohem Fieber nicht warten, dann 112."
                action = statement.insight.action ?? CoachAction(kind: .seeDoctor, title: "Verlauf ansehen", payload: "timeline=recent")
            } else {
                // The walkthrough (M1) starts a unit right after this: a gentle, startable one, never a hard one.
                text = "Dann ist heute Erholung dran, kein Training im eigentlichen Sinn. Wenn du magst: zehn Minuten sanft "
                    + "bewegen und durchatmen, mehr nicht. Kommen Fieber, Atemnot oder Brustschmerz dazu, lass dich ansehen."
                action = CoachAction(kind: .startWorkout, title: "Sanfte 10 Minuten",
                                     payload: RookWorkoutRequest(minutes: 10, intensity: "easy").payload)
            }
        case .onlyTenMinutes:
            reason = "Heute nur zehn Minuten"
            let intensity = strained ? "easy" : "normal"
            text = strained
                ? "Zehn Minuten locker passen gut zu heute. Ruhig bewegen, nicht ins Schwitzen kommen."
                : "Zehn Minuten reichen, wenn sie gut sind. Ich mach dir eine kurze Einheit draus."
            action = CoachAction(kind: serious ? .moveNow : .startWorkout, title: serious ? "10 Minuten gehen" : "10 Minuten starten",
                                 payload: RookWorkoutRequest(minutes: 10, intensity: serious ? "easy" : intensity).payload)
        case .lighter:
            reason = "Leichtere Variante gewünscht"
            text = "Gute Idee. Wir nehmen Tempo raus und halten trotzdem den Rhythmus."
            let minutes = RookWorkoutRequest(payload: statement.insight.action?.payload).minutes
            action = CoachAction(kind: serious ? .moveNow : .startWorkout, title: "Leichte Variante",
                                 payload: RookWorkoutRequest(minutes: minutes, intensity: "easy").payload)
        case .doesNotFit:
            reason = "Passt nicht zu deinem Gefühl"
            text = "Okay, dann zählt heute dein Gefühl mehr als die Werte. Sag mir kurz, was nicht passt, dann stelle ich es um."
            action = CoachAction(kind: .askUser, title: "Was passt nicht?", payload: "correction")
        case .why:
            return statement
        }
        var revised = statement
        revised.insight.revise(with: UserCorrection(at: date, text: feedback.title), newInterpretation: text, reason: reason)
        revised.insight.action = action
        revised.why.events.append("Du: „\(feedback.title)“ (\(timeText(date)))")
        return revised
    }

    static func timeText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}
