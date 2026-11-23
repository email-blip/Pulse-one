import Foundation

/// The Coach tab's lead: a headline and at most two short sentences in ROOK's voice
/// (interpretation → direction → action). No gap sentences, no "lernt noch", no lists of numbers.
public struct CoachHeadline: Equatable, Sendable {
    public let headline: String
    public let line: String
    /// Label of the primary action; nil when today has nothing to start.
    public let actionTitle: String?

    public init(headline: String, line: String, actionTitle: String?) {
        self.headline = headline
        self.line = line
        self.actionTitle = actionTitle
    }

    /// - Parameter doneToday: sessions already finished today, newest last.
    public static func make(plan: DailyPlan, doneToday: [WorkoutSummary], canStart: Bool) -> CoachHeadline {
        let session = plan.suggested
        switch plan.decision {
        case .seekHelp:
            return CoachHeadline(headline: "Heute kein Training. Lass das bitte abklären.",
                                 line: plan.decision.explanation, actionTitle: nil)
        case .rest:
            return CoachHeadline(headline: "Heute Pause. Erholung ist heute das Training.",
                                 line: "Wenn du dich krank fühlst, bleibt das Training aus. Ruhig gehen nur, wenn es guttut.",
                                 actionTitle: nil)
        case .asPlanned, .offerLighter, .easyOrRecovery:
            break
        }
        if let last = doneToday.last {
            let effort = last.perceivedExertion.map { " Anstrengung \($0) von 10." } ?? ""
            return CoachHeadline(headline: "Einheit erledigt. Stark.",
                                 line: "\(last.title), \(last.minutes) Minuten.\(effort) Morgen schauen wir, wie du darauf reagierst.",
                                 actionTitle: canStart ? "Noch eine Einheit" : nil)
        }
        if session.kind == .rest {
            return CoachHeadline(headline: "Ruhetag. Genieß ihn.",
                                 line: "Gehen und lockere Bewegung sind willkommen, mehr braucht es heute nicht.",
                                 actionTitle: nil)
        }
        let minutes = "\(session.minutes) Minuten, \(session.intensity.title)."
        let action = canStart ? "Einheit starten" : nil
        switch plan.decision {
        case .offerLighter:
            return CoachHeadline(headline: "Heute lieber eine Stufe leichter.",
                                 line: "Ein Wert liegt deutlich neben deinem üblichen Bereich. \(session.title), \(minutes)",
                                 actionTitle: action)
        case .easyOrRecovery:
            return CoachHeadline(headline: "Heute locker bleiben.",
                                 line: "Die letzten Tage ziehen an dir. Bewegen ja, belasten nein: \(session.title), \(minutes)",
                                 actionTitle: action)
        default:
            if session.kind == .recovery {
                return CoachHeadline(headline: "Heute ist Erholung dran.", line: "\(session.title), \(minutes)", actionTitle: action)
            }
            return CoachHeadline(headline: "Heute ziehen wir \(session.title) durch.",
                                 line: "\(minutes) \(session.intensity.feeling)", actionTitle: action)
        }
    }
}
