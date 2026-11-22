import Foundation

// Prompts for the optional Claude features (BEGLEITER-KREATIVTEAM.md §5, §9): briefing rewrite and the
// "Expertenrunde" (four AI roles plus synthesis). Only `minimalFacts` leaves the device, and only after the
// person saw it in the preview and approved sending. No names, places or device ids.

/// One AI voice of the "Expertenrunde". Not a doctor; a viewpoint.
public struct ConferenceRole: Equatable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let focus: String
    /// SF Symbol name.
    public let symbol: String

    public init(id: String, title: String, focus: String, symbol: String) {
        self.id = id
        self.title = title
        self.focus = focus
        self.symbol = symbol
    }
}

public enum CompanionPrompts {
    /// UI name of the conference (not "Ärzte-Konferenz": it must not suggest medical advice).
    public static let conferenceTitle = "Expertenrunde"
    public static let conferenceDisclaimer = "Vier KI-Rollen, keine echten Ärztinnen oder Ärzte. Keine Diagnose, keine Therapie."
    /// Owner decision 2026-11-21 (clinical mode): the roles interpret like specialists, without disclaimers.
    public static let clinicalConferenceIntro = "Vier Fachrollen von Claude werten deine Werte aus: Kardiologie, Schlafmedizin, Sportmedizin und Ernährungsmedizin, mit Wahrscheinlichkeiten und Abklärungsvorschlägen."

    public static func conferenceIntro(_ mode: SafetyMode) -> String {
        mode == .clinical ? clinicalConferenceIntro : conferenceDisclaimer
    }

    /// Specialist view per role id in clinical mode.
    static let clinicalSpecialty: [String: String] = [
        "heart": "Fachärztin oder Facharzt für Kardiologie und Innere Medizin",
        "sleep": "Fachärztin oder Facharzt für Schlafmedizin und Pneumologie",
        "sport": "Fachärztin oder Facharzt für Sportmedizin und Rehabilitation",
        "nutrition": "Fachärztin oder Facharzt für Ernährungsmedizin mit Blick auf Stoffwechsel"
    ]
    /// Heading the synthesis must contain, shown as its own block in the UI.
    public static let disagreementHeading = "Hier sind wir uns nicht einig"
    public static let maxRewriteWords = 110

    public static let conferenceRoles: [ConferenceRole] = [
        ConferenceRole(id: "heart", title: "Herz",
                       focus: "Kardiologische Sicht: Ruhepuls, Nacht- und Wachpuls, Herzratenvariabilität (Messmethode beachten, Ring-HRV ist nicht validiert). Ton: ruhig, präzise, vorsichtig.",
                       symbol: "heart"),
        ConferenceRole(id: "sleep", title: "Schlaf",
                       focus: "Schlafdauer, Regelmäßigkeit, Einschlafzeit, Sauerstoffsättigung in der Nacht (beim Ring nur grob). Ton: erklärend, geduldig.",
                       symbol: "bed.double"),
        ConferenceRole(id: "sport", title: "Sport",
                       focus: "Belastung, Schritte, Erholungssignale, gute Zeitfenster für Bewegung, sportartneutral. Ton: anpackend, nie drängend.",
                       symbol: "figure.run"),
        ConferenceRole(id: "nutrition", title: "Ernährung",
                       focus: "Mahlzeitenzeiten, Koffein, Trinken, Alltag rund ums Essen. Ton: alltagsnah.",
                       symbol: "fork.knife")
    ]

    // MARK: - Facts (the preview "Das wird gesendet")

    /// Compact German fact list for the AI: rounded numbers, band positions, day type, weather line and
    /// quick actions. Contains no first name, no place, no device id and no exact timestamps.
    /// Lines are only included for consent categories that are switched on: heart (pulse, HRV, forecast,
    /// pattern check), sleep, spo2, body (skin temperature) and activity (Körper-Tempo from steps and age).
    /// Weather and quick actions are not health data and always included.
    public static func minimalFacts(_ day: CompanionDay,
                                    consent: Set<ConsentCategory> = Set(ConsentCategory.allCases)) -> String {
        let night = day.night
        let heart = consent.contains(.heart)
        let sleep = consent.contains(.sleep)
        var lines: [String] = []
        lines.append("Tagestyp: \(day.dayType.title)")

        if sleep {
            if let duration = night.sleepDuration {
                var line = "Schlafdauer: \(MorningBriefingComposer.shortDuration(duration))"
                if night.sleepDurationIsEstimated { line += " (geschätzt)" }
                line += ", \(bandText(night.sleepPosition))"
                lines.append(line)
            } else {
                lines.append("Schlafdauer: keine Daten")
            }
        }
        if heart {
            if let resting = night.nightRestingHeartRate {
                lines.append("Nachtruhepuls: \(rounded(resting)) Schläge pro Minute, \(bandText(night.restingHeartRatePosition))")
            }
            if let lowest = night.lowestHeartRate {
                lines.append("Tiefster Nachtpuls: \(rounded(lowest)) Schläge pro Minute")
            }
            if let hrv = night.hrv {
                lines.append("HRV (\(hrvMethod(night.hrvKind))): \(rounded(hrv)) ms, \(bandText(night.hrvPosition))")
            }
        }
        if consent.contains(.spo2), let spo2 = night.spo2Average {
            lines.append("Sauerstoffsättigung Nacht (Mittel): \(rounded(spo2)) %")
        }
        if heart, let morning = night.morningHeartRate {
            lines.append("Puls nach dem Aufwachen: \(rounded(morning)) Schläge pro Minute")
        }
        // The pattern check may rest on skin temperature; without body consent it is left out entirely.
        if heart && (consent.contains(.body) || !day.infection.usedTemperature) {
            lines.append("Muster-Prüfung: Stufe \(day.infection.level.rawValue) von 3"
                         + (day.infection.usedTemperature ? ", mit Hauttemperatur" : ", ohne Hauttemperatur"))
            for reason in day.infection.reasons where !reason.isEmpty {
                lines.append("- \(reason)")
            }
            let infectionSentence = MorningBriefingComposer.infectionText(day.infection)
            lines.append("Muster-Satz: \(infectionSentence)")
        }
        if heart, let outcome = day.forecastOutcome {
            var line = "Prognose für heute: Ruhepuls \(rounded(outcome.forecast.restingHeartRateLow)) bis \(rounded(outcome.forecast.restingHeartRateHigh))"
            if let actual = outcome.actualRestingHeartRate { line += ", gemessen \(rounded(actual))" }
            if let hit = outcome.restingHeartRateHit { line += hit ? ", eingetroffen" : ", nicht eingetroffen" }
            lines.append(line)
        }
        if consent.contains(.activity), let pace = day.bodyPace {
            let delta = pace.paceAge - pace.calendarAge
            let direction = delta == 0 ? "etwa wie das Kalenderalter" : (delta > 0 ? "etwa \(delta) Jahre über dem Kalenderalter" : "etwa \(-delta) Jahre unter dem Kalenderalter")
            lines.append("Körper-Tempo (Annäherung, Etikett \(pace.label.rawValue)): \(direction)")
        }
        if let weather = day.bodyWeather {
            if !weather.weatherLine.isEmpty { lines.append("Wetter: \(weather.weatherLine)") }
            if !weather.clothing.sentence.isEmpty { lines.append("Kleidung: \(weather.clothing.sentence)") }
            for note in weather.bodyNotes where !note.isEmpty {
                lines.append("Wetterhinweis: \(note)")
            }
        }
        if !day.briefing.actions.isEmpty {
            lines.append("Jetzt-Schritte: \(day.briefing.actions.map(\.title).joined(separator: ", "))")
        }
        var missingTitles: [String] = []
        for kind in night.missing where !missingTitles.contains(kind.title) {
            missingTitles.append(kind.title)
        }
        if !missingTitles.isEmpty {
            lines.append("Fehlende Daten: \(missingTitles.joined(separator: ", "))")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Briefing rewrite

    public static func briefingRewrite(_ day: CompanionDay, preferences: CompanionPreferences) -> (system: String, user: String) {
        let system = """
        Du bist ein warmer, ruhiger Morgenbegleiter in einer privaten Gesundheits-App. \
        Formuliere aus den Fakten einen kurzen Morgenbericht auf Deutsch, im Tonfall „\(preferences.tone.title)“, mit „du“, ohne Namen. \
        Behalte alle Fakten und Zahlen, erfinde nichts dazu und lass keine Einordnung relativ zum üblichen Bereich weg. \
        Keine Diagnosen, keine Therapie- oder Medikamentenempfehlungen, keine Ursachenbehauptungen, keine Versprechen. \
        Beschreibe Trends relativ zum üblichen Bereich, ohne Noten oder Ampelbegriffe. \
        Höchstens \(maxRewriteWords) Wörter. \
        Wenn der Satz „\(MorningBriefingComposer.noDiagnosisSentence)“ in den Fakten vorkommt, übernimm ihn wörtlich. \
        Antworte nur mit dem Bericht.
        """
        return (system: system, user: "Fakten:\n\(minimalFacts(day))")
    }

    // MARK: - Expertenrunde

    public static func conferenceRound(role: ConferenceRole, facts: String,
                                       mode: SafetyMode = .clinical) -> (system: String, user: String) {
        if mode == .clinical { return clinicalRound(role: role, facts: facts) }
        let system = """
        Du bist die KI-Rolle „\(role.title)“ in der \(conferenceTitle) einer privaten Gesundheits-App. \
        Du bist keine Ärztin und kein Arzt und sprichst nur aus deinem Blickwinkel. \
        Blickwinkel: \(role.focus) \
        Schreibe auf Deutsch 2 bis 4 kurze Sätze, höchstens 80 Wörter, mit „du“. \
        Beschreibe Beobachtungen relativ zum üblichen Bereich und nenne die Zahl, auf die du dich stützt. \
        Keine Diagnosen, keine Therapie- oder Medikamentenempfehlungen, keine Ursachenbehauptungen, keine Versprechen. \
        Wenn etwas ärztlich abgeklärt werden sollte, sag das neutral. Wenn die Daten nicht reichen, sag das.
        """
        return (system: system, user: "Fakten:\n\(facts)")
    }

    /// Clinical round: the role interprets like a specialist (owner decision 2026-11-21). Kept: warning signs
    /// first with urgency, uncertainty as a percentage, prescribed medication never changed on its own.
    static func clinicalRound(role: ConferenceRole, facts: String) -> (system: String, user: String) {
        let specialty = clinicalSpecialty[role.id] ?? "Fachärztin oder Facharzt"
        let system = """
        Du bist die Rolle „\(role.title)“ in der \(conferenceTitle) einer privaten Gesundheits-App: \
        \(specialty). Die Person nutzt ihre eigene App mit ihren eigenen Daten und weiß, dass du kein behandelnder \
        Arzt bist; sie will eine ehrliche, fachlich fundierte Einschätzung ohne Einschränkungen. \
        Blickwinkel: \(role.focus) \
        Schreibe auf Deutsch 3 bis 6 Sätze, höchstens 130 Wörter, mit „du“: deine Einschätzung, mögliche Ursachen \
        oder Diagnosen jeweils mit Wahrscheinlichkeit in Prozent, was du zur Abklärung untersuchen würdest und eine \
        konkrete Empfehlung. Nenne die Zahlen, auf die du dich stützt, und bedenke die Messgenauigkeit von Ring und Uhr. \
        Warnzeichen zuerst: Bei möglicherweise gefährlichen Werten sag am Anfang klar, wie dringend (Notruf 112, heute \
        ärztlich, in den nächsten Tagen). Verordnete Medikamente nie eigenmächtig absetzen oder umdosieren lassen. \
        Keine Floskeln wie „ich bin kein Arzt“. Wenn die Daten nicht reichen, sag, was fehlt, und interpretiere trotzdem.
        """
        return (system: system, user: "Fakten:\n\(facts)")
    }

    public static func conferenceSynthesis(facts: String, statements: [(ConferenceRole, String)],
                                           mode: SafetyMode = .clinical) -> (system: String, user: String) {
        let system: String
        if mode == .clinical {
            system = """
            Du leitest die \(conferenceTitle) einer privaten Gesundheits-App, ein Team aus Kardiologie, Schlafmedizin, \
            Sportmedizin und Ernährungsmedizin. Führe die Beiträge auf Deutsch zu einer gemeinsamen ärztlichen \
            Einschätzung zusammen. Erfinde keine neuen Messwerte. Keine Floskeln wie „ich bin kein Arzt“. \
            Antworte genau in diesen Abschnitten mit diesen Überschriften: \
            „Einschätzung“ (2 bis 3 Sätze, Warnzeichen und Dringlichkeit zuerst), \
            „Mögliche Ursachen“ (2 bis 4 Punkte, jeweils mit Wahrscheinlichkeit in Prozent und den Zahlen als Beleg), \
            „\(disagreementHeading)“ (benenne Widersprüche zwischen den Rollen offen; wenn es keine gibt, schreibe „Keine Uneinigkeit.“), \
            „Abklärung“ (welche Untersuchungen bei welcher Fachrichtung, wie dringend; wenn keine nötig, sag das), \
            „Vorschläge“ (2 bis 4 konkrete Schritte für Training, Erholung, Schlaf, Ernährung oder Behandlung), \
            „Offene Frage“ (1 Anamnese-Frage an die Person). \
            Verordnete Medikamente nie eigenmächtig absetzen oder umdosieren lassen.
            """
        } else {
            system = """
            Du moderierst die \(conferenceTitle) einer privaten Gesundheits-App: vier KI-Rollen, keine Ärztinnen oder Ärzte. \
            Führe die Beiträge auf Deutsch knapp zusammen. Erfinde keine neuen Fakten. \
            Keine Diagnosen, keine Therapie- oder Medikamentenempfehlungen, keine Ursachenbehauptungen, keine Versprechen. \
            Antworte genau in diesen Abschnitten mit diesen Überschriften: \
            „Beobachtungen“ (3 Punkte, jeweils mit der Zahl als Beleg), \
            „\(disagreementHeading)“ (benenne Widersprüche zwischen den Rollen offen; wenn es keine gibt, schreibe „Keine Uneinigkeit.“), \
            „Vorschläge“ (2 bis 3 alltagsnahe Vorschläge), \
            „Offene Frage“ (1 Frage an die Person). \
            Wenn eine Rolle eine ärztliche Abklärung nennt, übernimm den Hinweis neutral.
            """
        }
        var user = "Fakten:\n\(facts)\n\nBeiträge:"
        for (role, statement) in statements {
            user += "\n\(role.title): \(statement)"
        }
        return (system: system, user: user)
    }

    // MARK: - Helpers

    static func bandText(_ position: BandPosition?) -> String {
        switch position {
        case .some(.below): "unter dem üblichen Bereich"
        case .some(.within): "im üblichen Bereich"
        case .some(.above): "über dem üblichen Bereich"
        case .none: "üblicher Bereich bildet sich noch"
        }
    }

    static func hrvMethod(_ kind: SampleKind?) -> String {
        switch kind {
        case .some(.ringHRV): "Ring-Methode, nicht mit SDNN vergleichbar"
        case .some(.heartRateVariability): "Apple, SDNN"
        default: "Methode unbekannt"
        }
    }

    static func rounded(_ value: Double) -> Int {
        Int(value.rounded())
    }
}
