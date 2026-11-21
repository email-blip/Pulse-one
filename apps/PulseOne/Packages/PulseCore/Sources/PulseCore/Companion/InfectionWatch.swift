import Foundation

// Companion (Begleiter) T1, idea P3: a descriptive "infection-like pattern" check from night values.
// It compares the last nights with the person's own band and never diagnoses. No sentence ever says
// the person is healthy or not ill; every level points out that this is no diagnosis.

public enum InfectionWatch {
    /// Nights looked at, including the last one.
    public static let nightsChecked = 4
    /// Resting heart rate this far above the band's upper edge asks for clarification.
    public static let strongMargin = 10.0
    /// Relative skin temperature deviation (°C) that counts as raised.
    public static let deviationThreshold = 0.5
    /// Absolute skin temperature this far above the band's upper edge (°C) counts as raised.
    public static let skinMargin = 0.3

    public static let notEnoughDataSentence = "Für ein Infekt-Muster brauche ich mindestens 7 Nächte mit Ringdaten."
    static let noDiagnosis = "Das ist keine Diagnose."
    static let patternCauses = "So ein Muster zeigt sich manchmal bei Infekten, Stress, Alkohol oder Schlafmangel."
    static let temperatureNote = "ohne Hauttemperatur (R09) weniger aussagekräftig"

    /// Result of one night against the band of the 28 nights before it.
    struct NightCheck: Sendable {
        let hasBand: Bool
        let restingAbove: Bool
        let restingStrong: Bool
        let hrvBelow: Bool
        let temperatureUp: Bool

        var anySignal: Bool { restingAbove || hrvBelow || temperatureUp }
    }

    public static func assess(_ input: CompanionInput) -> InfectionSignal {
        let calendar = input.calendar
        let today = calendar.startOfDay(for: input.now)
        let pool = NightSamples(input.samples)
        let window = NightAnalyzer.bandWindowNights
        let records = NightMath.records(endingOn: today, count: window + nightsChecked, pool: pool,
                                        dailyResting: NightMath.dailyRestingHeartRates(input.samples, calendar: calendar),
                                        calendar: calendar)
        guard let tonight = records.last else { return notEnoughData(input, usedTemperature: false) }
        let usedTemperature = tonight.skinTemperatureDeviation != nil || tonight.skinTemperature != nil

        // One resting method and one HRV kind for all nights and bands, chosen by the last night.
        let source: RestingSource
        if tonight.nightRestingHeartRate != nil {
            source = .night
        } else if tonight.dailyRestingHeartRate != nil {
            source = .daily
        } else {
            return notEnoughData(input, usedTemperature: usedTemperature)
        }
        var hrvKind: SampleKind?
        if tonight.ringHRV != nil {
            hrvKind = .ringHRV
        } else if tonight.appleHRV != nil {
            hrvKind = .heartRateVariability
        }

        // Newest night first.
        var checks: [NightCheck] = []
        for back in 0..<nightsChecked {
            let index = records.count - 1 - back
            guard index >= window else { break }
            let history = Array(records[(index - window)..<index])
            checks.append(check(records[index], history: history, source: source, hrvKind: hrvKind))
        }
        guard let last = checks.first, last.hasBand else {
            return notEnoughData(input, usedTemperature: usedTemperature)
        }

        var streak = 0
        for night in checks {
            guard night.hasBand && night.restingAbove else { break }
            streak += 1
        }
        let streakNights = checks.prefix(streak)
        let hrvBelowInStreak = streakNights.contains { $0.hrvBelow }
        let temperatureInStreak = streakNights.contains { $0.temperatureUp }
        let isPattern = streak >= 2 && (hrvBelowInStreak || temperatureInStreak)

        var reasons: [String] = []
        if streak == 1 {
            reasons.append("Ruhepuls heute Nacht über deinem üblichen Bereich")
        } else if streak > 1 {
            reasons.append("Ruhepuls \(streak) Nächte über deinem üblichen Bereich")
        }
        if last.restingStrong { reasons.append("Ruhepuls mehr als 10 Schläge über deinem üblichen Bereich") }
        if last.hrvBelow { reasons.append("HRV heute Nacht unter deinem üblichen Bereich") }
        if last.temperatureUp { reasons.append("Hauttemperatur heute Nacht erhöht") }
        if input.feelsSick { reasons.append("Du fühlst dich angeschlagen") }
        if input.alarmSymptoms { reasons.append("Du hast Warnzeichen angegeben") }
        if !usedTemperature { reasons.append(temperatureNote) }

        let lead = patternLead(streak: streak, hrvBelow: hrvBelowInStreak, temperatureUp: temperatureInStreak)
        let clarifyTail = "Wenn du dich krank fühlst oder das anhält, lass es bitte ärztlich abklären. \(noDiagnosis)"

        if input.alarmSymptoms {
            return InfectionSignal(level: .clarify, reasons: reasons, usedTemperature: usedTemperature,
                                   sentence: alarmSentence)
        }
        if isPattern && streak >= 3 {
            return InfectionSignal(level: .clarify, reasons: reasons, usedTemperature: usedTemperature,
                                   sentence: "\(lead). \(patternCauses) Geh es heute ruhiger an. \(clarifyTail)")
        }
        if last.restingStrong {
            let opening = isPattern ? "\(lead)." : "Dein Ruhepuls lag heute Nacht deutlich über deinem üblichen Bereich."
            return InfectionSignal(level: .clarify, reasons: reasons, usedTemperature: usedTemperature,
                                   sentence: "\(opening) Geh es heute ruhiger an. \(clarifyTail)")
        }
        if isPattern {
            return InfectionSignal(level: .pattern, reasons: reasons, usedTemperature: usedTemperature,
                                   sentence: "\(lead). \(patternCauses) Geh es heute ruhiger an. \(noDiagnosis)")
        }
        if last.anySignal {
            if input.feelsSick {
                // Feeling ill plus one signal reads like a pattern, but never more than that.
                return InfectionSignal(level: .pattern, reasons: reasons, usedTemperature: usedTemperature,
                                       sentence: "Du fühlst dich angeschlagen, und ein Wert lag heute Nacht außerhalb deines "
                                           + "üblichen Bereichs. \(patternCauses) Geh es heute ruhiger an. \(noDiagnosis)")
            }
            return InfectionSignal(level: .watch, reasons: reasons, usedTemperature: usedTemperature,
                                   sentence: "Ein Wert lag heute Nacht außerhalb deines üblichen Bereichs. Ich behalte das im Blick.")
        }
        var sentence = "Deine Nachtwerte liegen in deinem üblichen Bereich. Ein Infekt-Muster sehe ich heute nicht. \(noDiagnosis)"
        if input.feelsSick { sentence += " Wenn du dich angeschlagen fühlst, geh es trotzdem ruhiger an." }
        return InfectionSignal(level: .none, reasons: reasons, usedTemperature: usedTemperature, sentence: sentence)
    }

    static let alarmSentence = "Du hast Warnzeichen angegeben. Bitte lass das ärztlich abklären; bei akuten Beschwerden "
        + "sofort den Notruf 112 wählen. \(noDiagnosis)"

    static func notEnoughData(_ input: CompanionInput, usedTemperature: Bool) -> InfectionSignal {
        if input.alarmSymptoms {
            return InfectionSignal(level: .clarify, reasons: ["Du hast Warnzeichen angegeben"], usedTemperature: usedTemperature,
                                   sentence: alarmSentence)
        }
        var reasons = ["Noch zu wenige Nächte für deinen üblichen Bereich"]
        if !usedTemperature { reasons.append(temperatureNote) }
        return InfectionSignal(level: .none, reasons: reasons, usedTemperature: usedTemperature, sentence: notEnoughDataSentence)
    }

    /// e.g. "Ruhepuls seit 2 Nächten über deinem üblichen Bereich, HRV darunter".
    static func patternLead(streak: Int, hrvBelow: Bool, temperatureUp: Bool) -> String {
        var parts = ["Ruhepuls seit \(streak) Nächten über deinem üblichen Bereich"]
        if hrvBelow { parts.append("HRV darunter") }
        if temperatureUp { parts.append("Hauttemperatur erhöht") }
        return parts.joined(separator: ", ")
    }

    static func check(_ night: NightRecord, history: [NightRecord], source: RestingSource, hrvKind: SampleKind?) -> NightCheck {
        var hasBand = false
        var restingAbove = false
        var restingStrong = false
        if let resting = night.resting(source), let band = NightBand.make(history.compactMap { $0.resting(source) }) {
            hasBand = true
            restingAbove = resting > band.upper
            restingStrong = resting > band.upper + strongMargin
        }
        var hrvBelow = false
        if let kind = hrvKind, let value = night.hrv(kind), let band = NightBand.make(history.compactMap { $0.hrv(kind) }) {
            hrvBelow = value < band.lower
        }
        var temperatureUp = false
        if let deviation = night.skinTemperatureDeviation {
            temperatureUp = deviation > deviationThreshold
        } else if let skin = night.skinTemperature, let band = NightBand.make(history.compactMap(\.skinTemperature)) {
            temperatureUp = skin > band.upper + skinMargin
        }
        return NightCheck(hasBand: hasBand, restingAbove: restingAbove, restingStrong: restingStrong, hrvBelow: hrvBelow,
                          temperatureUp: temperatureUp)
    }
}
