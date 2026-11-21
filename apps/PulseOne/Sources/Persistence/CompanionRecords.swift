import Foundation
import PulseCore
import SwiftData

/// Companion ("Begleiter") data on disk. Core values are stored as JSON so the engine types stay plain Swift;
/// every field is optional or has a default for lightweight migration. Stays on the device.

/// JSON helpers shared by the companion records (ISO dates are not needed: records are only read by this app).
enum CompanionJSON {
    static func encode<T: Encodable>(_ value: T) -> Data? {
        try? JSONEncoder().encode(value)
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data?) -> T? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}

/// The one settings row: alarm, place for the weather, preferences, scheduled alarm ids.
@Model
final class CompanionSettingsRecord {
    var alarmEnabled: Bool = false
    var alarmHour: Int = 7
    var alarmMinute: Int = 0
    /// Calendar weekdays (1 = Sunday … 7 = Saturday). Empty = once, at the next matching time.
    var weekdaysRaw: [Int] = [2, 3, 4, 5, 6]
    var placeName: String = ""
    var latitude: Double?
    var longitude: Double?
    /// `CompanionPreferences` as JSON.
    var preferencesJSON: Data?
    /// AlarmKit UUID strings (iOS 26+) or notification ids "companion.alarm.<weekday>" (fallback).
    var alarmIDs: [String] = []
    /// Last weather snapshot (`WeatherSnapshot` JSON); UI-test data may store one here.
    var weatherJSON: Data?
    /// Day the night researcher last scanned (at most once per day).
    var lastResearchScan: Date?
    var updatedAt: Date = Date.distantPast

    init() {}

    var preferences: CompanionPreferences {
        get { CompanionJSON.decode(CompanionPreferences.self, from: preferencesJSON) ?? CompanionPreferences() }
        set { preferencesJSON = CompanionJSON.encode(newValue) }
    }

    var weekdays: [Int] {
        get { weekdaysRaw.filter { (1...7).contains($0) }.sorted() }
        set { weekdaysRaw = Array(Set(newValue.filter { (1...7).contains($0) })).sorted() }
    }

    var cachedWeather: WeatherSnapshot? {
        get { CompanionJSON.decode(WeatherSnapshot.self, from: weatherJSON) }
        set { weatherJSON = newValue.flatMap { CompanionJSON.encode($0) } }
    }

    /// True when a place with coordinates is set.
    var hasPlace: Bool { !placeName.isEmpty && latitude != nil && longitude != nil }
}

/// A morning briefing that was shown after a confirmed wake-up.
@Model
final class StoredBriefing {
    var createdAt: Date = Date.distantPast
    var dayTypeRaw: String = CompanionDayType.notEnoughData.rawValue
    var headline: String = ""
    var briefingJSON: Data = Data()
    var spokenScript: String = ""
    var wakeTime: Date?
    var wakeMethodRaw: String = WakeMethod.unknown.rawValue

    init(_ briefing: MorningBriefing, wake: WakeEstimate) {
        createdAt = briefing.createdAt
        dayTypeRaw = briefing.dayType.rawValue
        headline = briefing.headline
        briefingJSON = CompanionJSON.encode(briefing) ?? Data()
        spokenScript = briefing.spokenScript
        wakeTime = wake.time
        wakeMethodRaw = wake.method.rawValue
    }

    var briefing: MorningBriefing? { CompanionJSON.decode(MorningBriefing.self, from: briefingJSON) }
    var dayType: CompanionDayType { CompanionDayType(rawValue: dayTypeRaw) ?? .notEnoughData }
    var wakeMethod: WakeMethod { WakeMethod(rawValue: wakeMethodRaw) ?? .unknown }

    func update(_ briefing: MorningBriefing, wake: WakeEstimate) {
        createdAt = briefing.createdAt
        dayTypeRaw = briefing.dayType.rawValue
        headline = briefing.headline
        briefingJSON = CompanionJSON.encode(briefing) ?? briefingJSON
        spokenScript = briefing.spokenScript
        wakeTime = wake.time
        wakeMethodRaw = wake.method.rawValue
    }
}

/// An evening forecast for one day and, once evaluated, how it turned out.
@Model
final class StoredForecast {
    var targetDay: Date = Date.distantPast
    /// `MorningForecast` as JSON.
    var json: Data = Data()
    var actualRestingHeartRate: Double?
    var actualHRVTendency: Int?
    /// Resting heart rate inside the forecast range (nil = not evaluated yet).
    var hit: Bool?
    var hrvHit: Bool?
    var outcomeSentence: String?

    init(_ forecast: MorningForecast) {
        targetDay = forecast.targetDay
        json = CompanionJSON.encode(forecast) ?? Data()
    }

    var forecast: MorningForecast? { CompanionJSON.decode(MorningForecast.self, from: json) }

    func replace(with forecast: MorningForecast) {
        targetDay = forecast.targetDay
        json = CompanionJSON.encode(forecast) ?? json
    }

    func record(_ outcome: ForecastOutcome) {
        actualRestingHeartRate = outcome.actualRestingHeartRate
        actualHRVTendency = outcome.actualHRVTendency
        hit = outcome.restingHeartRateHit
        hrvHit = outcome.hrvHit
        outcomeSentence = outcome.sentence
    }

    /// The stored outcome, nil while not evaluated.
    var outcome: ForecastOutcome? {
        guard hit != nil || hrvHit != nil, let forecast else { return nil }
        return ForecastOutcome(forecast: forecast, actualRestingHeartRate: actualRestingHeartRate,
                               actualHRVTendency: actualHRVTendency, restingHeartRateHit: hit, hrvHit: hrvHit,
                               sentence: outcomeSentence ?? "")
    }
}

/// One finding of the local night researcher.
@Model
final class StoredFinding {
    var createdAt: Date = Date.distantPast
    /// `ResearchFinding` as JSON.
    var json: Data = Data()

    init(_ finding: ResearchFinding, createdAt: Date) {
        self.createdAt = createdAt
        json = CompanionJSON.encode(finding) ?? Data()
    }

    var finding: ResearchFinding? { CompanionJSON.decode(ResearchFinding.self, from: json) }
}

enum CompanionPersistence {
    static let models: [any PersistentModel.Type] = [CompanionSettingsRecord.self, StoredBriefing.self,
                                                     StoredForecast.self, StoredFinding.self]
}
