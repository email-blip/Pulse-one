import Foundation

// Morning briefing (BEGLEITER-KREATIVTEAM.md §2.3, §3). Pure text assembly from already computed parts.
// Rules: trends relative to the personal band, no diagnoses, no therapy, no grades or traffic lights.

/// Everything the composer needs for one morning, computed by the engine.
public struct BriefingParts: Equatable, Sendable {
    public let night: NightSummary
    public let dayType: CompanionDayType
    public let infection: InfectionSignal
    public let forecastOutcome: ForecastOutcome?
    public let bodyPace: BodyPaceResult?
    public let bodyWeather: BodyWeatherReport?
    public let actions: [QuickAction]
    public let topFinding: ResearchFinding?

    public init(night: NightSummary, dayType: CompanionDayType, infection: InfectionSignal,
                forecastOutcome: ForecastOutcome? = nil, bodyPace: BodyPaceResult? = nil,
                bodyWeather: BodyWeatherReport? = nil, actions: [QuickAction], topFinding: ResearchFinding? = nil) {
        self.night = night
        self.dayType = dayType
        self.infection = infection
        self.forecastOutcome = forecastOutcome
        self.bodyPace = bodyPace
        self.bodyWeather = bodyWeather
        self.actions = actions
        self.topFinding = topFinding
    }
}

public enum MorningBriefingComposer {
    /// Upper limit for the spoken script (about 45 seconds of speech).
    public static let maxSpokenWords = 110

    public static let breakfastCheckSentence = "Am Frühstückstisch messe ich noch einmal kurz deinen Puls."
    public static let noDiagnosisSentence = "Das ist keine Diagnose."
    public static let medicalCheckSentence = "Wenn du dich krank fühlst oder Fieber hast, lass es ärztlich abklären."

    public static func compose(day: BriefingParts, preferences: CompanionPreferences, now: Date, calendar: Calendar) -> MorningBriefing {
        let tone = preferences.tone
        let greetingLine = Self.headline(firstName: preferences.firstName)
        var sections: [BriefingSection] = []

        // 1. Greeting
        let greetingText = tone == .motivating ? "\(greetingLine) Schön, dass du wach bist." : greetingLine
        sections.append(BriefingSection(kind: .greeting, title: "Guten Morgen", text: greetingText, statement: .observed))

        // 2. Night (measured)
        let nightLines = Self.nightSentences(day.night, tone: tone)
        sections.append(BriefingSection(kind: .night, title: "Deine Nacht", text: nightLines.joined(separator: " "),
                                        statement: .measured))

        // 3. Forecast check (card only)
        if let outcome = day.forecastOutcome, let sentence = CompanionSafety.sanitize(outcome.sentence), !sentence.isEmpty {
            sections.append(BriefingSection(kind: .forecastCheck, title: "Prognose-Abgleich", text: sentence, statement: .computed))
        }

        // 4. Outlook (computed day type in words)
        let outlook = Self.outlookSentence(day.dayType, tone: tone)
        sections.append(BriefingSection(kind: .outlook, title: "Dein Tag", text: outlook, statement: .computed))

        // 5. Infection pattern line
        let infectionLine = Self.infectionText(day.infection)
        sections.append(BriefingSection(kind: .infection, title: "Muster-Blick", text: infectionLine,
                                        statement: day.infection.level == .clarify ? .medicalCheck : .computed))

        // 6. Weather and clothing
        var weatherSpoken: [String] = []
        if let weather = day.bodyWeather {
            weatherSpoken = [weather.weatherLine, weather.clothing.sentence]
                .compactMap { CompanionSafety.sanitize(trimmed($0)) }
                .filter { !$0.isEmpty }
            let notes = weather.bodyNotes.compactMap { CompanionSafety.sanitize(trimmed($0)) }.filter { !$0.isEmpty }
            let cardParts = weatherSpoken + notes + [weather.attribution]
            if !weatherSpoken.isEmpty {
                sections.append(BriefingSection(kind: .weather, title: "Wetter", text: cardParts.joined(separator: " "),
                                                statement: .observed))
            }
        }

        // 7. Quick actions
        let actionsText = Self.actionsSentence(day.actions)
        if !day.actions.isEmpty {
            sections.append(BriefingSection(kind: .actions, title: "Jetzt tun", text: actionsText, statement: .suggestion))
        }

        // 8. Breakfast check
        let breakfast = tone == .brief ? "Beim Frühstück messe ich kurz deinen Puls." : breakfastCheckSentence
        sections.append(BriefingSection(kind: .breakfastCheck, title: "Frühstücks-Check", text: breakfast, statement: .suggestion))

        // 9. Research finding (card only, not in brief tone)
        if tone != .brief, let finding = day.topFinding, let sentence = CompanionSafety.sanitize(trimmed(finding.sentence)),
           !sentence.isEmpty {
            let text = "\(sentence) Etikett \(finding.label.rawValue): \(finding.label.title)."
            sections.append(BriefingSection(kind: .research, title: "Fund der Woche", text: text, statement: .computed))
        }

        // 10. Body pace (card only, label C, not in brief tone)
        if tone != .brief, let pace = day.bodyPace, let sentence = CompanionSafety.sanitize(trimmed(pace.sentence)),
           !sentence.isEmpty {
            let lead = sentence.hasPrefix("Körper-Tempo") ? sentence : "Körper-Tempo (experimentell): \(sentence)"
            let text = "\(lead) Etikett \(pace.label.rawValue): \(pace.label.title)."
            sections.append(BriefingSection(kind: .bodyPace, title: "Körper-Tempo", text: text, statement: .computed))
        }

        // 11. Coverage
        if let coverage = Self.coverageText(day.night, dayType: day.dayType) {
            sections.append(BriefingSection(kind: .coverage, title: "Datenlage", text: coverage, statement: .observed))
        }

        // Spoken script: greeting, night one-liner, outlook, infection, weather, actions.
        let blocks: [[String]] = [
            [greetingLine],
            Array(nightLines.prefix(1)),
            [outlook],
            [infectionLine],
            weatherSpoken,
            day.actions.isEmpty ? [] : [actionsText]
        ]
        // Drop order when too long: weather, night, outlook, actions, infection, greeting.
        let script = limitWords(blocks, dropOrder: [4, 1, 2, 5, 3, 0], maxWords: maxSpokenWords)

        return MorningBriefing(createdAt: now, dayType: day.dayType, headline: greetingLine, sections: sections,
                               actions: day.actions, spokenScript: script)
    }

    // MARK: - Building blocks

    static func headline(firstName: String) -> String {
        let name = trimmed(firstName)
        return name.isEmpty ? "Guten Morgen." : "Guten Morgen, \(name)."
    }

    static func nightSentences(_ night: NightSummary, tone: CompanionPreferences.Tone) -> [String] {
        var result: [String] = []
        if tone == .brief {
            if let duration = night.sleepDuration {
                var sentence = "Schlaf \(shortDuration(duration))"
                if night.sleepDurationIsEstimated { sentence += " (geschätzt)" }
                if let position = night.sleepPosition { sentence += ", \(position.description)" }
                result.append(sentence + ".")
            } else {
                result.append("Schlafdauer unbekannt.")
            }
            if let resting = night.nightRestingHeartRate {
                var sentence = "Ruhepuls \(rounded(resting))"
                if let position = night.restingHeartRatePosition { sentence += ", \(position.description)" }
                result.append(sentence + ".")
            }
            if let hrv = night.hrv {
                var sentence = "HRV \(rounded(hrv)) ms\(hrvMethodSuffix(night.hrvKind))"
                if let position = night.hrvPosition { sentence += ", \(position.description)" }
                result.append(sentence + ".")
            }
            return result
        }

        if let duration = night.sleepDuration {
            var sentence = "Du hast \(night.sleepDurationIsEstimated ? "geschätzt " : "")\(longDuration(duration)) geschlafen"
            if let position = night.sleepPosition { sentence += ", das liegt \(position.description)" }
            result.append(sentence + ".")
        } else {
            result.append("Zur Schlafdauer liegen für diese Nacht keine Daten vor.")
        }
        if let resting = night.nightRestingHeartRate {
            var sentence = "Dein Ruhepuls in der Nacht lag bei \(rounded(resting)) Schlägen pro Minute"
            if let position = night.restingHeartRatePosition {
                sentence += ", \(position.description)"
            } else {
                sentence += ", dein persönlicher Bereich bildet sich noch"
            }
            result.append(sentence + ".")
        }
        if let hrv = night.hrv {
            var sentence = "Deine Herzratenvariabilität lag bei \(rounded(hrv)) ms\(hrvMethodSuffix(night.hrvKind))"
            if let position = night.hrvPosition { sentence += ", \(position.description)" }
            result.append(sentence + ".")
        }
        if let morning = night.morningHeartRate {
            result.append("Nach dem Aufwachen hat der Ring \(rounded(morning)) Schläge pro Minute gemessen.")
        }
        return result
    }

    static func outlookSentence(_ dayType: CompanionDayType, tone: CompanionPreferences.Tone) -> String {
        switch (dayType, tone) {
        case (.recovered, .brief): "Gut erholt, gute Voraussetzungen für Belastung."
        case (.recovered, .motivating): "Dein Körper wirkt heute gut erholt: gute Voraussetzungen für Belastung, nutze den Schwung."
        case (.recovered, .factual): "Dein Tag: gute Voraussetzungen für Belastung."
        case (.normal, .brief): "Normaler Start, normales Programm."
        case (.normal, .motivating): "Ein ganz gewöhnlicher Tag, gut für dein normales Programm. Leg los."
        case (.normal, .factual): "Ein gewöhnlicher Tag, gut für dein normales Programm."
        case (.shortNight, .brief): "Kurze Nacht, heute ruhigerer Takt."
        case (.shortNight, .motivating): "Kurze Nacht, aber mit Licht, Wasser und einem ruhigeren Takt holst du das Beste aus dem Tag."
        case (.shortNight, .factual): "Heute ist ein Tag für einen ruhigeren Takt: wichtige Dinge eher an den Vormittag."
        case (.unusualPattern, .brief): "Geh es heute langsamer an."
        case (.unusualPattern, .motivating): "Gönn dir heute einen ruhigeren Tag. Geh es heute langsamer an: Training eher locker oder Pause, viel trinken, früh ins Bett."
        case (.unusualPattern, .factual): "Geh es heute langsamer an: Training eher locker oder Pause, viel trinken, früh ins Bett."
        case (.notEnoughData, .brief): "Dein Bereich bildet sich noch."
        case (.notEnoughData, .motivating): "Dein persönlicher Bereich bildet sich noch. Jede Nacht mit dem Ring macht die Vergleiche genauer."
        case (.notEnoughData, .factual): "Dein persönlicher Bereich bildet sich noch, deshalb beschreibe ich heute nur."
        }
    }

    static func infectionText(_ signal: InfectionSignal) -> String {
        let raw = trimmed(signal.sentence)
        var text = raw.isEmpty ? fallbackInfectionSentence(signal.level) : (CompanionSafety.sanitize(raw) ?? fallbackInfectionSentence(signal.level))
        if signal.level >= .pattern && !text.contains("ärztlich") {
            text += " " + medicalCheckSentence
        }
        return text
    }

    static func fallbackInfectionSentence(_ level: InfectionLevel) -> String {
        switch level {
        case .none:
            "Ein Infekt-Muster sehe ich in deinen Nachtwerten heute nicht. \(noDiagnosisSentence)"
        case .watch:
            "Ein Nachtwert liegt außerhalb deines üblichen Bereichs, ich behalte das im Blick. \(noDiagnosisSentence)"
        case .pattern, .clarify:
            "Deine Nachtwerte zeigen seit mehreren Nächten ein ungewohntes Muster. \(noDiagnosisSentence)"
        }
    }

    static func actionsSentence(_ actions: [QuickAction]) -> String {
        let phrases = actions.map { QuickActionCatalog.phrase(for: $0) }
        return "Jetzt: \(joinedList(phrases))."
    }

    static func coverageText(_ night: NightSummary, dayType: CompanionDayType) -> String? {
        var parts: [String] = []
        var titles: [String] = []
        for kind in night.missing where !titles.contains(kind.title) {
            titles.append(kind.title)
        }
        if !titles.isEmpty {
            parts.append("Für diese Nacht fehlen Daten zu: \(titles.joined(separator: ", ")).")
        }
        let bandForming = dayType == .notEnoughData
            || (night.nightRestingHeartRate != nil && night.restingHeartRatePosition == nil)
        if bandForming {
            parts.append("Dein persönlicher Bereich bildet sich noch, Vergleiche gibt es nach etwa sieben Tagen mit Daten.")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    // MARK: - Formatting

    /// "7 Stunden 50", "1 Stunde", "45 Minuten".
    static func longDuration(_ seconds: TimeInterval) -> String {
        let totalMinutes = max(0, Int((seconds / 60).rounded()))
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours == 0 { return "\(minutes) Minuten" }
        let hourWord = hours == 1 ? "Stunde" : "Stunden"
        return minutes == 0 ? "\(hours) \(hourWord)" : "\(hours) \(hourWord) \(minutes)"
    }

    /// "7 h 50 min".
    static func shortDuration(_ seconds: TimeInterval) -> String {
        let totalMinutes = max(0, Int((seconds / 60).rounded()))
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours == 0 { return "\(minutes) min" }
        return minutes == 0 ? "\(hours) h" : "\(hours) h \(minutes) min"
    }

    static func rounded(_ value: Double) -> Int {
        Int(value.rounded())
    }

    static func hrvMethodSuffix(_ kind: SampleKind?) -> String {
        switch kind {
        case .some(.ringHRV): " (Ring-Messung)"
        case .some(.heartRateVariability): " (Apple, SDNN)"
        default: ""
        }
    }

    /// "a", "a und b", "a, b und c".
    static func joinedList(_ items: [String]) -> String {
        guard let last = items.last else { return "" }
        if items.count == 1 { return last }
        return items.dropLast().joined(separator: ", ") + " und " + last
    }

    static func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace }).count
    }

    /// Joins the blocks; while above `maxWords`, removes whole sentences from the end of the block that is
    /// first in `dropOrder` and still has content. A last resort cuts at a word boundary.
    static func limitWords(_ blocks: [[String]], dropOrder: [Int], maxWords: Int) -> String {
        var working = blocks
        func joined() -> String {
            working.flatMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
        }
        var text = joined()
        while wordCount(text) > maxWords {
            guard let index = dropOrder.first(where: { $0 < working.count && !working[$0].isEmpty }) else { break }
            working[index].removeLast()
            text = joined()
        }
        if wordCount(text) > maxWords {
            text = text.split(whereSeparator: { $0.isWhitespace }).prefix(maxWords).joined(separator: " ")
        }
        return text
    }
}
