import Foundation

// ROOK at every opening of the app (owner's wish, 2026-11-25): how it is going right now and how he reads the
// body and the current values, with a next step that fits the time of day. The local reading appears at once;
// Claude's wording streams in after it (at most every ten minutes, standing permission of the check-ins).

/// The parts of a day ROOK fits his next step to.
public enum RookDayPart: String, Sendable, Equatable, CaseIterable {
    case night, morning, midday, afternoon, evening, late

    public static func at(_ date: Date, calendar: Calendar) -> RookDayPart {
        switch calendar.component(.hour, from: date) {
        case 0..<5: .night
        case 5..<11: .morning
        case 11..<14: .midday
        case 14..<18: .afternoon
        case 18..<22: .evening
        default: .late
        }
    }

    public var title: String {
        switch self {
        case .night: "Nacht"
        case .morning: "Morgen"
        case .midday: "Mittag"
        case .afternoon: "Nachmittag"
        case .evening: "Abend"
        case .late: "später Abend"
        }
    }
}

/// The person's values right now, each with the usual range it is compared with. Computed on the iPhone from
/// stored samples; nothing is invented and nothing is sent by building it.
public struct RookMoment: Sendable, Equatable {
    public struct Reading: Sendable, Equatable {
        public let value: Double
        public let at: Date
        /// Middle half of the comparison values; nil until there are enough of them.
        public let usual: ClosedRange<Double>?
        /// How many comparison values (days or readings) the usual range rests on.
        public let n: Int

        public init(value: Double, at: Date, usual: ClosedRange<Double>?, n: Int) {
            self.value = value
            self.at = at
            self.usual = usual
            self.n = n
        }

        public enum Position: Sendable, Equatable { case below, within, above, unknown }

        /// Clearly outside means more than half a range width beyond it, as for the nights.
        public var position: Position {
            guard let usual else { return .unknown }
            let margin = (usual.upperBound - usual.lowerBound) / 2
            if value > usual.upperBound + margin { return .above }
            if value < usual.lowerBound - margin { return .below }
            return .within
        }
    }

    public let now: Date
    public var heartRate: Reading?
    public var hrv: Reading?
    /// `.ringHRV` or `.heartRateVariability`; the two methods are never compared with each other.
    public var hrvKind: SampleKind?
    public var steps: Reading?
    public var sleepHours: Reading?

    public init(now: Date, heartRate: Reading? = nil, hrv: Reading? = nil, hrvKind: SampleKind? = nil,
                steps: Reading? = nil, sleepHours: Reading? = nil) {
        self.now = now
        self.heartRate = heartRate
        self.hrv = hrv
        self.hrvKind = hrvKind
        self.steps = steps
        self.sleepHours = sleepHours
    }

    /// Whether any value of today is there (pulse, HRV or steps).
    public var hasCurrentValues: Bool { heartRate != nil || hrv != nil || steps != nil }

    /// Pulse readings this recent count as "right now".
    static let heartRateRecency: TimeInterval = 2 * 3_600
    static let hrvRecency: TimeInterval = 24 * 3_600

    public static let sampleKinds: Set<SampleKind> = [.heartRate, .ringHRV, .heartRateVariability, .steps, .sleepDuration]
    /// How far back `build` looks (HRV and sleep compare with four weeks).
    public static let historyDays = 29

    /// Builds the moment from stored samples (usable ones only, of one person).
    public static func build(samples: [HealthSample], now: Date, calendar: Calendar) -> RookMoment {
        var moment = RookMoment(now: now)
        let past = samples.filter { $0.start <= now }
        let today = calendar.startOfDay(for: now)
        let sinceMidnight = now.timeIntervalSince(today)

        // Pulse now, against the same time of day (±1 hour) on the 14 days before today.
        let pulses = past.filter { $0.kind == .heartRate }
        if let latest = pulses.max(by: { $0.start < $1.start }), now.timeIntervalSince(latest.start) <= heartRateRecency {
            let comparison = pulses.filter { sample in
                guard sample.start < today, sample.start >= today.addingTimeInterval(-14 * 86_400) else { return false }
                let offset = sample.start.timeIntervalSince(calendar.startOfDay(for: sample.start))
                return abs(offset - sinceMidnight) <= 3_600
            }.map(\.value)
            moment.heartRate = Reading(value: latest.value, at: latest.start, usual: usualRange(comparison, minimum: 10),
                                       n: comparison.count)
        }

        // HRV: the newest reading of the last day, against the same method over four weeks.
        let hrvs = past.filter { $0.kind == .ringHRV || $0.kind == .heartRateVariability }
        if let latest = hrvs.max(by: { $0.start < $1.start }), now.timeIntervalSince(latest.start) <= hrvRecency {
            let comparison = hrvs.filter { $0.kind == latest.kind && $0.start < now.addingTimeInterval(-hrvRecency)
                && $0.start >= now.addingTimeInterval(-28 * 86_400) }.map(\.value)
            moment.hrv = Reading(value: latest.value, at: latest.start, usual: usualRange(comparison, minimum: 7),
                                 n: comparison.count)
            moment.hrvKind = latest.kind
        }

        // Steps so far today, against the steps up to the same clock time on the 14 days before. One source only
        // (ring and Apple Health can both count the same steps).
        let steps = past.filter { $0.kind == .steps }
        let todaySteps = steps.filter { $0.start >= today }
        if let source = Dictionary(grouping: todaySteps, by: \.source)
            .max(by: { $0.value.reduce(0) { $0 + $1.value } < $1.value.reduce(0) { $0 + $1.value } })?.key {
            let total = todaySteps.filter { $0.source == source }.reduce(0) { $0 + $1.value }
            var comparison: [Double] = []
            for offset in 1...14 {
                guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
                let cut = day.addingTimeInterval(sinceMidnight)
                let daySteps = steps.filter { $0.source == source && $0.start >= day && $0.start < cut }
                // Days without any step data say nothing about the usual amount.
                guard steps.contains(where: { $0.source == source && calendar.isDate($0.start, inSameDayAs: day) }) else { continue }
                comparison.append(daySteps.reduce(0) { $0 + $1.value })
            }
            moment.steps = Reading(value: total, at: now, usual: usualRange(comparison, minimum: 5), n: comparison.count)
        }

        // Sleep of the last night (ended within the last 18 hours), against the nights of four weeks.
        let sleeps = past.filter { $0.kind == .sleepDuration && $0.end <= now }
        if let source = Dictionary(grouping: sleeps, by: \.source).max(by: { $0.value.count < $1.value.count })?.key {
            let own = sleeps.filter { $0.source == source }
            let byNight = Dictionary(grouping: own) { calendar.startOfDay(for: $0.end) }
                .mapValues { $0.reduce(0) { $0 + $1.value } / 3_600 }
            if let last = own.max(by: { $0.end < $1.end }), now.timeIntervalSince(last.end) <= 18 * 3_600,
               let hours = byNight[calendar.startOfDay(for: last.end)] {
                let lastNight = calendar.startOfDay(for: last.end)
                let comparison = byNight.filter { $0.key < lastNight && $0.key >= lastNight.addingTimeInterval(-28 * 86_400) }
                    .map { $0.value }
                moment.sleepHours = Reading(value: hours, at: last.end, usual: usualRange(comparison, minimum: 5),
                                            n: comparison.count)
            }
        }
        return moment
    }

    static func usualRange(_ values: [Double], minimum: Int) -> ClosedRange<Double>? {
        guard values.count >= minimum, let low = IntelligenceStats.quantile(values, 0.25),
              let high = IntelligenceStats.quantile(values, 0.75), low <= high else { return nil }
        return low...high
    }
}

/// ROOK's reading of the moment on the iPhone: interpretation, direction and one next step for the time of day,
/// at most three short sentences. Numbers sit behind "Warum?".
public enum RookNow {
    /// A clear change or a warning sign (clarify, urgent): it stays the message and is not reworded by Claude.
    public static func needsAttention(_ statement: RookStatement) -> Bool {
        statement.insight.direction.severity >= CoachDirection.clarify.severity
    }

    public static func statement(moment: RookMoment, night: Insight, subjectID: UUID, calendar: Calendar) -> RookStatement {
        let nightStatement = RookLocal.statement(from: night, subjectID: subjectID, calendar: calendar)
        // A clear change over several nights stays the message all day; the referral is not softened by a calm hour.
        if nightStatement.insight.direction.severity >= CoachDirection.clarify.severity { return nightStatement }

        let part = RookDayPart.at(moment.now, calendar: calendar)
        let pulse = moment.heartRate?.position ?? .unknown
        let variability = moment.hrv?.position ?? .unknown
        let movement = moment.steps?.position ?? .unknown
        let tense = pulse == .above || variability == .below
        let calm = !tense && (pulse == .within || pulse == .below || variability == .within || variability == .above)
        let nightDirection = nightStatement.insight.direction
        let heavyNights = nightDirection == .strained || nightDirection == .watch

        let direction: CoachDirection = tense && heavyNights ? .strained
            : tense ? .watch
            : heavyNights ? .watch
            : nightDirection == .improving ? .improving : .stable

        var sentences: [String] = []
        // 1. How the body is right now.
        if pulse == .above && variability == .below {
            sentences.append("Dein Körper ist gerade angespannt, der Puls liegt höher und die Herzratenvariabilität tiefer als sonst um diese Zeit.")
        } else if pulse == .above {
            sentences.append("Dein Puls liegt gerade höher als sonst um diese Zeit.")
        } else if variability == .below {
            sentences.append("Deine Herzratenvariabilität ist gerade tiefer als sonst, dein Körper arbeitet noch an etwas.")
        } else if calm {
            sentences.append(variability == .unknown ? "Gerade ist dein Puls ruhig und in deinem Rahmen."
                             : "Gerade ist dein Körper ruhig, Puls und Herzratenvariabilität liegen in deinem Rahmen.")
        } else if let first = RookTextGuard.sentences(nightStatement.insight.interpretation).first {
            sentences.append(first)
        }
        // 2. The day so far, or the night in the morning.
        if part != .morning, part != .night, movement == .below {
            sentences.append("Bewegt hast du dich bisher weniger als sonst bis zu dieser Uhrzeit.")
        } else if part != .morning, part != .night, movement == .above {
            sentences.append("Bewegt hast du dich heute schon mehr als sonst.")
        } else if nightDirection == .improving {
            sentences.append("Die letzten Nächte haben dir gut getan.")
        } else if heavyNights {
            sentences.append("Die letzten Nächte ziehen noch an dir.")
        } else if let sleep = moment.sleepHours?.position, sleep == .below, part == .morning {
            sentences.append("Die Nacht war kürzer als sonst.")
        }
        // 3. The next step for this time of day.
        let next = step(part: part, tense: tense || heavyNights, movement: movement, greeting: !moment.hasCurrentValues
                        && nightStatement.insight.action?.kind == .askUser)
        sentences.append(next.sentence)
        let interpretation = Array(sentences.prefix(3)).joined(separator: " ")

        let headline = headline(direction: direction, part: part)
        let evidence = evidenceRefs(moment) + nightStatement.insight.evidence
        let anchor = moment.heartRate.map { DateInterval(start: $0.at.addingTimeInterval(-3_600), end: max($0.at, moment.now)) }
        let insight = CoachInsight(
            subjectID: subjectID, createdAt: moment.now, observation: observation(moment, night: nightStatement),
            interpretation: interpretation, direction: direction, evidence: evidence, action: next.action,
            priority: direction.severity, valid: DateInterval(start: moment.now, duration: 3_600),
            recheckAt: moment.now.addingTimeInterval(3_600),
            narration: RookLocal.cues(interpretation, anchor: anchor, track: .heartRate))
        var why = nightStatement.why
        why.comparison = "Puls: dieselbe Uhrzeit (plus minus eine Stunde) an deinen 14 Tagen vor heute. "
            + "Herzratenvariabilität: deine Werte der letzten 28 Tage mit demselben Verfahren. "
            + "Schritte: bis zu dieser Uhrzeit an deinen 14 Tagen vor heute. Nacht: " + nightStatement.why.comparison
        why.calculation = "Üblich ist die mittlere Hälfte deiner Vergleichswerte. Auffällig heißt: mehr als eine halbe "
            + "Bereichsbreite außerhalb. Die Nacht deutet ROOK wie am Morgen. " + nightStatement.why.calculation
        why.uncertainty = "Einzelne Messungen am Tag schwanken mit Bewegung, Kaffee und Stress; beim nächsten Öffnen schaue "
            + "ich wieder hin. " + nightStatement.why.uncertainty
        return RookStatement(insight: insight, headline: headline, why: why, source: .local)
    }

    struct Step {
        let sentence: String
        let action: CoachAction
    }

    static func step(part: RookDayPart, tense: Bool, movement: RookMoment.Reading.Position, greeting: Bool) -> Step {
        switch part {
        case .night, .late:
            return Step(sentence: "Am meisten hilft dir jetzt, bald ins Bett zu gehen.",
                        action: CoachAction(kind: .goToBed, title: "Schlafen gehen"))
        case .morning:
            if greeting {
                return Step(sentence: "Wie fühlst du dich heute? Sag es mir kurz, dann planen wir den Tag.",
                            action: CoachAction(kind: .askUser, title: "Wie geht's dir?", payload: "feeling"))
            }
            return tense
                ? Step(sentence: "Starte heute locker, zwanzig ruhige Minuten reichen.",
                       action: CoachAction(kind: .moveNow, title: "20 Minuten locker",
                                           payload: RookWorkoutRequest(minutes: 20, intensity: "easy").payload))
                : Step(sentence: "Heute verträgst du deine normale Einheit.",
                       action: CoachAction(kind: .startWorkout, title: "Meine Einheit starten"))
        case .midday:
            if tense {
                return Step(sentence: "Nimm dir zwei Minuten und atme ruhig durch.",
                            action: CoachAction(kind: .rest, title: "Kurz durchatmen", payload: "breathe=2"))
            }
            return Step(sentence: movement == .below ? "Zehn Minuten draußen gehen bringen dich gut durch den Nachmittag."
                                                     : "Ein kurzer Gang nach dem Essen hält dich wach.",
                        action: CoachAction(kind: .moveNow, title: "10 Minuten gehen",
                                            payload: RookWorkoutRequest(minutes: 10, intensity: "easy").payload))
        case .afternoon:
            return tense
                ? Step(sentence: "Mach heute lieber etwas Lockeres statt Vollgas.",
                       action: CoachAction(kind: .moveNow, title: "20 Minuten locker",
                                           payload: RookWorkoutRequest(minutes: 20, intensity: "easy").payload))
                : Step(sentence: "Wenn du heute trainieren willst, ist jetzt ein gutes Fenster.",
                       action: CoachAction(kind: .startWorkout, title: "Meine Einheit starten"))
        case .evening:
            if movement == .below && !tense {
                return Step(sentence: "Ein ruhiger Abendspaziergang hilft dir später beim Einschlafen.",
                            action: CoachAction(kind: .moveNow, title: "Abendspaziergang",
                                                payload: RookWorkoutRequest(minutes: 20, intensity: "easy").payload))
            }
            return Step(sentence: "Fahr jetzt langsam runter, dann wird die Nacht besser.",
                        action: CoachAction(kind: .rest, title: "Runterfahren", payload: "windDown"))
        }
    }

    static func headline(direction: CoachDirection, part: RookDayPart) -> String {
        switch direction {
        case .strained: return "Heute Tempo raus"
        case .watch: return "Etwas angespannt"
        case .improving: return "Läuft gut"
        default:
            switch part {
            case .morning: return "Guter Start"
            case .midday: return "Läuft ruhig"
            case .afternoon: return "Alles im Rahmen"
            case .evening: return "Ruhiger Abend"
            case .night, .late: return "Zeit für Ruhe"
            }
        }
    }

    static func evidenceRefs(_ moment: RookMoment) -> [EvidenceRef] {
        var refs: [EvidenceRef] = []
        let hour = DateInterval(start: moment.now.addingTimeInterval(-3_600), end: moment.now)
        if let pulse = moment.heartRate {
            refs.append(EvidenceRef(kind: .heartRate, window: DateInterval(start: pulse.at.addingTimeInterval(-3_600),
                                                                           end: max(pulse.at, moment.now)),
                                    label: "Puls gerade", shownValue: "\(RookLocal.number(pulse.value)) bpm",
                                    comparison: pulse.usual.map { "sonst \(range($0)) bpm um diese Zeit, aus \(pulse.n) Messungen" }))
        }
        if let hrv = moment.hrv {
            let method = moment.hrvKind == .heartRateVariability ? "Apple-Messung" : "Ring-Messung"
            refs.append(EvidenceRef(kind: moment.hrvKind ?? .ringHRV,
                                    window: DateInterval(start: hrv.at.addingTimeInterval(-3_600), end: max(hrv.at, moment.now)),
                                    label: "Herzratenvariabilität zuletzt (\(method))", shownValue: "\(RookLocal.number(hrv.value)) ms",
                                    comparison: hrv.usual.map { "sonst \(range($0)) ms, aus \(hrv.n) Messungen" }))
        }
        if let steps = moment.steps {
            refs.append(EvidenceRef(kind: .steps, window: DateInterval(start: Calendar.current.startOfDay(for: moment.now),
                                                                       end: max(moment.now, hour.start)),
                                    label: "Schritte bisher heute", shownValue: String(Int(steps.value.rounded())),
                                    comparison: steps.usual.map {
                                        "sonst \(Int($0.lowerBound.rounded()))–\(Int($0.upperBound.rounded())) bis zu dieser Uhrzeit, aus \(steps.n) Tagen"
                                    }))
        }
        return refs
    }

    /// One line with the numbers, shown under "Warum?" (never in the card text).
    static func observation(_ moment: RookMoment, night: RookStatement) -> String {
        var parts: [String] = []
        if let pulse = moment.heartRate {
            parts.append("Puls \(RookLocal.number(pulse.value)) bpm" + (pulse.usual.map { " (sonst \(range($0)) bpm um diese Zeit)" } ?? ""))
        }
        if let hrv = moment.hrv {
            parts.append("HRV \(RookLocal.number(hrv.value)) ms" + (hrv.usual.map { " (sonst \(range($0)) ms)" } ?? ""))
        }
        if let steps = moment.steps {
            parts.append("Schritte bisher \(Int(steps.value.rounded()))"
                         + (steps.usual.map { " (sonst \(Int($0.lowerBound.rounded()))–\(Int($0.upperBound.rounded())) bis jetzt)" } ?? ""))
        }
        if let sleep = moment.sleepHours {
            parts.append("Schlaf \(RookLocal.number(sleep.value)) h" + (sleep.usual.map { " (sonst \(range($0)) h)" } ?? ""))
        }
        if parts.isEmpty { return night.observation }
        return parts.joined(separator: " · ")
    }

    static func range(_ range: ClosedRange<Double>) -> String {
        "\(RookLocal.number(range.lowerBound))–\(RookLocal.number(range.upperBound))"
    }

    /// The numbers Claude may use when it words the moment: the values, their usual ranges and the night's evidence.
    public static func allowedNumbers(_ moment: RookMoment, local: RookStatement) -> [Double] {
        var numbers: [Double] = []
        for reading in [moment.heartRate, moment.hrv, moment.steps, moment.sleepHours].compactMap({ $0 }) {
            numbers += [reading.value, reading.value.rounded(), (reading.value * 10).rounded() / 10, Double(reading.n)]
            if let usual = reading.usual {
                numbers += [usual.lowerBound, usual.upperBound, usual.lowerBound.rounded(), usual.upperBound.rounded(),
                            (usual.lowerBound * 10).rounded() / 10, (usual.upperBound * 10).rounded() / 10]
            }
        }
        for ref in local.insight.evidence {
            for number in ResponseValidator.numbers(in: (ref.shownValue ?? "") + " " + (ref.comparison ?? "")) {
                numbers.append(number.value)
            }
        }
        return numbers
    }
}

// MARK: - Claude's wording of the moment

/// Prompt and streamed answer for ROOK at every opening. Claude words the same reading in ROOK's voice; direction
/// and evidence stay the iPhone's, numbers are checked against the moment, and each sentence runs the guards.
public enum RookNowPrompt {
    public static let version = 5
    public static let maxOutputTokens = 300

    public static func system(mode: SafetyMode) -> String {
        let task = """
        Die Person hat gerade die App geöffnet. Sag ihr in deinem Ton, wie es gerade läuft und wie du ihren Körper und \
        die aktuellen Werte einschätzt. Aufbau: Deutung, Richtung, nächste Handlung, die zur Tageszeit passt. Höchstens \
        drei kurze Sätze, möglichst ohne Zahlen (die stehen unter „Warum?“). Kein Markdown, keine Aufzählung, keine \
        Begrüßungsfloskel, keine Wiederholung der Überschrift.
        Antworte genau in diesem Format, ohne weitere Zeilen:
        Zeile 1: Überschrift mit höchstens vier Wörtern, ohne Punkt.
        Zeile 2: die höchstens drei Sätze.
        Zeile 3: AKTION: <kind> | <Knopftext mit höchstens drei Wörtern>
        kind ist eines von startWorkout, moveNow, rest, goToBed, askUser. Übernimm die vorgeschlagene Aktion, wenn sie \
        passt; ändere sie nur, wenn etwas aus den Werten klar dagegen spricht.
        """
        let rules = """
        Zahlen nur aus der Nachricht, nichts erfinden. Keine Prozentangaben für Ursachen oder Diagnosen. Nie erwähnen: \
        fehlende oder alte Daten, Abgleich, Basislinien, Lernphasen, Rollen- oder Haftungshinweise. Die Richtung der \
        Einschätzung des iPhones bleibt; du formulierst sie nur besser.
        """
        return [RookPrompts.voiceCharacter, task, RookPrompts.scope(mode), rules].joined(separator: "\n\n")
    }

    /// The user message: time, the values with their usual ranges, the night and the iPhone's reading.
    public static func message(moment: RookMoment, local: RookStatement, calendar: Calendar) -> String {
        let part = RookDayPart.at(moment.now, calendar: calendar)
        let time = String(format: "%02d:%02d", calendar.component(.hour, from: moment.now), calendar.component(.minute, from: moment.now))
        var lines = ["Uhrzeit: \(time) (\(part.title))."]
        lines.append("Werte jetzt: \(local.observation).")
        lines.append("Einschätzung des iPhones: \(local.headline). \(local.insight.interpretation)")
        lines.append("Richtung: \(local.insight.direction.title).")
        if let action = local.insight.action {
            lines.append("Vorgeschlagene Aktion: \(action.kind.rawValue) | \(action.title)")
        }
        return lines.joined(separator: "\n")
    }
}

/// Reads Claude's streamed lines (headline, sentences, action) and keeps only what passes the checks.
public struct RookNowReply: Sendable, Equatable {
    public private(set) var headline: String?
    public private(set) var sentences: [String] = []
    public private(set) var action: CoachAction?
    let allowed: [Double]
    let mode: SafetyMode

    static let actionKinds: Set<CoachActionKind> = [.startWorkout, .moveNow, .rest, .goToBed, .askUser]

    public init(allowed: [Double], mode: SafetyMode) {
        self.allowed = allowed
        self.mode = mode
    }

    /// Takes one finished piece (a line or a sentence) and says whether the visible text changed.
    public mutating func take(_ piece: String) -> Bool {
        let text = piece.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return false }
        if text.uppercased().hasPrefix("AKTION:") {
            action = Self.action(from: text)
            return false
        }
        if headline == nil {
            var line = text.replacingOccurrences(of: #"^(?:Zeile\s*1:|Überschrift:)\s*"#, with: "", options: .regularExpression)
            line = line.trimmingCharacters(in: CharacterSet(charactersIn: ".:*# ")).trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, line.split(separator: " ").count <= 6, RookTextGuard.isClean(line) else {
                headline = ""
                return take(text)
            }
            headline = line
            return true
        }
        guard sentences.count < 3 else { return false }
        var added = false
        for sentence in RookTextGuard.sentences(text) where sentences.count < 3 {
            guard let spoken = RookSpeech.speakable(sentence, mode: mode), Self.numbersOK(spoken, allowed: allowed) else { continue }
            sentences.append(spoken)
            added = true
        }
        return added
    }

    static func numbersOK(_ text: String, allowed: [Double]) -> Bool {
        let measured = text.replacingOccurrences(of: RookValidator.adviceNumbers, with: " ",
                                                 options: [.regularExpression, .caseInsensitive])
        return ResponseValidator.numbers(in: measured).allSatisfy { ResponseValidator.matches($0, allowed: allowed) }
    }

    static func action(from line: String) -> CoachAction? {
        let body = line.dropFirst("AKTION:".count)
        let parts = body.split(separator: "|", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2, let kind = CoachActionKind(rawValue: parts[0]), actionKinds.contains(kind) else { return nil }
        let title = parts[1].split(separator: " ").prefix(4).joined(separator: " ")
        guard !title.isEmpty, RookTextGuard.isClean(title) else { return nil }
        return CoachAction(kind: kind, title: title)
    }

    /// The local reading in Claude's words: direction, evidence and "Warum?" stay; text and action may change. An
    /// action of the same kind keeps the local payload (minutes, intensity).
    public func applied(to local: RookStatement) -> RookStatement? {
        guard !sentences.isEmpty else { return nil }
        let interpretation = sentences.joined(separator: " ")
        var chosen = local.insight.action
        if let action {
            chosen = action.kind == local.insight.action?.kind
                ? CoachAction(kind: action.kind, title: action.title, payload: local.insight.action?.payload)
                : action
        }
        let old = local.insight
        let anchor = old.narration.first?.anchor
        let track = old.narration.first?.track
        let insight = CoachInsight(
            id: old.id, subjectID: old.subjectID, createdAt: old.createdAt, observation: old.observation,
            interpretation: interpretation, direction: old.direction, evidence: old.evidence, action: chosen,
            priority: old.priority, valid: old.valid, recheckAt: old.recheckAt, corrections: old.corrections,
            revisions: old.revisions, narration: RookLocal.cues(interpretation, anchor: anchor, track: track))
        let title = (headline ?? "").isEmpty ? local.headline : (headline ?? local.headline)
        return RookStatement(insight: insight, headline: title, why: local.why, source: .claude)
    }
}
