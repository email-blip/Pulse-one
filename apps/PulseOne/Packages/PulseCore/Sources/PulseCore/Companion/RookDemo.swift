import Foundation

/// The two demonstration cases for the acceptance (Auftrag 04, point 7): a positive development and a clear
/// change with the advice to have it checked. Synthetic, visibly marked: the app shows them only with
/// `-uiTesting YES` and the "Testansicht" banner, never as ring measurements.
public enum RookDemo {
    public enum Case: String, CaseIterable, Sendable {
        case positive = "rookPositive"
        case clarify = "rookClarify"
    }

    public static func statement(_ demo: Case, now: Date, profileID: UUID, calendar: Calendar) -> RookStatement {
        let insight = InsightEngine.build(input(demo, now: now, profileID: profileID, calendar: calendar), calendar: calendar)
        var statement = RookLocal.statement(from: insight, slot: .morning, subjectID: profileID, calendar: calendar)
        statement.source = .demo
        return statement
    }

    /// 28 calm nights, then the case: three better nights, or four nights with a clearly higher resting pulse.
    public static func input(_ demo: Case, now: Date, profileID: UUID, calendar: Calendar) -> InsightInput {
        let today = calendar.startOfDay(for: now)
        func night(_ offset: Int, _ rhr: Double, _ hrv: Double, _ sleep: Double) -> NightPoint {
            NightPoint(date: calendar.date(byAdding: .day, value: -offset, to: today) ?? today,
                       restingHeartRate: rhr, hrv: hrv, sleepHours: sleep)
        }
        let wiggle: [Double] = [0, 1, 0, -1, 0, 1]
        let calmFrom = demo == .positive ? 3 : 4
        let calm = (calmFrom...(calmFrom + 27)).map { offset in
            night(offset, 57 + wiggle[offset % wiggle.count], 41 - wiggle[(offset + 2) % wiggle.count],
                  7.1 + 0.2 * wiggle[(offset + 4) % wiggle.count])
        }
        let recent: [NightPoint] = switch demo {
        case .positive: [night(2, 54, 45, 7.4), night(1, 53, 46, 7.5), night(0, 53, 47, 7.4)]
        case .clarify: [night(3, 67, 31, 6.7), night(2, 68, 30, 6.6), night(1, 69, 29, 6.5), night(0, 70, 28, 6.6)]
        }
        let newest = calendar.date(byAdding: .hour, value: 6, to: today)
        return InsightInput(profileID: profileID, now: now, nights: calm + recent, origin: "Testansicht · synthetische Nächte",
                            hrvMethod: "Ring-HRV", newestSample: newest, lastSync: newest)
    }

    // MARK: Sample answers in ROOK's voice (checked by `RookTextGuard` and the validator tests)

    /// The facts a sample answer cites.
    public static func sampleContext(_ demo: Case) -> HealthAnalysisContext {
        let fact: AnalysisFact = switch demo {
        case .positive:
            AnalysisFact(id: "F1", kind: SampleKind.restingHeartRate.rawValue, title: "Ruhepuls", stat: "night_value", value: 53,
                         unit: "bpm", period: "letzte Nacht", n: 1, coverage: 1,
                         baseline: FactBaseline(median: 58, p25: 57, p75: 59, windowDays: 28, n: 26), source: "ring", quality: "ok")
        case .clarify:
            AnalysisFact(id: "F1", kind: SampleKind.restingHeartRate.rawValue, title: "Ruhepuls", stat: "mean", value: 69,
                         unit: "bpm", period: "letzte 7 Tage", n: 7, coverage: 1,
                         baseline: FactBaseline(median: 57, p25: 56, p75: 58, windowDays: 28, n: 26), source: "ring", quality: "ok")
        }
        let hrv = AnalysisFact(id: "F2", kind: SampleKind.ringHRV.rawValue, title: "HRV (Ring)", stat: "night_value",
                               value: demo == .positive ? 47 : 29, unit: "ms", period: "letzte Nacht", n: 1, coverage: 1,
                               baseline: FactBaseline(median: 41, p25: 39, p75: 43, windowDays: 28, n: 26),
                               source: "ring", quality: "ok")
        return HealthAnalysisContext(
            analysisType: "checkin", generatedAt: "2026-11-23T07:30:00+01:00",
            period: AnalysisPeriod(start: "2026-11-23", end: "2026-11-23", timezone: "Europe/Berlin"),
            comparisonPeriod: AnalysisPeriod(start: "2026-10-26", end: "2026-11-22", timezone: "Europe/Berlin"),
            profile: .empty, consentedCategories: ["heart"], facts: [fact, hrv], correlations: [], events: [], dataGaps: [])
    }

    public static func sampleReply(_ demo: Case) -> String {
        switch demo {
        case .positive:
            """
            {"headline":"Wieder im Rhythmus","interpretation":"Dein Rhythmus wird wieder stabiler. Die letzten Nächte passen \
            besser zusammen, und du kommst nach Belastung schneller zurück. Genau diese Regelmäßigkeit würde ich jetzt halten.",\
            "observation":"Ruhepuls 53 bpm, 5 unter deinem Mittel von 58; HRV 47 ms, über deinem Bereich.",\
            "direction":"improving","action":{"kind":"startWorkout","title":"Meine Einheit starten"},"evidence":["F1","F2"],\
            "alternatives":[{"title":"Ruhigere Woche","fit":"strong","note":"Weniger Belastung lässt den Nachtpuls sinken."}],\
            "uncertainty":"Drei Nächte in dieselbe Richtung, das ist belastbar.","recheckHours":24}
            """
        case .clarify:
            """
            {"headline":"Abklären lassen","interpretation":"Diese Veränderung würde ich abklären lassen. Dein Puls bleibt seit \
            Tagen nachts deutlich höher als sonst. Ich habe dir den Verlauf und die entscheidenden Beobachtungen zusammengestellt.",\
            "observation":"Ruhepuls seit 7 Tagen im Mittel 69 bpm, 12 über deinem Mittel von 57.",\
            "direction":"clarify","action":{"kind":"seeDoctor","title":"Verlauf ansehen"},"evidence":["F1"],\
            "alternatives":[{"title":"Beginnender Infekt","fit":"partial","note":"Ein Infekt hebt den Nachtpuls oft schon vor \
            den ersten Beschwerden."},{"title":"Hohe Belastung","fit":"weak","note":"Dagegen spricht, dass es über eine Woche \
            anhält."}],"uncertainty":"Mehrere Nächte in dieselbe Richtung machen die Veränderung deutlich.","recheckHours":24}
            """
        }
    }
}
