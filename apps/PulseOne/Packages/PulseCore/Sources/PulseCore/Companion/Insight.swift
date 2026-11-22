import Foundation

// Codex P1-005: one coherent insight instead of isolated tiles.
// Observation (measured) → interpretation with alternatives (derived / hypothesis) → one action
// (recommendation) → a planned recheck. Every insight keeps profile, time, origin and method, coverage,
// baseline, evidence ids, hypotheses with counter-evidence, the action, the recheck and its revisions.
// Corrections change the interpretation, never the measurements. No diagnosis percentages: hypotheses
// carry a qualitative fit only, because no calibrated model exists. Pure rules, no I/O.

/// What kind of statement a line is; shown as a visible badge.
public enum InsightStatementKind: String, Codable, Sendable, CaseIterable {
    case measurement, derived, hypothesis, recommendation

    public var title: String {
        switch self {
        case .measurement: "Messung"
        case .derived: "Abgeleitet"
        case .hypothesis: "Hypothese"
        case .recommendation: "Empfehlung"
        }
    }
}

/// The values of one night (the night that ended on `date`, local start of day). Nil = not measured.
public struct NightPoint: Codable, Equatable, Sendable {
    public var date: Date
    public var restingHeartRate: Double?
    public var hrv: Double?
    public var sleepHours: Double?

    public init(date: Date, restingHeartRate: Double?, hrv: Double?, sleepHours: Double?) {
        self.date = date
        self.restingHeartRate = restingHeartRate
        self.hrv = hrv
        self.sleepHours = sleepHours
    }

    var isEmpty: Bool { restingHeartRate == nil && hrv == nil && sleepHours == nil }
}

/// Everything the engine looks at. Built by the app from stored samples, or synthetic in test views.
public struct InsightInput: Sendable {
    public var profileID: UUID
    public var now: Date
    /// Nights, any order, up to about 35. Missing nights are simply absent.
    public var nights: [NightPoint]
    /// Where the night values come from, e.g. "Ring R03 · Verlauf vom Ring".
    public var origin: String
    /// HRV method label; ring HRV and Apple SDNN are never mixed.
    public var hrvMethod: String
    /// Newest stored sample of any night kind, and the last successful import.
    public var newestSample: Date?
    public var lastSync: Date?
    /// Answers to the insight's questions so far (question id → option).
    public var answers: [String: String]

    public init(profileID: UUID, now: Date, nights: [NightPoint], origin: String, hrvMethod: String,
                newestSample: Date?, lastSync: Date?, answers: [String: String] = [:]) {
        self.profileID = profileID
        self.now = now
        self.nights = nights
        self.origin = origin
        self.hrvMethod = hrvMethod
        self.newestSample = newestSample
        self.lastSync = lastSync
        self.answers = answers
    }
}

public struct BaselineBand: Codable, Equatable, Sendable {
    public let median: Double
    public let p25: Double
    public let p75: Double
    public let nights: Int
    public let windowNights: Int
}

public struct InsightEvidence: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let kind: InsightStatementKind
    public let title: String
    public let text: String
    public let value: Double?
    public let unit: String
    public let baseline: BaselineBand?
    /// Share of nights with data in the baseline window (0–1).
    public let coverage: Double
    public let origin: String
    public let method: String
}

public enum InsightFit: String, Codable, Sendable, Comparable {
    case strong, partial, weak, open

    public var title: String {
        switch self {
        case .strong: "passt gut"
        case .partial: "passt teilweise"
        case .weak: "passt kaum"
        case .open: "offen"
        }
    }

    private var order: Int {
        switch self {
        case .strong: 3
        case .partial: 2
        case .open: 1
        case .weak: 0
        }
    }

    public static func < (lhs: InsightFit, rhs: InsightFit) -> Bool { lhs.order < rhs.order }
}

public struct InsightHypothesis: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let title: String
    /// Short medical or physiological explanation.
    public let explanation: String
    public var supporting: [String]
    public var against: [String]
    public var fit: InsightFit
}

public struct InsightQuestion: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let text: String
    public let options: [String]
    /// Why the answer matters for the interpretation.
    public let why: String
}

public enum InsightActionKind: String, Codable, Sendable {
    case trainAsPlanned, easeOff, sync, observe
}

public struct InsightAction: Codable, Equatable, Sendable {
    public let kind: InsightActionKind
    public let text: String
    public let reason: String
}

public struct InsightRecheck: Codable, Equatable, Sendable {
    public let at: Date
    public let what: String
    public let criterion: String
}

public struct InsightRevision: Codable, Equatable, Sendable {
    public let at: Date
    public let reason: String
    public let previousInterpretation: String
}

public enum InsightCase: String, Codable, Sendable {
    /// Last night is within or better than the usual range.
    case recovered
    /// One or more recent nights changed; cause open.
    case changedNights
    /// Last night is missing or the data are stale: nothing is interpreted as current.
    case dataGap
    /// Not enough nights for a usual range yet.
    case learning
}

public struct Insight: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let profileID: UUID
    public let createdAt: Date
    /// Newest data the insight is based on.
    public let dataThrough: Date?
    public let insightCase: InsightCase
    public let headline: String
    public let observation: String
    public var interpretation: String
    public let evidence: [InsightEvidence]
    public var hypotheses: [InsightHypothesis]
    public let questions: [InsightQuestion]
    public var answers: [String: String]
    public var action: InsightAction
    public let recheck: InsightRecheck
    public var revisions: [InsightRevision]
    /// Night points shown on the shared time axis (real gaps stay gaps).
    public let nights: [NightPoint]
}

/// Result of the planned recheck.
public enum RecheckOutcome: Equatable, Sendable {
    case notYet
    case noData
    case resolved(String)
    case unchanged(String)
}

public enum InsightEngine {
    /// Data older than this do not describe "last night".
    public static let staleAfter: TimeInterval = 18 * 3_600
    public static let windowNights = 28
    public static let minimumNights = 7

    // MARK: Build

    public static func build(_ input: InsightInput, calendar: Calendar) -> Insight {
        let today = calendar.startOfDay(for: input.now)
        let nights = input.nights.sorted { $0.date < $1.date }.filter { $0.date <= today }
        let lastNight = nights.last { calendar.isDate($0.date, inSameDayAs: today) && !$0.isEmpty }
        let stale = input.newestSample.map { input.now.timeIntervalSince($0) > staleAfter } ?? true
        let history = nights.filter { $0.date < today && $0.date >= (calendar.date(byAdding: .day, value: -windowNights, to: today) ?? today) }
        if lastNight == nil || stale {
            return dataGap(input, nights: nights, today: today, calendar: calendar)
        }
        guard let last = lastNight else { return dataGap(input, nights: nights, today: today, calendar: calendar) }
        let rhrBand = band(history.compactMap(\.restingHeartRate))
        let hrvBand = band(history.compactMap(\.hrv))
        let sleepBand = band(history.compactMap(\.sleepHours))
        if rhrBand == nil, hrvBand == nil, sleepBand == nil {
            return learning(input, nights: nights, history: history, calendar: calendar)
        }
        var evidence: [InsightEvidence] = []
        func add(_ title: String, _ value: Double?, _ unit: String, _ band: BaselineBand?, method: String) {
            guard let value else { return }
            let id = "E\(evidence.count + 1)"
            let position = band.map { describe(value, band: $0, unit: unit) } ?? "noch kein üblicher Bereich"
            evidence.append(InsightEvidence(id: id, kind: .measurement, title: title, text: "\(title) \(number(value)) \(unit), \(position)",
                                            value: value, unit: unit, baseline: band,
                                            coverage: Double(band?.nights ?? 0) / Double(windowNights),
                                            origin: input.origin, method: method))
        }
        add("Ruhepuls", last.restingHeartRate, "bpm", rhrBand, method: "niedrigster Nachtwert")
        add("HRV", last.hrv, "ms", hrvBand, method: input.hrvMethod)
        add("Schlaf", last.sleepHours, "h", sleepBand, method: "Schlafdauer der Nacht")

        let changed = changedNights(nights.suffix(4), rhr: rhrBand, hrv: hrvBand, sleep: sleepBand)
        let strongSingle = isStrongSingle(last, rhr: rhrBand, hrv: hrvBand)
        if changed >= 2 || strongSingle {
            return changedNightsInsight(input, nights: nights, evidence: evidence, changed: changed, last: last,
                                        rhr: rhrBand, hrv: hrvBand, sleep: sleepBand, calendar: calendar)
        }
        return recovered(input, nights: nights, evidence: evidence, last: last, rhr: rhrBand, hrv: hrvBand, calendar: calendar)
    }

    // MARK: Cases

    static func recovered(_ input: InsightInput, nights: [NightPoint], evidence: [InsightEvidence], last: NightPoint,
                          rhr: BaselineBand?, hrv: BaselineBand?, calendar: Calendar) -> Insight {
        let better = (last.restingHeartRate.map { value in rhr.map { value <= $0.median } ?? false } ?? false)
            && (last.hrv.map { value in hrv.map { value >= $0.median } ?? true } ?? true)
        let headline = better ? "Gut erholt" : "Im üblichen Bereich"
        let interpretation = better
            ? "Ruhepuls am oder unter deinem Mittel und HRV nicht darunter: Dein Körper hat sich erholt. Eine intensive Einheit passt heute."
            : "Die Nacht liegt in deinem üblichen Bereich. Nichts spricht gegen dein geplantes Training."
        let questions = [InsightQuestion(id: "feeling", text: "Wie fühlst du dich heute?", options: ["Fit", "Normal", "Schlapp"],
                                         why: "Wenn sich dein Befinden und die Werte widersprechen, hat dein Befinden Vorrang.")]
        var insight = Insight(
            id: UUID(), profileID: input.profileID, createdAt: input.now, dataThrough: input.newestSample, insightCase: .recovered,
            headline: headline, observation: evidence.map(\.text).joined(separator: " · "), interpretation: interpretation,
            evidence: evidence,
            hypotheses: [InsightHypothesis(id: "H1", title: "Normale Erholung",
                                           explanation: "Ruhepuls und HRV spiegeln, wie stark das vegetative Nervensystem nachts auf Erholung schaltet.",
                                           supporting: evidence.map(\.id), against: [], fit: .strong)],
            questions: questions, answers: [:],
            action: InsightAction(kind: .trainAsPlanned, text: better ? "Training wie geplant, gern intensiv." : "Training wie geplant.",
                                  reason: "Werte im oder besser als dein üblicher Bereich."),
            recheck: recheckTomorrow(input, calendar: calendar, what: "Ruhepuls nach dem Training",
                                     criterion: rhr.map { "Ruhepuls morgen höchstens \(number($0.p75)) bpm" } ?? "Ruhepuls morgen im üblichen Bereich"),
            revisions: [], nights: nights)
        for (question, answer) in input.answers { insight = revise(insight, question: question, answer: answer, at: input.now) }
        return insight
    }

    static func changedNightsInsight(_ input: InsightInput, nights: [NightPoint], evidence: [InsightEvidence], changed: Int,
                                     last: NightPoint, rhr: BaselineBand?, hrv: BaselineBand?, sleep: BaselineBand?,
                                     calendar: Calendar) -> Insight {
        let rhrUp = last.restingHeartRate.flatMap { value in rhr.map { value > $0.p75 } } ?? false
        let hrvDown = last.hrv.flatMap { value in hrv.map { value < $0.p25 } } ?? false
        let sleepShort = last.sleepHours.flatMap { value in sleep.map { value < $0.p25 } } ?? false
        let nightsText = changed >= 2 ? "Seit \(changed) Nächten verändert" : "Letzte Nacht deutlich verändert"
        var signs: [String] = []
        if rhrUp { signs.append("Ruhepuls erhöht") }
        if hrvDown { signs.append("HRV niedriger") }
        if sleepShort { signs.append("Schlaf kürzer") }
        let interpretation = "\(signs.joined(separator: ", ")). Das Muster zeigt, dass dein Körper nachts mehr arbeitet als sonst. "
            + "Die Ursache ist offen; die Fragen unten grenzen sie ein."
        let hypotheses = [
            InsightHypothesis(id: "H-infection", title: "Beginnender Infekt",
                              explanation: "Bei einer Immunreaktion steigen Ruhepuls und oft die Hauttemperatur, die HRV fällt, häufig 1–2 Tage vor Symptomen.",
                              supporting: rhrUp && hrvDown ? ["Ruhepuls hoch und HRV niedrig zugleich"] : [],
                              against: ["Keine Temperatur gemessen"] + (rhrUp ? [] : ["Ruhepuls nicht erhöht"]),
                              fit: rhrUp && hrvDown ? .partial : .weak),
            InsightHypothesis(id: "H-load", title: "Hohe Trainingsbelastung",
                              explanation: "Nach harten Einheiten braucht das Herz-Kreislauf-System 24–72 Stunden; in der Zeit liegt der Ruhepuls höher.",
                              supporting: [], against: [], fit: .open),
            InsightHypothesis(id: "H-alcohol", title: "Alkohol oder spätes Essen",
                              explanation: "Alkohol und große Mahlzeiten spät am Abend heben den Nachtpuls und senken die HRV für eine Nacht.",
                              supporting: [], against: changed >= 3 ? ["Mehrere Nächte hintereinander, eher kein Einzelabend"] : [], fit: .open),
            InsightHypothesis(id: "H-sleep", title: "Schlafmangel oder Stress",
                              explanation: "Kurzer oder unruhiger Schlaf und Stress halten den Sympathikus aktiv.",
                              supporting: sleepShort ? ["Schlaf unter deinem üblichen Bereich"] : [],
                              against: sleepShort ? [] : ["Schlafdauer im üblichen Bereich"], fit: sleepShort ? .partial : .weak),
        ]
        let questions = [
            InsightQuestion(id: "symptoms", text: "Halskratzen, Gliederschmerzen oder erhöhte Temperatur?", options: ["Ja", "Nein"],
                            why: "Trennt einen Infekt von Belastung."),
            InsightQuestion(id: "training", text: "Hast du in den letzten zwei Tagen hart trainiert?", options: ["Ja", "Nein"],
                            why: "Harte Einheiten erklären bis zu drei veränderte Nächte."),
            InsightQuestion(id: "alcohol", text: "Alkohol oder spät gegessen?", options: ["Ja", "Nein"],
                            why: "Erklärt eine einzelne veränderte Nacht."),
        ]
        var insight = Insight(
            id: UUID(), profileID: input.profileID, createdAt: input.now, dataThrough: input.newestSample, insightCase: .changedNights,
            headline: nightsText, observation: evidence.map(\.text).joined(separator: " · "), interpretation: interpretation,
            evidence: evidence + [InsightEvidence(id: "E\(evidence.count + 1)", kind: .derived, title: "Veränderte Nächte",
                                                  text: "\(changed) der letzten 4 Nächte außerhalb deines üblichen Bereichs",
                                                  value: Double(changed), unit: "Nächte", baseline: nil,
                                                  coverage: Double(min(nights.suffix(4).count, 4)) / 4, origin: input.origin,
                                                  method: "Vergleich mit den 28 Nächten davor")],
            hypotheses: hypotheses, questions: questions, answers: [:],
            action: InsightAction(kind: .easeOff, text: "Heute kein hartes Training: 20 Minuten locker gehen, früh ins Bett.",
                                  reason: "Solange die Ursache offen ist, schont das in jedem der Fälle."),
            recheck: recheckTomorrow(input, calendar: calendar, what: "Ruhepuls und HRV der nächsten Nacht",
                                     criterion: rhr.map { "Ruhepuls zurück auf höchstens \(number($0.p75)) bpm" } ?? "Werte zurück im üblichen Bereich"),
            revisions: [], nights: nights)
        for (question, answer) in input.answers.sorted(by: { $0.key < $1.key }) {
            insight = revise(insight, question: question, answer: answer, at: input.now)
        }
        return insight
    }

    static func dataGap(_ input: InsightInput, nights: [NightPoint], today: Date, calendar: Calendar) -> Insight {
        let newest = input.newestSample.map { "Neueste Werte vom \(dayText($0, calendar: calendar))" } ?? "Noch keine Werte gespeichert"
        let sync = input.lastSync.map { "letzter Abgleich \(dayText($0, calendar: calendar))" } ?? "noch kein Abgleich"
        let evidence = [InsightEvidence(id: "E1", kind: .measurement, title: "Datenstand", text: "\(newest), \(sync)",
                                        value: nil, unit: "", baseline: nil, coverage: 0, origin: input.origin, method: "Abgleich")]
        return Insight(
            id: UUID(), profileID: input.profileID, createdAt: input.now, dataThrough: input.newestSample, insightCase: .dataGap,
            headline: "Letzte Nacht fehlt noch",
            observation: "\(newest), \(sync). Für die letzte Nacht liegen keine Werte vor.",
            interpretation: "Ich deute nichts als aktuelle Nacht, solange die Daten fehlen. Ältere Werte zeige ich nicht als heute.",
            evidence: evidence,
            hypotheses: [
                InsightHypothesis(id: "H-sync", title: "Ring noch nicht abgeglichen",
                                  explanation: "Der Ring speichert die Nacht selbst; sie kommt erst beim nächsten Verbinden aufs iPhone.",
                                  supporting: [], against: [], fit: .open),
                InsightHypothesis(id: "H-worn", title: "Ring nachts nicht getragen oder Akku leer",
                                  explanation: "Ohne Hautkontakt misst der Ring nichts; dann bleibt die Nacht dauerhaft leer.",
                                  supporting: [], against: [], fit: .open),
            ],
            questions: [InsightQuestion(id: "worn", text: "Hast du den Ring heute Nacht getragen?", options: ["Ja", "Nein"],
                                        why: "Getragen: Abgleich holt die Nacht. Nicht getragen: die Lücke bleibt.")],
            answers: [:],
            action: InsightAction(kind: .sync, text: "Ring verbinden und Verlauf abgleichen.", reason: "Erst dann gibt es eine belastbare Aussage zur Nacht."),
            recheck: InsightRecheck(at: input.now.addingTimeInterval(3_600), what: "Ist die letzte Nacht da?",
                                    criterion: "Nachtwerte von heute gespeichert"),
            revisions: [], nights: nights)
            .applying(input.answers, at: input.now)
    }

    static func learning(_ input: InsightInput, nights: [NightPoint], history: [NightPoint], calendar: Calendar) -> Insight {
        let missing = max(minimumNights - history.count, 1)
        return Insight(
            id: UUID(), profileID: input.profileID, createdAt: input.now, dataThrough: input.newestSample, insightCase: .learning,
            headline: "Ich lerne dein Normal", observation: "\(history.count) Nächte mit Werten gespeichert.",
            interpretation: "Noch \(missing) Nächte, dann kenne ich deinen üblichen Bereich und kann Veränderungen einordnen.",
            evidence: [], hypotheses: [], questions: [], answers: [:],
            action: InsightAction(kind: .observe, text: "Ring nachts tragen.", reason: "Jede Nacht macht den Vergleich genauer."),
            recheck: recheckTomorrow(input, calendar: calendar, what: "Neue Nacht", criterion: "Eine Nacht mehr gespeichert"),
            revisions: [], nights: nights)
    }

    // MARK: Answers and corrections

    /// Applies one answer. It changes the fit of hypotheses and the interpretation; measurements stay as they are.
    public static func revise(_ insight: Insight, question: String, answer: String, at date: Date) -> Insight {
        guard insight.answers[question] != answer else { return insight }
        var updated = insight
        updated.answers[question] = answer
        let before = updated.interpretation
        let yes = answer == "Ja"
        func set(_ id: String, _ fit: InsightFit, _ note: String, supporting: Bool) {
            guard let index = updated.hypotheses.firstIndex(where: { $0.id == id }) else { return }
            updated.hypotheses[index].fit = fit
            if supporting { updated.hypotheses[index].supporting.append(note) } else { updated.hypotheses[index].against.append(note) }
        }
        var reason = ""
        switch (question, insight.insightCase) {
        case ("symptoms", .changedNights):
            set("H-infection", yes ? .strong : .weak, yes ? "Du hast Symptome angegeben" : "Keine Symptome", supporting: yes)
            reason = yes ? "Symptome angegeben" : "Keine Symptome"
            if yes {
                updated.action = InsightAction(kind: .easeOff, text: "Heute Pause oder nur Spazieren, viel trinken. Bei Fieber über 39 °C, Atemnot oder Brustschmerz ärztlich abklären.",
                                               reason: "Training mit Infekt belastet das Herz unnötig.")
            }
        case ("training", .changedNights):
            set("H-load", yes ? .strong : .weak, yes ? "Harte Einheit angegeben" : "Kein hartes Training", supporting: yes)
            reason = yes ? "Hartes Training angegeben" : "Kein hartes Training"
        case ("alcohol", .changedNights):
            set("H-alcohol", yes ? .partial : .weak, yes ? "Alkohol oder spätes Essen angegeben" : "Kein Alkohol, nicht spät gegessen", supporting: yes)
            reason = yes ? "Alkohol/spätes Essen angegeben" : "Kein Alkohol"
        case ("feeling", .recovered) where answer == "Schlapp":
            updated.action = InsightAction(kind: .easeOff, text: "Heute locker statt intensiv.",
                                           reason: "Werte unauffällig, aber du fühlst dich schlapp: dein Befinden hat Vorrang.")
            reason = "Befinden widerspricht den Werten"
        case ("worn", .dataGap):
            reason = yes ? "Ring getragen" : "Ring nicht getragen"
            if let index = updated.hypotheses.firstIndex(where: { $0.id == (yes ? "H-sync" : "H-worn") }) {
                updated.hypotheses[index].fit = .strong
            }
            if !yes {
                updated.action = InsightAction(kind: .observe, text: "Heute Nacht tragen; diese Nacht bleibt eine Lücke.",
                                               reason: "Ohne Messung gibt es nichts abzugleichen.")
            }
        default:
            return updated
        }
        updated.interpretation = interpretation(for: updated)
        updated.hypotheses.sort { $0.fit > $1.fit }
        updated.revisions.append(InsightRevision(at: date, reason: reason, previousInterpretation: before))
        return updated
    }

    /// Interpretation text from the current hypothesis fits.
    static func interpretation(for insight: Insight) -> String {
        switch insight.insightCase {
        case .changedNights:
            let strong = insight.hypotheses.filter { $0.fit == .strong }.map(\.title)
            let open = insight.hypotheses.filter { $0.fit == .open || $0.fit == .partial }.map(\.title)
            if let first = strong.first {
                return "Am besten passt: \(first). " + (open.isEmpty ? "" : "Noch möglich: \(open.joined(separator: ", ")).")
            }
            return "Ursache weiter offen. In Frage kommen: \(open.joined(separator: ", "))."
        case .recovered:
            return insight.answers["feeling"] == "Schlapp"
                ? "Die Werte sind unauffällig, du fühlst dich aber schlapp. Werte messen nicht alles; heute zählt dein Befinden."
                : insight.interpretation
        case .dataGap:
            return insight.answers["worn"] == "Nein"
                ? "Ohne getragenen Ring gibt es für diese Nacht keine Werte. Ich lasse die Lücke stehen und schätze nichts."
                : "Die Nacht liegt vermutlich noch auf dem Ring. Nach dem Abgleich deute ich sie."
        case .learning:
            return insight.interpretation
        }
    }

    // MARK: Recheck

    /// Compares the next night with the recheck criterion. Needs the night that ended after the insight.
    public static func evaluateRecheck(_ insight: Insight, nights: [NightPoint], now: Date, calendar: Calendar) -> RecheckOutcome {
        guard now >= insight.recheck.at else { return .notYet }
        let after = nights.filter { $0.date > calendar.startOfDay(for: insight.createdAt) && !$0.isEmpty }.sorted { $0.date < $1.date }
        guard let next = after.first else { return .noData }
        switch insight.insightCase {
        case .dataGap:
            return .resolved("Die Nacht ist jetzt da.")
        case .learning:
            return .resolved("Eine Nacht mehr gespeichert.")
        case .recovered, .changedNights:
            guard let band = insight.evidence.first(where: { $0.title == "Ruhepuls" })?.baseline, let value = next.restingHeartRate else {
                return .noData
            }
            return value <= band.p75
                ? .resolved("Ruhepuls \(number(value)) bpm, wieder im üblichen Bereich.")
                : .unchanged("Ruhepuls \(number(value)) bpm, weiter über deinem üblichen Bereich.")
        }
    }

    // MARK: Helpers

    static func band(_ values: [Double]) -> BaselineBand? {
        guard values.count >= minimumNights else { return nil }
        let sorted = values.sorted()
        return BaselineBand(median: PersonalBaseline.percentile(sorted, 0.5), p25: PersonalBaseline.percentile(sorted, 0.25),
                            p75: PersonalBaseline.percentile(sorted, 0.75), nights: values.count, windowNights: windowNights)
    }

    /// Nights among `recent` with resting pulse above, HRV below or sleep below the usual range, each by more
    /// than half the range's width (at least 3 % of the median), so ordinary scatter does not count.
    static func changedNights(_ recent: ArraySlice<NightPoint>, rhr: BaselineBand?, hrv: BaselineBand?, sleep: BaselineBand?) -> Int {
        recent.filter { night in
            let up = night.restingHeartRate.flatMap { value in rhr.map { value > $0.p75 + margin($0) } } ?? false
            let down = night.hrv.flatMap { value in hrv.map { value < $0.p25 - margin($0) } } ?? false
            let short = night.sleepHours.flatMap { value in sleep.map { value < $0.p25 - margin($0) } } ?? false
            return up || down || short
        }.count
    }

    static func margin(_ band: BaselineBand) -> Double {
        max((band.p75 - band.p25) / 2, abs(band.median) * 0.03)
    }

    /// One value alone can be enough: resting pulse at least 8 bpm or HRV at least 30 % away from the median.
    static func isStrongSingle(_ night: NightPoint, rhr: BaselineBand?, hrv: BaselineBand?) -> Bool {
        let rhrJump = night.restingHeartRate.flatMap { value in rhr.map { value - $0.median >= 8 } } ?? false
        let hrvDrop = night.hrv.flatMap { value in hrv.map { $0.median > 0 && (value - $0.median) / $0.median <= -0.3 } } ?? false
        return rhrJump || hrvDrop
    }

    static func describe(_ value: Double, band: BaselineBand, unit: String) -> String {
        if value > band.p75 { return "über deinem üblichen Bereich (\(number(band.p25))–\(number(band.p75)) \(unit))" }
        if value < band.p25 { return "unter deinem üblichen Bereich (\(number(band.p25))–\(number(band.p75)) \(unit))" }
        return "im üblichen Bereich (\(number(band.p25))–\(number(band.p75)) \(unit))"
    }

    static func recheckTomorrow(_ input: InsightInput, calendar: Calendar, what: String, criterion: String) -> InsightRecheck {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: input.now)) ?? input.now
        let at = calendar.date(bySettingHour: 8, minute: 0, second: 0, of: tomorrow) ?? tomorrow
        return InsightRecheck(at: at, what: what, criterion: criterion)
    }

    static func dayText(_ date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "d. MMMM, HH:mm"
        return formatter.string(from: date)
    }

    static func number(_ value: Double) -> String { LocalCheckIn.number(value) }
}

extension Insight {
    /// Applies stored answers in a fixed order.
    func applying(_ answers: [String: String], at date: Date) -> Insight {
        answers.sorted { $0.key < $1.key }.reduce(self) { InsightEngine.revise($0, question: $1.key, answer: $1.value, at: date) }
    }
}
