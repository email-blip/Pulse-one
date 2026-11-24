import Foundation

/// ROOK's own reading on the iPhone, built from the night engine (`InsightEngine`). Used whenever Claude is
/// not asked (no key, offline, budget, nothing new) and as the frame a Claude answer is checked against.
/// The visible text never lists numbers and never talks about missing data or a baseline (plan §9);
/// numbers, comparison, method and alternatives go behind "Warum?".
public enum RookLocal {
    public static let name = "ROOK"

    /// Resting pulse this far above the median on at least `clarifyNights` of the last four nights is more
    /// than a bad day: ROOK advises to have it checked.
    static let clarifyRise: Double = 10
    static let clarifyNights = 3
    /// A drop of the resting pulse over the last three nights against the week before counts as improving.
    static let improvingDrop: Double = 2

    public static func statement(from insight: Insight, slot: CheckInSlot? = nil, subjectID: UUID? = nil,
                                 calendar: Calendar) -> RookStatement {
        switch insight.insightCase {
        case .learning:
            if let night = lastNight(insight, calendar: calendar) {
                return reference(insight, night: night, slot: slot, subjectID: subjectID ?? insight.profileID, calendar: calendar)
            }
            return greeting(at: insight.createdAt, slot: slot, subjectID: subjectID ?? insight.profileID, calendar: calendar,
                            nights: insight.nights)
        case .dataGap:
            return greeting(at: insight.createdAt, slot: slot, subjectID: subjectID ?? insight.profileID, calendar: calendar,
                            nights: insight.nights)
        case .recovered:
            return recovered(insight, subjectID: subjectID ?? insight.profileID, calendar: calendar)
        case .changedNights:
            return changed(insight, subjectID: subjectID ?? insight.profileID, calendar: calendar)
        }
    }

    // MARK: Without a current basis

    /// No fresh night or too few nights: a normal greeting and an offer, no diagnosis of the day.
    public static func greeting(at now: Date, slot: CheckInSlot?, subjectID: UUID?, calendar: Calendar,
                                nights: [NightPoint] = []) -> RookStatement {
        let hello = salutation(at: now, slot: slot, calendar: calendar)
        let interpretation = "Wie fühlst du dich heute? Sag es mir kurz, dann planen wir den Tag zusammen."
        let insight = CoachInsight(
            subjectID: subjectID, createdAt: now,
            observation: "Für heute liegt noch keine Nacht vor, die ich deuten würde.",
            interpretation: interpretation, direction: .stable, evidence: [],
            action: CoachAction(kind: .askUser, title: "Wie geht's dir?", payload: "feeling"),
            priority: 0, valid: dayInterval(now, calendar: calendar), recheckAt: nil,
            narration: cues(interpretation, anchor: nil, track: nil))
        let count = nights.filter { !$0.isEmpty }.count
        let why = RookWhy(
            comparison: count >= InsightEngine.minimumNights
                ? "Deine letzten Nächte; die heutige ist noch nicht auf dem iPhone."
                : "Erfahrungswerte für Erwachsene, bis \(InsightEngine.minimumNights) eigene Nächte zusammen sind (bisher \(count)).",
            events: [], calculation: "Keine Deutung ohne Werte der letzten Nacht. Ältere Werte zeige ich nicht als heute.",
            alternatives: [],
            uncertainty: "Ohne aktuelle Werte stelle ich keine Tagesdiagnose. Dein Befinden ist heute die beste Quelle.")
        return RookStatement(insight: insight, headline: hello, why: why, source: .local)
    }

    // MARK: Few own nights: compare with experience values

    /// Typical values for adults, used until there are enough own nights (owner 2026-11-23: compare with
    /// experience values instead of talking about a missing baseline).
    static let referenceRestingPulse: ClosedRange<Double> = 45...65
    static let referenceSleep: ClosedRange<Double> = 7...9

    static func lastNight(_ insight: Insight, calendar: Calendar) -> NightPoint? {
        insight.nights.last { calendar.isDate($0.date, inSameDayAs: insight.createdAt) && !$0.isEmpty }
    }

    /// Last night against experience values: a short reading, a startable unit, the values behind "Warum?".
    static func reference(_ insight: Insight, night: NightPoint, slot: CheckInSlot?, subjectID: UUID,
                          calendar: Calendar) -> RookStatement {
        let hello = salutation(at: insight.createdAt, slot: slot, calendar: calendar)
        let pulseHigh = night.restingHeartRate.map { $0 > referenceRestingPulse.upperBound } ?? false
        let sleepShort = night.sleepHours.map { $0 < referenceSleep.lowerBound - 1 } ?? false
        let interpretation: String
        let direction: CoachDirection
        let action: CoachAction
        if pulseHigh || sleepShort {
            let what = pulseHigh && sleepShort ? "Die Nacht war kurz und dein Puls eher hoch"
                : (pulseHigh ? "Dein Puls war heute Nacht eher hoch" : "Die Nacht war kurz")
            interpretation = "\(what), das kostet Energie. Heute lieber gleichmäßig statt hart; wie fühlst du dich?"
            direction = .watch
            action = CoachAction(kind: .startWorkout, title: "Lockere Einheit",
                                 payload: RookWorkoutRequest(minutes: 20, intensity: "easy").payload)
        } else {
            interpretation = "Die Nacht sieht ruhig aus: entspannter Puls, ordentlich Schlaf. "
                + "Wenn du dich auch so fühlst, spricht nichts gegen deine Einheit."
            direction = .stable
            action = CoachAction(kind: .startWorkout, title: "Meine Einheit starten",
                                 payload: RookWorkoutRequest(intensity: "normal").payload)
        }
        let today = calendar.startOfDay(for: insight.createdAt)
        let window = DateInterval(start: today.addingTimeInterval(-6 * 3_600), duration: 17 * 3_600)
        var evidence: [EvidenceRef] = []
        if let pulse = night.restingHeartRate {
            evidence.append(EvidenceRef(kind: .restingHeartRate, window: window, label: "Ruhepuls letzte Nacht",
                                        shownValue: "\(number(pulse)) bpm",
                                        comparison: "Erfahrungswert Erwachsene \(number(referenceRestingPulse.lowerBound))–\(number(referenceRestingPulse.upperBound)) bpm"))
        }
        if let sleep = night.sleepHours {
            evidence.append(EvidenceRef(kind: .sleepDuration, window: window, label: "Schlaf letzte Nacht",
                                        shownValue: "\(number(sleep)) h",
                                        comparison: "Erfahrungswert Erwachsene \(number(referenceSleep.lowerBound))–\(number(referenceSleep.upperBound)) h"))
        }
        if let hrv = night.hrv {
            evidence.append(EvidenceRef(kind: insight.evidence.first?.method.contains("SDNN") == true ? .heartRateVariability : .ringHRV,
                                        window: window, label: "HRV letzte Nacht", shownValue: "\(number(hrv)) ms",
                                        comparison: "nur mit deinen eigenen Nächten vergleichbar"))
        }
        let observation = evidence.map { "\($0.label) \($0.shownValue ?? "")" }.joined(separator: " · ")
        let coach = CoachInsight(
            subjectID: subjectID, createdAt: insight.createdAt, observation: observation, interpretation: interpretation,
            direction: direction, evidence: evidence, action: action, priority: direction == .watch ? 2 : 1,
            valid: dayInterval(insight.createdAt, calendar: calendar), recheckAt: insight.recheck.at,
            narration: cues(interpretation, anchor: window, track: .heartRate))
        let own = insight.nights.filter { !$0.isEmpty }.count
        let why = RookWhy(
            comparison: "Erfahrungswerte für Erwachsene. Ab \(InsightEngine.minimumNights) eigenen Nächten vergleiche ich mit "
                + "deinem eigenen Bereich (bisher \(own)).",
            events: [],
            calculation: "Ruhepuls ist der niedrigste Nachtwert, Schlaf die Schlafdauer der Nacht. Deutlich heißt: Ruhepuls über "
                + "\(number(referenceRestingPulse.upperBound)) bpm oder weniger als \(number(referenceSleep.lowerBound - 1)) Stunden Schlaf.",
            alternatives: [],
            uncertainty: "Erfahrungswerte streuen von Mensch zu Mensch stark; dein eigener Verlauf wird genauer.")
        return RookStatement(insight: coach, headline: hello, why: why, source: .local)
    }

    static func salutation(at now: Date, slot: CheckInSlot?, calendar: Calendar) -> String {
        let hour = calendar.component(.hour, from: now)
        switch slot {
        case .some(.morning): return "Guten Morgen"
        case .some(.midday): return "Hallo"
        case .some(.evening): return "Guten Abend"
        case .none: return hour < 11 ? "Guten Morgen" : (hour < 18 ? "Hallo" : "Guten Abend")
        }
    }

    // MARK: Good nights

    static func recovered(_ insight: Insight, subjectID: UUID, calendar: Calendar) -> RookStatement {
        let better = insight.headline == "Gut erholt"
        let trend = improvingTrend(insight.nights)
        let headline: String
        let interpretation: String
        let direction: CoachDirection
        let action: CoachAction
        if trend {
            headline = "Wieder im Rhythmus"
            interpretation = "Dein Rhythmus wird wieder stabiler. Die letzten Nächte passen besser zusammen, und dein Puls "
                + "kommt nachts schneller runter. Genau diese Regelmäßigkeit würde ich jetzt halten."
            direction = .improving
            action = CoachAction(kind: .startWorkout, title: "Meine Einheit starten",
                                 payload: RookWorkoutRequest(intensity: "normal").payload)
        } else if better {
            headline = "Gut erholt"
            interpretation = "Starke Nacht: ruhiger Puls, gute Erholung. Dein Körper hat heute Reserven. "
                + "Wenn du eine harte Einheit willst, dann heute."
            direction = .improving
            action = CoachAction(kind: .startWorkout, title: "Meine Einheit starten",
                                 payload: RookWorkoutRequest(intensity: "hard").payload)
        } else {
            headline = "Solide Nacht"
            interpretation = "Alles in deinem Rahmen, nichts zieht gerade an dir. Trainier wie geplant. Fühlst du dich auch so?"
            direction = .stable
            action = CoachAction(kind: .startWorkout, title: "Meine Einheit starten",
                                 payload: RookWorkoutRequest(intensity: "normal").payload)
        }
        return make(insight, subjectID: subjectID, headline: headline, interpretation: interpretation, direction: direction,
                    action: action, priority: trend ? 2 : 1, calendar: calendar)
    }

    /// Resting pulse of the last three nights at least `improvingDrop` below the seven nights before, or HRV
    /// of the last three nights clearly above them.
    static func improvingTrend(_ nights: [NightPoint]) -> Bool {
        let sorted = nights.sorted { $0.date < $1.date }
        let recent = sorted.suffix(3)
        let before = sorted.dropLast(3).suffix(7)
        func median(_ values: [Double]) -> Double? {
            values.isEmpty ? nil : PersonalBaseline.percentile(values.sorted(), 0.5)
        }
        guard recent.count == 3, before.count >= 5 else { return false }
        if let now = median(recent.compactMap(\.restingHeartRate)), let then = median(before.compactMap(\.restingHeartRate)),
           then - now >= improvingDrop {
            return true
        }
        if let now = median(recent.compactMap(\.hrv)), let then = median(before.compactMap(\.hrv)), then > 0,
           (now - then) / then >= 0.1 {
            return true
        }
        return false
    }

    // MARK: Changed nights

    static func changed(_ insight: Insight, subjectID: UUID, calendar: Calendar) -> RookStatement {
        if needsClarification(insight) {
            let interpretation = "Diese Veränderung würde ich abklären lassen. Dein Puls bleibt seit Tagen nachts deutlich "
                + "höher als sonst, das ist mehr als ein schlechter Tag. Ich habe dir den Verlauf und die entscheidenden "
                + "Beobachtungen zusammengestellt."
            return make(insight, subjectID: subjectID, headline: "Abklären lassen", interpretation: interpretation,
                        direction: .clarify,
                        action: CoachAction(kind: .seeDoctor, title: "Verlauf ansehen", payload: "timeline=recent"),
                        priority: 5, calendar: calendar)
        }
        let several = insight.headline.hasPrefix("Seit")
        let interpretation = several
            ? "Die letzten Tage ziehen mehr an dir als sonst. Heute würde ich die harte Einheit streichen und den Abend "
                + "ruhig halten. Morgen schauen wir, ob die Richtung wieder stimmt."
            : "Die letzte Nacht hat mehr an dir gezogen als sonst. Heute lieber locker statt hart, und abends früh runterfahren. "
                + "Morgen schauen wir, ob sich das wieder einpendelt."
        return make(insight, subjectID: subjectID, headline: "Heute Tempo raus", interpretation: interpretation,
                    direction: .strained,
                    action: CoachAction(kind: .moveNow, title: "20 Minuten locker",
                                        payload: RookWorkoutRequest(minutes: 20, intensity: "easy").payload),
                    priority: 3, calendar: calendar)
    }

    /// Resting pulse at least `clarifyRise` above the usual median on `clarifyNights` of the last four nights.
    static func needsClarification(_ insight: Insight) -> Bool {
        guard let band = insight.evidence.first(where: { $0.title == "Ruhepuls" })?.baseline else { return false }
        let recent = insight.nights.sorted { $0.date < $1.date }.suffix(4)
        let high = recent.filter { night in
            guard let value = night.restingHeartRate else { return false }
            return value - band.median >= clarifyRise || value > 100
        }
        return high.count >= clarifyNights
    }

    // MARK: Assembly

    static func make(_ insight: Insight, subjectID: UUID, headline: String, interpretation: String,
                     direction: CoachDirection, action: CoachAction, priority: Int, calendar: Calendar) -> RookStatement {
        let today = calendar.startOfDay(for: insight.createdAt)
        let night = DateInterval(start: today.addingTimeInterval(-6 * 3_600), duration: 17 * 3_600)
        let recentStart = calendar.date(byAdding: .day, value: -4, to: today) ?? today
        let recent = DateInterval(start: recentStart, end: max(insight.createdAt, recentStart.addingTimeInterval(1)))
        let evidence = insight.evidence.map { evidenceRef($0, night: night, recent: recent) }
        // The first sentence is about last night or the last days; the cursor goes there while it is spoken.
        let primary = evidence.first
        let anchor = direction == .improving || direction == .stable ? (primary?.window ?? night) : recent
        let cueTrack = primary?.kind.flatMap { Self.track(for: $0) } ?? .heartRate
        let coach = CoachInsight(
            subjectID: subjectID, createdAt: insight.createdAt, observation: insight.observation,
            interpretation: interpretation, direction: direction, evidence: evidence, action: action,
            priority: priority, valid: dayInterval(insight.createdAt, calendar: calendar),
            recheckAt: insight.recheck.at, narration: cues(interpretation, anchor: anchor, track: cueTrack))
        return RookStatement(insight: coach, headline: headline, why: why(for: insight), source: .local)
    }

    static func evidenceRef(_ item: InsightEvidence, night: DateInterval, recent: DateInterval) -> EvidenceRef {
        let kind: SampleKind? = switch item.title {
        case "Ruhepuls": .restingHeartRate
        case "HRV": item.method.contains("SDNN") ? .heartRateVariability : .ringHRV
        case "Schlaf": .sleepDuration
        default: nil
        }
        let shown = item.value.map { value in item.unit.isEmpty ? number(value) : "\(number(value)) \(item.unit)" }
        let comparison = item.baseline.map { band in
            "üblich \(number(band.p25))–\(number(band.p75)) \(item.unit), aus \(band.nights) Nächten"
        }
        return EvidenceRef(kind: kind, window: kind == nil ? recent : night,
                           label: kind == nil ? item.title : "\(item.title) letzte Nacht", shownValue: shown,
                           comparison: comparison)
    }

    static func track(for kind: SampleKind) -> TimelineTrack? {
        TimelineTrack.allCases.first { $0.sampleKinds.contains(kind) }
            ?? (kind == .restingHeartRate ? .heartRate : kind == .sleepDuration ? .sleepPhases : nil)
    }

    static func why(for insight: Insight) -> RookWhy {
        let nights = insight.evidence.compactMap(\.baseline).map(\.nights).max() ?? 0
        let events = insight.questions.compactMap { question -> String? in
            insight.answers[question.id].map { "Deine Antwort auf „\(question.text)“: \($0)" }
        }
        let alternatives = insight.hypotheses.map { hypothesis in
            RookAlternative(title: hypothesis.title, fit: hypothesis.fit == .open ? .partial : hypothesis.fit,
                            note: hypothesis.explanation)
        }
        var uncertainty: [String] = []
        if nights < 20 { uncertainty.append("Der Vergleich stützt sich auf \(nights) Nächte, er wird mit jeder Nacht genauer.") }
        if insight.evidence.contains(where: { $0.title == "HRV" && !$0.method.contains("SDNN") }) {
            uncertainty.append("Die HRV des Rings ist ein eigenes Verfahren und nicht mit Apple-Werten vergleichbar.")
        }
        uncertainty.append("Eine einzelne Nacht kann durch Sitz des Rings oder Bewegung verrauscht sein; mehrere Nächte in "
                           + "dieselbe Richtung sind belastbarer.")
        return RookWhy(
            comparison: "Deine \(InsightEngine.windowNights) Nächte vor heute (\(nights) mit Werten).",
            events: events,
            calculation: "Ruhepuls ist der niedrigste Nachtwert. Dein üblicher Bereich ist die mittlere Hälfte deiner Nächte "
                + "vor heute. Deutlich verändert heißt: mehr als eine halbe Bereichsbreite außerhalb, oder Ruhepuls mindestens "
                + "8 Schläge über deinem Mittel, oder HRV mindestens 30 % darunter.",
            alternatives: alternatives,
            uncertainty: uncertainty.joined(separator: " "))
    }

    static func cues(_ text: String, anchor: DateInterval?, track: TimelineTrack?) -> [NarrationCue] {
        RookTextGuard.sentences(text).enumerated().map { index, sentence in
            NarrationCue(text: sentence, anchor: index == 0 ? anchor : nil, track: index == 0 ? track : nil)
        }
    }

    static func dayInterval(_ date: Date, calendar: Calendar) -> DateInterval {
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        return DateInterval(start: start, end: end)
    }

    static func number(_ value: Double) -> String { LocalCheckIn.number(value) }
}
