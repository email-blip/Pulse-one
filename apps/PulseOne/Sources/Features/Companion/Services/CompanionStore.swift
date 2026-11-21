import Foundation
import Observation
import PulseCore
import SwiftData

/// State of the companion ("Begleiter"): gathers inputs (samples, weather, forecast, findings), runs
/// `CompanionEngine`, persists results and schedules alarm and nudges. The engine decides; this type only
/// does I/O. In UI tests it never touches the network, notifications or alarms.
@MainActor
@Observable
final class CompanionStore {
    /// Kinds the engine reads (35 days). `.ringStress` is deliberately absent: never used for decisions.
    static let sampleKinds: Set<SampleKind> = [
        .heartRate, .restingHeartRate, .ringHRV, .heartRateVariability, .oxygenSaturation, .steps,
        .sleepDuration, .skinTemperature, .skinTemperatureDeviation, .activeEnergy, .trainingDuration
    ]
    static let historyDays = 35

    private(set) var settings: CompanionSettingsRecord
    private(set) var today: CompanionDay?
    /// Newest briefing saved after a confirmed wake-up (also from earlier days).
    private(set) var latestBriefing: MorningBriefing?
    private(set) var weather: WeatherSnapshot?
    private(set) var findings: [ResearchFinding] = []
    /// Share of evaluated forecasts whose resting heart rate fell in the range (0…1), nil without outcomes.
    private(set) var forecastHitRate: Double?
    private(set) var isRefreshing = false
    /// Calm German message for the UI, nil when the last action worked.
    var lastError: String?

    private let context: ModelContext
    private let weatherService: WeatherService
    private let alarms: AlarmScheduler
    private let isUITesting: Bool
    @ObservationIgnored private var confirmedWakeToday: Date?
    @ObservationIgnored private var lastRefreshArguments: (profileID: UUID?, birthYear: Int?, firstName: String)?
    @ObservationIgnored private var calendar: Calendar = .current

    init(context: ModelContext) {
        self.context = context
        weatherService = WeatherService()
        alarms = AlarmScheduler()
        isUITesting = LaunchOptions.current.isUITesting
        let existing = (try? context.fetch(FetchDescriptor<CompanionSettingsRecord>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])))?.first
        if let existing {
            settings = existing
        } else {
            let record = CompanionSettingsRecord()
            context.insert(record)
            try? context.save()
            settings = record
        }
        weather = settings.cachedWeather
        latestBriefing = loadLatestBriefing()
        findings = loadFindings()
        forecastHitRate = loadHitRate()
    }

    // MARK: Settings helpers

    var preferences: CompanionPreferences {
        get { settings.preferences }
        set {
            settings.preferences = newValue
            touchAndSave()
        }
    }

    var isAlarmKitAvailable: Bool { alarms.isAlarmKitAvailable }

    /// The stored place as a `GeoPlace` (id 0: not from a search result), nil when none is set.
    var place: GeoPlace? {
        guard settings.hasPlace, let latitude = settings.latitude, let longitude = settings.longitude else { return nil }
        return GeoPlace(id: 0, name: settings.placeName, admin1: nil, country: nil, latitude: latitude, longitude: longitude)
    }

    func setPlace(_ place: GeoPlace) {
        settings.placeName = place.name
        settings.latitude = place.latitude
        settings.longitude = place.longitude
        settings.cachedWeather = nil
        weather = nil
        touchAndSave()
    }

    func clearPlace() {
        settings.placeName = ""
        settings.latitude = nil
        settings.longitude = nil
        settings.cachedWeather = nil
        weather = nil
        touchAndSave()
    }

    /// Place search for the settings screen. Empty in UI tests (no network).
    func searchPlaces(_ name: String) async -> [GeoPlace] {
        guard !isUITesting else { return [] }
        do {
            lastError = nil
            return try await weatherService.search(name)
        } catch {
            lastError = "Die Ortssuche ist gerade nicht erreichbar. Bitte später noch einmal versuchen."
            return []
        }
    }

    // MARK: Alarm

    /// Saves the alarm and (re)schedules it. In UI tests only the settings are stored.
    func saveAlarm(enabled: Bool, hour: Int, minute: Int, weekdays: [Int]) async {
        settings.alarmEnabled = enabled
        settings.alarmHour = min(max(hour, 0), 23)
        settings.alarmMinute = min(max(minute, 0), 59)
        settings.weekdays = weekdays
        touchAndSave()
        guard !isUITesting else { return }

        await alarms.cancelAll(ids: settings.alarmIDs)
        settings.alarmIDs = []
        lastError = nil
        if enabled {
            do {
                settings.alarmIDs = try await alarms.schedule(hour: settings.alarmHour, minute: settings.alarmMinute,
                                                              weekdays: settings.weekdays)
            } catch AlarmScheduler.SchedulingError.notAuthorized {
                settings.alarmEnabled = false
                lastError = "Der Wecker braucht deine Erlaubnis. Du kannst sie in den iPhone-Einstellungen erteilen."
            } catch {
                settings.alarmEnabled = false
                lastError = "Der Wecker konnte gerade nicht gestellt werden. Bitte noch einmal versuchen."
            }
        }
        touchAndSave()
    }

    // MARK: Wake

    /// "Ich bin wach" in the app: notes the moment and runs the companion again with the last arguments.
    func confirmWake(at date: Date) {
        confirmedWakeToday = date
        guard let arguments = lastRefreshArguments else { return }
        Task {
            await refresh(profileID: arguments.profileID, birthYear: arguments.birthYear,
                          firstName: arguments.firstName, confirmedWake: date)
        }
    }

    /// Wake moment from the alarm button, if one is waiting (younger than 2 h). Does not remove it.
    var pendingAlarmWake: Date? { isUITesting ? nil : PendingWake.peek() }

    // MARK: Refresh

    func refresh(profileID: UUID?, birthYear: Int?, firstName: String,
                 confirmedWake: Date? = nil, morningHeartRate: Double? = nil) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        lastRefreshArguments = (profileID, birthYear, firstName)
        lastError = nil

        let now = LaunchOptions.current.usesTestScenario ? TestScenario.fixedTime : Date()
        calendar = .current
        let startOfToday = calendar.startOfDay(for: now)

        // Wake: explicit argument, else the alarm button, else an earlier confirmation today.
        if let alarmWake = isUITesting ? nil : PendingWake.consume() { confirmedWakeToday = alarmWake }
        if let confirmedWake { confirmedWakeToday = confirmedWake }
        if let known = confirmedWakeToday, !calendar.isDate(known, inSameDayAs: now) { confirmedWakeToday = nil }
        let wake = confirmedWakeToday

        let since = calendar.date(byAdding: .day, value: -Self.historyDays, to: startOfToday) ?? startOfToday
        let samples = SampleReader(context: context).samples(Self.sampleKinds, since: since, profileID: profileID)

        let currentWeather = await loadWeather(now: now)
        weather = currentWeather

        let pendingRecord = forecastRecord(for: startOfToday)
        findings = researchFindings(samples: samples, now: now)

        var preferences = settings.preferences
        if !firstName.isEmpty { preferences.firstName = firstName }

        let input = CompanionInput(now: now, calendar: calendar, samples: samples, preferences: preferences,
                                   birthYear: birthYear, confirmedWake: wake, alarmTime: alarmTime(now: now),
                                   morningHeartRate: morningHeartRate, weather: currentWeather,
                                   pendingForecast: pendingRecord?.forecast, findings: findings)
        let day = CompanionEngine.run(input)
        today = day

        if wake != nil { saveBriefing(day) }
        if let outcome = day.forecastOutcome, let pendingRecord,
           outcome.restingHeartRateHit != nil || outcome.hrvHit != nil {
            pendingRecord.record(outcome)
        }
        if let next = day.nextForecast { store(next) }
        try? context.save()
        forecastHitRate = loadHitRate()

        if !isUITesting {
            await NudgeScheduler.replace(with: day.nudges, now: now, calendar: calendar)
        }
    }

    // MARK: Inputs

    /// Fresh weather for the stored place; on failure the stored snapshot if younger than 3 h, else nil.
    /// UI tests use only the stored snapshot (test data), never the network.
    private func loadWeather(now: Date) async -> WeatherSnapshot? {
        let stored = settings.cachedWeather
        if isUITesting { return stored }
        guard settings.hasPlace, let latitude = settings.latitude, let longitude = settings.longitude else { return nil }
        do {
            let fresh = try await weatherService.snapshot(placeName: settings.placeName, latitude: latitude,
                                                          longitude: longitude, now: now)
            settings.cachedWeather = fresh
            return fresh
        } catch {
            lastError = "Das Wetter ist gerade nicht abrufbar. Der Bericht kommt heute ohne Wetter."
            guard let stored, now.timeIntervalSince(stored.fetchedAt) < 3 * 3600 else { return nil }
            return stored
        }
    }

    /// Today's alarm moment if the alarm is on for today's weekday and the time has passed.
    private func alarmTime(now: Date) -> Date? {
        guard settings.alarmEnabled else { return nil }
        let days = settings.weekdays
        guard days.isEmpty || days.contains(calendar.component(.weekday, from: now)),
              let time = calendar.date(bySettingHour: settings.alarmHour, minute: settings.alarmMinute, second: 0, of: now),
              time <= now else { return nil }
        return time
    }

    /// Stored findings, rescanned at most once per day (local, nothing leaves the device).
    private func researchFindings(samples: [HealthSample], now: Date) -> [ResearchFinding] {
        if let last = settings.lastResearchScan, calendar.isDate(last, inSameDayAs: now) {
            return loadFindings()
        }
        let table = NightResearcher.dailyTable(samples, calendar: calendar)
        let found = NightResearcher.scan(table, calendar: calendar)
        let old = (try? context.fetch(FetchDescriptor<StoredFinding>())) ?? []
        for record in old { context.delete(record) }
        for finding in found { context.insert(StoredFinding(finding, createdAt: now)) }
        settings.lastResearchScan = now
        return found
    }

    // MARK: Persistence

    private func saveBriefing(_ day: CompanionDay) {
        let briefing = day.briefing
        let start = calendar.startOfDay(for: briefing.createdAt)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        let descriptor = FetchDescriptor<StoredBriefing>(predicate: #Predicate { $0.createdAt >= start && $0.createdAt < end })
        if let existing = (try? context.fetch(descriptor))?.first {
            existing.update(briefing, wake: day.night.wake)
        } else {
            context.insert(StoredBriefing(briefing, wake: day.night.wake))
        }
        latestBriefing = briefing
    }

    private func forecastRecord(for day: Date) -> StoredForecast? {
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        let descriptor = FetchDescriptor<StoredForecast>(predicate: #Predicate { $0.targetDay >= start && $0.targetDay < end })
        return (try? context.fetch(descriptor))?.first
    }

    /// Keeps one forecast per target day; an already evaluated one is never overwritten.
    private func store(_ forecast: MorningForecast) {
        if let existing = forecastRecord(for: forecast.targetDay) {
            if existing.outcome == nil { existing.replace(with: forecast) }
        } else {
            context.insert(StoredForecast(forecast))
        }
    }

    private func loadLatestBriefing() -> MorningBriefing? {
        var descriptor = FetchDescriptor<StoredBriefing>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first?.briefing
    }

    private func loadFindings() -> [ResearchFinding] {
        let rows = (try? context.fetch(FetchDescriptor<StoredFinding>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []
        return rows.compactMap(\.finding)
    }

    private func loadHitRate() -> Double? {
        let rows = (try? context.fetch(FetchDescriptor<StoredForecast>())) ?? []
        return MorningForecaster.hitRate(rows.compactMap(\.outcome))
    }

    private func touchAndSave() {
        settings.updatedAt = Date()
        try? context.save()
    }
}
