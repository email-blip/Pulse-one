import Foundation

/// Outcome of the local safety check for one sentence (clinical context spec §6).
public enum SafetyVerdict: Equatable, Sendable {
    case allow
    /// Shown, but marked (S4 causal wording).
    case flag(rule: String, reason: String)
    /// Never shown.
    case reject(rule: String, reason: String)
}

/// How far Claude may go. The owner decided on 2026-11-21 that his private app interprets like a
/// physician: diagnoses, probabilities and treatment options are allowed (`clinical`). `descriptive` is
/// the earlier trend-only mode, kept as a switch in the settings.
public enum SafetyMode: String, Codable, Sendable, CaseIterable {
    case clinical
    case descriptive
}

/// Local, testable rules S1–S7. In `descriptive` mode PULSE ONE describes trends only (S1–S4 apply).
/// In `clinical` mode diagnoses, disease probabilities and causes are allowed; what stays is the
/// medication note (S3 as a flag), the fixed referral thresholds (S5), the emergency notice (S6) and the
/// removal of empty disclaimers (S7).
public enum SafetyRules {
    static let diseaseTerms = [
        "vorhofflimmern", "herzinsuffizienz", "herzschwäche", "bluthochdruck", "hypertonie", "hypotonie", "diabetes",
        "depression", "schlafapnoe", "apnoe", "arrhythmie", "herzrhythmusstörung", "infektion", "covid", "corona",
        "grippe", "influenza", "burnout", "anämie", "blutarmut", "schilddrüse", "tachykardie", "bradykardie",
        "herzinfarkt", "schlaganfall", "angststörung", "krebs", "tumor", "long covid", "myokarditis", "insomnie",
        "schlafstörung", "übertraining", "erkrankung", "krankheit",
    ]

    /// S1: wording that turns an observation into a diagnosis.
    static let diagnosisMarkers = [
        "du hast ", "sie haben ", "du leidest", "leiden an", "leidest an", "deutet auf", "deuten auf", "spricht für",
        "sprechen für", "hinweis auf", "hinweise auf", "anzeichen für", "anzeichen von", "anzeichen einer",
        "anzeichen eines", "typisch für", "symptom", "diagnose", "diagnostiz", "befund", "bestätigt", "liegt vor",
        "könnte eine", "könnte ein", "vermutlich eine", "wahrscheinlich eine",
    ]

    static let medicationTerms = [
        "medikament", "tablette", "betablocker", "blutdruckmittel", "dosis", "dosierung", "insulin", "antibiotik",
        "ibuprofen", "aspirin", "paracetamol", "präparat", "nahrungsergänzung", "supplement", "magnesium",
        "melatonin", "vitamin", "pille", "arznei", "statin",
    ]

    static let medicationVerbs = [
        "absetzen", "abzusetzen", "erhöhen", "reduzieren", "einnehmen", "nehmen", "weglassen", "verringern",
        "steigern", "dosieren", "ersetzen", "pausieren", "verzichte",
    ]

    static let causalMarkers = [
        "weil", "verursacht", "verursachen", "führt zu", "führte zu", "führen zu", "dadurch", "wegen", "liegt an",
        "lag an", "ursache", "bewirkt", "sorgt für", "sorgte für",
    ]

    /// S7: disclaimers the owner does not want to read (he knows the app is not a physician).
    static let boilerplate = [
        "ich bin kein arzt", "ich bin keine ärztin", "ich bin kein mediziner", "kein ersatz für", "ersetzt keine",
        "ersetzt nicht den", "ersetzt nicht die", "kann keine diagnose", "keine diagnose stellen", "kein medizinprodukt",
        "keine medizinische beratung", "nicht als medizinische", "nur zu informationszwecken",
    ]

    public static func isBoilerplate(_ text: String) -> Bool {
        let lower = text.lowercased()
        return boilerplate.contains { lower.contains($0) }
    }

    /// Drops sentences that are only a disclaimer (S7); everything else stays word for word.
    public static func removingBoilerplate(_ text: String) -> String {
        var kept: [String] = []
        text.enumerateSubstrings(in: text.startIndex..., options: [.bySentences, .substringNotRequired]) { _, range, enclosing, _ in
            let sentence = String(text[enclosing])
            if !isBoilerplate(String(text[range])) { kept.append(sentence) }
        }
        return kept.joined().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Checks one sentence. Rejections come before flags.
    public static func check(_ text: String, mode: SafetyMode = .clinical) -> SafetyVerdict {
        if mode == .clinical { return checkClinical(text) }
        let lower = " " + text.lowercased() + " "
        let mentionsDisease = diseaseTerms.contains { lower.contains($0) }
        if lower.contains("icd") || lower.contains("diagnose:") {
            return .reject(rule: "S1", reason: "Diagnosesprache")
        }
        if mentionsDisease, diagnosisMarkers.contains(where: { lower.contains($0) }) {
            return .reject(rule: "S1", reason: "Diagnosesprache")
        }
        if lower.range(of: #"\d+\s?(%|prozent)[^.]{0,40}(wahrscheinlich|risiko|chance)"#, options: .regularExpression) != nil
            || lower.contains("erhöhtes risiko") || lower.contains("risiko für") || lower.contains("risiko einer")
            || lower.contains("wahrscheinlichkeit für") || lower.contains("wahrscheinlichkeit von")
            || lower.contains("wahrscheinlichkeit einer") {
            return .reject(rule: "S2", reason: "Wahrscheinlichkeit oder Risiko einer Erkrankung")
        }
        if medicationTerms.contains(where: { lower.contains($0) }), medicationVerbs.contains(where: { lower.contains($0) }) {
            return .reject(rule: "S3", reason: "Medikation nur mit Ärztin oder Arzt ändern")
        }
        if causalMarkers.contains(where: { lower.range(of: #"\b"# + $0 + #"\b"#, options: .regularExpression) != nil }) {
            return .flag(rule: "S4", reason: "Ursache behauptet; Daten zeigen nur einen beobachteten Zusammenhang")
        }
        return .allow
    }

    /// Clinical S3 only notes changes to prescribed medication; vitamins or magnesium need no note.
    static let prescriptionTerms = [
        "medikament", "tablette", "betablocker", "blutdruckmittel", "dosis", "dosierung", "insulin", "antibiotik",
        "statin", "arznei", "präparat", "pille", "antidepressiv", "schilddrüsenhormon", "blutverdünn",
    ]

    static let changeVerbs = [
        "absetzen", "abzusetzen", "reduzieren", "erhöhen", "weglassen", "verringern", "umdosieren", "umstellen",
        "pausieren", "ersetzen", "halbieren", "verdoppeln",
    ]

    static func checkClinical(_ text: String) -> SafetyVerdict {
        let lower = " " + text.lowercased() + " "
        if isBoilerplate(text) {
            return .reject(rule: "S7", reason: "Floskel ohne Inhalt")
        }
        if prescriptionTerms.contains(where: { lower.contains($0) }), changeVerbs.contains(where: { lower.contains($0) }) {
            return .flag(rule: "S3", reason: "Verordnete Medikamente nur nach Rücksprache mit deiner Ärztin oder deinem Arzt umstellen.")
        }
        return .allow
    }

    /// S6: acute symptoms. A plain question is answered locally and not sent; in the consultation the
    /// emergency notice is shown first and Claude must open with the urgent advice.
    static let emergencyTerms = [
        "brustschmerz", "schmerzen in der brust", "druck auf der brust", "engegefühl in der brust", "atemnot",
        "bekomme keine luft", "kriege keine luft", "lähmung", "gelähmt", "bewusstlos", "ohnmächtig", "ohnmacht",
        "sprachstörung", "kann nicht sprechen", "herzrasen mit schwindel", "suizid", "umbringen",
    ]

    public static func isEmergency(_ question: String) -> Bool {
        let lower = question.lowercased()
        return emergencyTerms.contains { lower.contains($0) }
    }

    public static let emergencyReply = "Bei akuten Beschwerden wie Brustschmerz, Atemnot, Lähmung oder Bewusstlosigkeit "
        + "bitte sofort den Notruf 112 wählen. In seelischen Krisen hilft die Telefonseelsorge rund um die Uhr unter "
        + "0800 111 0 111. PULSE ONE kann in dieser Lage nicht helfen und schickt nichts an Claude."

    /// Shown above the consultation when the person describes acute symptoms; the message still goes to
    /// Claude, which must open with the urgent advice.
    public static let consultationEmergencyNotice = "Was du beschreibst, kann ein Warnzeichen sein. Bei akutem "
        + "Brustschmerz, Atemnot, Lähmung, Sprachstörung oder Bewusstlosigkeit sofort den Notruf 112 wählen. In seelischen "
        + "Krisen hilft die Telefonseelsorge rund um die Uhr unter 0800 111 0 111."

    /// S5: fixed thresholds that force at least a mention, whatever Claude wrote. Uses period facts with
    /// at least 7 days of data, so a single odd day never triggers it.
    public static func requiredReferral(facts: [AnalysisFact]) -> MedicalReferral? {
        var result: MedicalReferral?
        func escalate(_ level: ReferralLevel, _ reason: String, _ id: String) {
            if let current = result, current.level >= level { return }
            result = MedicalReferral(level: level, reason: reason, evidence: [id])
        }
        for fact in facts {
            switch fact.kind {
            case SampleKind.restingHeartRate.rawValue where fact.n >= 7:
                if fact.value > 100 || fact.value < 40 {
                    escalate(.recommend, "Der Ruhepuls lag über mindestens sieben Tage außerhalb von 40 bis 100 bpm. "
                          + "Das bitte ärztlich abklären lassen, besonders bei Beschwerden. Bei viel Ausdauertraining "
                          + "kann ein niedriger Ruhepuls normal sein.", fact.id)
                } else if let b = fact.baseline, fact.value - b.median > 10 {
                    escalate(.mention, "Der Ruhepuls liegt seit mindestens sieben Tagen deutlich über deinem üblichen Band. "
                          + "Wenn das bleibt oder du dich krank fühlst, ärztlich abklären lassen.", fact.id)
                }
            case SampleKind.sleepDuration.rawValue where fact.n >= 7 && fact.unit == "h" && fact.value < 5:
                escalate(.mention, "Du hast im Mittel weniger als fünf Stunden geschlafen. Wenn das anhält, "
                      + "kann ein ärztliches Gespräch helfen.", fact.id)
            case "spo2_low_readings" where fact.value >= 3:
                escalate(.mention, "Mehrere niedrige SpO₂-Messwerte unter 90 %. Ringmessungen können ungenau sein; "
                      + "wenn sich das wiederholt oder du Beschwerden hast, ärztlich abklären lassen.", fact.id)
            default:
                break
            }
        }
        return result
    }
}
