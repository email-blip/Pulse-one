# Begleiter – Bauplan (Produktion)

Stand 2026-11-21. Modul „Begleiter“ (Code: `Companion`): Wecker, Morgenbericht, Tagesimpulse.
Ideen: CREATIVE-LAB-2 (I1, P1/P17, I6+P2, P3, P7, I11, X1). Konzept: `BEGLEITER-KREATIVTEAM.md`.
Integrationsvertrag: `INTEGRATION.md` (Projektdateien). Gemeinsame Typen: `PulseCore/Companion/CompanionModels.swift` (nicht umbenennen, nur ergänzen).

## Regeln für alle Teams
- Kein Mac, kein lokaler Compiler: Code muss beim ersten CI-Lauf kompilieren. Swift 6, strict concurrency, Warnungen = Fehler. Nur dokumentierte APIs. Lieber einfach und sicher als clever.
- Keine Diagnosen, keine Ampelfarben, Trends relativ zum persönlichen Band. Infekt-Satz nie „du bist nicht krank“.
- Ring-HRV (`.ringHRV`) und Apple-SDNN (`.heartRateVariability`) nie mischen: Ring zuerst, sonst Apple.
- `.ringStress` nicht für Entscheidungen.
- Nur eigene Dateien anlegen/ändern (Spalte „Dateien“). Gemeinsame Typen nur über den Lead ändern.

## Teams und Dateien

| Team | Inhalt | Dateien |
|---|---|---|
| T1 Nacht & Signale | `NightAnalyzer`, `WakeDetector`, `InfectionWatch`, `MorningForecaster`, `BodyPace` | `PulseCore/Companion/Night*.swift`, `Wake*.swift`, `Infection*.swift`, `Forecast*.swift`, `BodyPace*.swift`, Tests `CompanionNightTests.swift` |
| T2 Kontext & Tag | `OpenMeteo` (URLs + Parser), `ClothingAdvisor`, `BodyWeather`, `NightResearcher`, `DayRhythmPlanner` | `PulseCore/Companion/Weather*.swift`, `Clothing*.swift`, `Research*.swift`, `DayRhythm*.swift`, Tests `CompanionContextTests.swift` |
| T3 Bericht & KI | `QuickActionCatalog`, `MorningBriefingComposer`, `CompanionSafety`, `CompanionPrompts` (Claude-Umformulierung, Ärzte-Konferenz), `CompanionEngine.run` | `PulseCore/Companion/Briefing*.swift`, `QuickAction*.swift`, `CompanionSafety.swift`, `CompanionPrompts.swift`, `CompanionEngine.swift`, Tests `CompanionBriefingTests.swift` |
| T4 Dienste | AlarmKit + Fallback, Sprache, Wetterabruf, Mitteilungen, Speicher, Weckton | `Sources/Features/Companion/Services/*`, `Sources/Persistence/CompanionRecords.swift`, `Sources/Features/Companion/Resources/*` |
| T5 Oberfläche | Begleiter-Screen, Guten-Morgen-Ablauf, Einstellungen, Konferenz, Forscher, Heute-Karte, Testdaten, UI-Tests | `Sources/Features/Companion/*.swift` (ohne Services), `UITests/CompanionTests.swift` |
| Lead | Vertrag, Einhängepunkte (PulseSchema, TodayTile, TestScenario, Screenshot-/Audit-Liste), Review, CI, PR | — |

## Kern-Schnittstellen (PulseCore, reine Funktionen, keine I/O)

```swift
// T1
public enum NightAnalyzer {
    /// Night = 18:00 previous day … wake (or now). Band from the 28 days before.
    public static func summarize(_ input: CompanionInput) -> NightSummary
}
public enum WakeDetector {
    public static func detect(heartRate: [HealthSample], steps: [HealthSample], sleepEnd: Date?,
                              confirmed: Date?, now: Date) -> WakeEstimate
}
public enum DayTypeClassifier {
    public static func classify(night: NightSummary, infection: InfectionSignal, sleepNeedHours: Double) -> CompanionDayType
}
public enum InfectionWatch {
    public static func assess(_ input: CompanionInput) -> InfectionSignal
}
public enum MorningForecaster {
    /// Evening forecast for tomorrow from the person's own history (needs ≥ 14 nights, else nil).
    public static func forecast(for targetDay: Date, input: CompanionInput) -> MorningForecast?
    public static func evaluate(_ forecast: MorningForecast, night: NightSummary, input: CompanionInput) -> ForecastOutcome
    /// Share of hits over stored outcomes (0…1), nil when empty.
    public static func hitRate(_ outcomes: [ForecastOutcome]) -> Double?
}
public enum BodyPace {
    public static func estimate(_ input: CompanionInput) -> BodyPaceResult?
}

// T2
public enum OpenMeteo {
    public static func forecastURL(latitude: Double, longitude: Double) -> URL
    public static func airQualityURL(latitude: Double, longitude: Double) -> URL
    public static func geocodingURL(name: String) -> URL?
    public static func parseForecast(_ data: Data, placeName: String) throws -> WeatherSnapshot
    public static func parseAirQuality(_ data: Data, into snapshot: WeatherSnapshot) throws -> WeatherSnapshot
    public static func parseGeocoding(_ data: Data) throws -> [GeoPlace]
}
public struct GeoPlace: Codable, Equatable, Sendable, Identifiable { id, name, admin1, country, latitude, longitude }
public enum ClothingAdvisor {
    public static func advise(_ weather: WeatherSnapshot, from: Date, to: Date, calendar: Calendar) -> ClothingAdvice
}
public enum BodyWeather {
    public static func report(_ weather: WeatherSnapshot, now: Date, calendar: Calendar, findings: [ResearchFinding]) -> BodyWeatherReport
}
public enum NightResearcher {
    /// Daily table built from samples (columns documented in the file), Spearman, lag 0/1, BH-FDR 0.1, ≥ 21 days.
    public static func dailyTable(_ samples: [HealthSample], calendar: Calendar) -> [Date: [String: Double]]
    public static func scan(_ table: [Date: [String: Double]], calendar: Calendar, minimumDays: Int = 21) -> [ResearchFinding]
}
public enum DayRhythmPlanner {
    public static func plan(wake: Date, dayType: CompanionDayType, night: NightSummary,
                            weather: BodyWeatherReport?, preferences: CompanionPreferences,
                            now: Date, calendar: Calendar) -> [CompanionNudge]
}

// T3
public enum QuickActionCatalog { public static let all: [QuickAction] }
public enum QuickActionPicker {
    public static func pick(dayType: CompanionDayType, night: NightSummary, weather: WeatherSnapshot?,
                            preferences: CompanionPreferences, now: Date, calendar: Calendar) -> [QuickAction] // exactly 3
}
public enum MorningBriefingComposer {
    public static func compose(day: BriefingParts, preferences: CompanionPreferences, now: Date, calendar: Calendar) -> MorningBriefing
}
public struct BriefingParts { night, dayType, infection, forecastOutcome, bodyPace, bodyWeather, actions, topFinding }
public enum CompanionSafety {
    /// Returns forbidden phrases found (diagnoses, "nicht krank", therapy, guarantees).
    public static func violations(in text: String) -> [String]
}
public enum CompanionPrompts {
    public static func minimalFacts(_ day: CompanionDay) -> String          // the preview the user sees before sending
    public static func briefingRewrite(_ day: CompanionDay, preferences: CompanionPreferences) -> (system: String, user: String)
    public static let conferenceRoles: [ConferenceRole]                       // Herz, Schlaf, Sport, Ernährung
    public static func conferenceRound(role: ConferenceRole, facts: String) -> (system: String, user: String)
    public static func conferenceSynthesis(facts: String, statements: [(ConferenceRole, String)]) -> (system: String, user: String)
}
public struct ConferenceRole: Equatable, Sendable, Identifiable { id, title, focus, symbol }
public enum CompanionEngine {
    public static func run(_ input: CompanionInput) -> CompanionDay
}
```

## App-Schnittstellen (T4 → T5)

```swift
@MainActor @Observable final class CompanionStore      // Environment-frei, wird in CompanionScreen erzeugt
    init(context: ModelContext)
    var settings: CompanionSettings                     // SwiftData-Datensatz (Weckzeit, Wochentage, Ort, Vorlieben)
    var today: CompanionDay?; var latestBriefing: StoredBriefing?
    func refresh(profileID: UUID?, birthYear: Int?, firstName: String) async   // läuft Engine, plant Mitteilungen
    func confirmWake(at: Date)
@MainActor final class AlarmScheduler                 // AlarmKit ab iOS 26, sonst Mitteilung mit Ton
    var isAlarmKitAvailable: Bool; func requestAuthorization() async -> Bool
    func schedule(hour:minute:weekdays:) async throws; func cancelAll() async
@MainActor final class BriefingSpeaker                // AVSpeechSynthesizer de-DE
    func speak(_ text: String); func stop(); var isSpeaking: Bool
actor WeatherService                                   // Open-Meteo, Cache 1 h
    func snapshot(for place: GeoPlace) async throws -> WeatherSnapshot; func search(_ name: String) async throws -> [GeoPlace]
@MainActor enum NudgeScheduler { static func replace(with nudges: [CompanionNudge]) async }  // Präfix "companion."
```

## Ablauf
1. Lead: Vertrag (dieses Dokument + `CompanionModels.swift`) – fertig.
2. T1, T2, T4 parallel. T3 parallel (nutzt Signaturen oben). T5 parallel (nutzt App-Schnittstellen).
3. Lead: Einhängepunkte, gegenseitiges Review, ein CI-Lauf, Fehler beheben, PR, Merge bei Grün.
4. Danach: Andocken an den Claude-Client aus PR #27 (Konferenz, Umformulierung), wenn #27 auf `main` ist.
