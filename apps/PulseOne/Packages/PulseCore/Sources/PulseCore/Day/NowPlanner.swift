import Foundation

// TODAY's "Jetzt dran" tile: exactly one next step of the day, chosen from Begleiter and Coach by the time of
// day (verzahnung plan: Coach = WAS, Begleiter = WANN/WIE, Heute = JETZT). Pure rules, no I/O.

/// Where tapping the tile leads.
public enum NowTarget: String, Equatable, Sendable {
    /// The Begleiter screen (morning report, activation sessions, snacks).
    case companion
    /// Informational: the step lives in the Coach tab.
    case coach
    /// Informational: the evening note further down on TODAY.
    case eveningNote
    /// Nothing to open.
    case none
}

public struct NowItem: Equatable, Sendable {
    public let id: String
    public let title: String
    public let detail: String
    public let symbol: String
    public let target: NowTarget

    public init(id: String, title: String, detail: String, symbol: String, target: NowTarget) {
        self.id = id
        self.title = title
        self.detail = detail
        self.symbol = symbol
        self.target = target
    }
}

/// What the app knows about today, gathered from the Begleiter, the activation and the Coach.
public struct NowInput: Sendable {
    public var now: Date
    public var calendar: Calendar
    /// The Begleiter has today's morning report.
    public var hasMorningReport: Bool
    /// Morning activation is switched on and not done yet.
    public var morningActivationOpen: Bool
    /// Length of the morning activation in seconds (for the text).
    public var morningActivationSeconds: Int
    /// Next open midday/evening activation and its time.
    public var nextActivation: (slot: ActivationSlot, time: Date, seconds: Int)?
    /// Calm hint after quiet hours (Begleiter rule), nil when not due.
    public var snackHint: String?
    /// Today's main session from the Coach (nil on rest days or without a coach).
    public var coachSession: PlannedSession?
    /// The Coach evening review for today exists.
    public var eveningReviewDone: Bool
    /// The shared day guard: no strength on sick or alarm days.
    public var dayGuard: DayGuard

    public init(now: Date, calendar: Calendar, hasMorningReport: Bool = false, morningActivationOpen: Bool = false,
                morningActivationSeconds: Int = 0, nextActivation: (slot: ActivationSlot, time: Date, seconds: Int)? = nil,
                snackHint: String? = nil, coachSession: PlannedSession? = nil, eveningReviewDone: Bool = false,
                dayGuard: DayGuard = .open) {
        self.now = now
        self.calendar = calendar
        self.hasMorningReport = hasMorningReport
        self.morningActivationOpen = morningActivationOpen
        self.morningActivationSeconds = morningActivationSeconds
        self.nextActivation = nextActivation
        self.snackHint = snackHint
        self.coachSession = coachSession
        self.eveningReviewDone = eveningReviewDone
        self.dayGuard = dayGuard
    }
}

public enum NowPlanner {
    /// Morning ends at 11:00, the evening review is offered from 18:00, wind-down from 21:30.
    static let morningEndsHour = 11
    static let eveningStartsHour = 18
    static let windDownMinute = 21 * 60 + 30
    /// A midday/evening session counts as "due" from 30 minutes before until 60 minutes after its time.
    static let dueBefore: TimeInterval = 30 * 60
    public static let dueAfterSeconds: TimeInterval = 60 * 60

    public static func pick(_ input: NowInput) -> NowItem {
        let minute = input.calendar.component(.hour, from: input.now) * 60 + input.calendar.component(.minute, from: input.now)
        let hour = minute / 60
        let guardrail = input.dayGuard

        if guardrail.limit == .noTraining {
            if guardrail.seekHelp {
                return NowItem(id: "seekHelp", title: "Heute bitte kein Training",
                               detail: "Deine Angaben sollten ärztlich abgeklärt werden. Bei akuten Beschwerden sofort 112 wählen.",
                               symbol: "cross.case", target: .coach)
            }
            return NowItem(id: "rest", title: "Heute ist Erholung dran",
                           detail: "Trinken, ruhen, frische Luft, wenn es dir guttut. Training pausiert.",
                           symbol: "bed.double", target: .none)
        }
        if hour < morningEndsHour, !input.hasMorningReport {
            return NowItem(id: "morningReport", title: "Guten Morgen: dein Morgenbericht",
                           detail: "Wie war die Nacht, was passt heute? Kurz ansehen oder vorlesen lassen.",
                           symbol: "sunrise", target: .companion)
        }
        if hour < morningEndsHour, input.morningActivationOpen {
            return NowItem(id: "activation.morning", title: "Morgen-Aktivierung",
                           detail: joined("\(durationText(input.morningActivationSeconds)), geführt mit Timer.", guardText(guardrail)),
                           symbol: ActivationSlot.morning.symbol, target: .companion)
        }
        if let next = input.nextActivation,
           next.time.timeIntervalSince(input.now) <= dueBefore, input.now.timeIntervalSince(next.time) <= dueAfterSeconds {
            return NowItem(id: "activation.\(next.slot.rawValue)", title: next.slot.title,
                           detail: joined("\(durationText(next.seconds)), jetzt dran.", guardText(guardrail)),
                           symbol: next.slot.symbol, target: .companion)
        }
        if let hint = input.snackHint {
            return NowItem(id: "snack", title: "Zeit für einen Bewegungs-Snack", detail: hint,
                           symbol: ActivationSlot.snack.symbol, target: .companion)
        }
        if hour >= eveningStartsHour, !input.eveningReviewDone {
            return NowItem(id: "closeout", title: "Tagesabschluss",
                           detail: "Wie war dein Tag? Der Abendrückblick im Tab „Coach“ plant damit morgen.",
                           symbol: "moon.stars", target: .coach)
        }
        if minute >= windDownMinute {
            return NowItem(id: "windDown", title: "Zeit zum Runterfahren",
                           detail: "Bildschirm dimmen, Licht runter. Morgen früh gibt es deinen Morgenbericht.",
                           symbol: "moon.zzz", target: .none)
        }
        if hour >= morningEndsHour, let session = input.coachSession, session.kind != .rest {
            let minutes = guardrail.limit == .reduced ? max(10, Int((Double(session.minutes) * guardrail.limit.volumeFactor).rounded()))
                : session.minutes
            let title = guardrail.limit == .gentleOnly ? "Heute nur sanft bewegen" : "Heute im Plan: \(session.title)"
            let detail = guardrail.limit == .gentleOnly
                ? "Spazieren oder Mobilität, ohne Anstrengung. Details im Tab „Coach“."
                : "\(minutes) min. Details im Tab „Coach“."
            return NowItem(id: "coach", title: title, detail: detail, symbol: "figure.run", target: .coach)
        }
        if let next = input.nextActivation, next.time > input.now {
            return NowItem(id: "upcoming.\(next.slot.rawValue)", title: "Alles erledigt für den Moment",
                           detail: "Nächste Aktivierung um \(clock(next.time, calendar: input.calendar)).",
                           symbol: "checkmark.circle", target: .companion)
        }
        return NowItem(id: "clear", title: "Alles erledigt für den Moment",
                       detail: "Gerade ist nichts offen. Der Begleiter meldet sich, wenn etwas dran ist.",
                       symbol: "checkmark.circle", target: .none)
    }

    static func joined(_ parts: String...) -> String {
        parts.filter { !$0.isEmpty }.joined(separator: " ")
    }

    static func durationText(_ seconds: Int) -> String {
        let minutes = max(1, Int((Double(max(0, seconds)) / 60).rounded()))
        return minutes == 1 ? "Etwa 1 Minute" : "Etwa \(minutes) Minuten"
    }

    /// One short sentence when today's guard limits the session; empty otherwise.
    static func guardText(_ guardrail: DayGuard) -> String {
        switch guardrail.limit {
        case .full: guardrail.avoidRegions.isEmpty ? "" : "Übungen für schmerzende Bereiche lässt der Plan heute weg."
        case .reduced: "Heute etwas weniger als sonst."
        case .gentleOnly: "Heute nur sanfte Übungen."
        case .noTraining: ""
        }
    }

    static func clock(_ date: Date, calendar: Calendar) -> String {
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        return String(format: "%d:%02d", hour, minute)
    }
}
