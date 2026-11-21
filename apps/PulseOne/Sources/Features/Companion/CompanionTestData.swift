import Foundation
import PulseCore
import SwiftData

/// Test view data for the "companion" scenarios: in-memory store only, never the real one (the screen shows
/// the "Testansicht" banner). Anchored to `TestScenario.fixedTime` like the other scenarios.
/// The last two nights are deliberately ordinary (no unusual pattern).
enum CompanionTestData {
    private static let deviceID = "test-ring"

    @MainActor
    static func insert(into context: ModelContext, now: Date = TestScenario.fixedTime) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let owner = TestScenario.owner

        func add(_ kind: SampleKind, _ value: Double, at start: Date, duration: TimeInterval = 0) {
            guard start <= now else { return }
            let sample = HealthSample(profileID: owner, kind: kind, value: value, unit: kind.canonicalUnit, start: start,
                                      end: start.addingTimeInterval(duration), timeZoneIdentifier: calendar.timeZone.identifier,
                                      source: .colmiRing, deviceID: deviceID,
                                      originalSampleID: "companion-\(kind.rawValue)-\(Int(start.timeIntervalSince1970))",
                                      importedAt: now, quality: .valid, method: .deviceHistory)
            context.insert(StoredSample(sample))
        }

        for offset in 0...34 {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            let hour = { (h: Double) in day.addingTimeInterval(h * 3600) }
            let ordinary = offset < 2
            let wave = sin(Double(offset) * 0.9)
            let nightBase = ordinary ? 55.0 : 55.0 + 2.0 * wave

            // Night heart rate every 10 minutes, 00:00–07:00: U-shaped, lowest around 03:30, rising at waking.
            for step in 0...42 {
                let t = Double(step) / 6.0
                let shape = ((t - 3.5) / 3.5) * ((t - 3.5) / 3.5)
                let jitter = 1.2 * sin(Double(step) * 1.7 + Double(offset))
                let wakeRise = t >= 6.6 ? 6.0 : 0.0
                let bpm: Double = nightBase + 7.0 * shape + jitter + wakeRise
                add(.heartRate, bpm.rounded(), at: hour(t))
            }
            // A few day values.
            let afternoon: Double = 77 + 3 * wave
            let dayValues: [(Double, Double)] = [(9, 68), (12, 74), (15, afternoon), (19, 70)]
            for (h, bpm) in dayValues {
                add(.heartRate, bpm, at: hour(h))
            }
            let hrvWave: Double = 6 * cos(Double(offset) * 0.5)
            let hrv: Double = ordinary ? 46 : 45 + hrvWave
            add(.ringHRV, hrv.rounded(), at: hour(3))
            let spo2: Double = offset % 4 == 0 ? 96 : 97
            add(.oxygenSaturation, spo2, at: hour(3.5))

            let sleepWave: Double = 0.5 * sin(Double(offset) * 0.7)
            let sleepHours: Double = ordinary ? 7.2 : 7.1 + sleepWave
            let sleepStart = hour(-0.85 + Double(offset % 3) / 6.0)
            add(.sleepDuration, sleepHours * 3600, at: sleepStart, duration: sleepHours * 3600)

            let afternoonSteps: Double = 1100 + 400 * wave
            let stepBlocks: [(Double, Double)] = [(7.5, 600), (10, 1300), (12.5, 1500), (15, afternoonSteps),
                                                  (17.5, 1700), (20, 900)]
            for (h, steps) in stepBlocks {
                add(.steps, steps, at: hour(h), duration: 3000)
            }
        }

        let settings = CompanionSettingsRecord()
        settings.alarmEnabled = true
        settings.alarmHour = 6
        settings.alarmMinute = 45
        settings.weekdays = [2, 3, 4, 5, 6]
        settings.placeName = "München"
        settings.latitude = 48.14
        settings.longitude = 11.58
        settings.cachedWeather = sampleWeather(now: now, calendar: calendar)
        settings.updatedAt = now
        context.insert(settings)

        context.insert(sampleConference(now: now))
    }

    /// Activation test view: levels for push, pull and core, and today's morning session finished as planned
    /// ("Passend"). Test view only, never in the real store.
    @MainActor
    static func insertActivation(into context: ModelContext, now: Date = TestScenario.fixedTime) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let morning = calendar.date(bySettingHour: 7, minute: 5, second: 0, of: now) ?? today
        let earlier = calendar.date(byAdding: .day, value: -14, to: today) ?? today
        var profile = ActivationProfile()
        profile.levels[.push] = ActivationLevel(family: .push, exerciseID: "pushup", best: 14, updatedAt: earlier)
        profile.levels[.pull] = ActivationLevel(family: .pull, exerciseID: "table-row", best: 10, updatedAt: earlier)
        profile.levels[.core] = ActivationLevel(family: .core, exerciseID: "plank", best: 45, updatedAt: earlier)

        let settings = ActivationSettingsRecord()
        settings.settings = ActivationSettings()
        settings.profile = profile
        settings.updatedAt = now
        context.insert(settings)

        let input = ActivationInput(slot: .morning, now: morning, calendar: calendar, settings: ActivationSettings(),
                                    profile: profile, coach: CoachPreferences(), dayType: .normal, infectionLevel: .none,
                                    doneToday: [])
        let plan = ActivationPlanner.plan(input)
        let steps = ActivationRun.steps(for: plan)
        var done: [Int: Int] = [:]
        for step in steps { done[step.id] = step.targetValue }
        let finished = morning.addingTimeInterval(Double(max(plan.estimatedSeconds, 60)))
        let result = ActivationResult(plan: plan, results: ActivationRun.results(plan: plan, steps: steps, done: done),
                                      feedback: .right, finishedAt: finished)
        context.insert(ActivationSessionRecord(result: result, day: today,
                                               minutes: ActivationRun.minutes(from: morning, to: finished)))
    }

    /// A finished expert round with the canned replies of the test transport (no usage, so no cost and
    /// nothing counted against the Analyse budget). Test view only.
    static func sampleConference(now: Date) -> StoredConference {
        let statements = CompanionPrompts.conferenceRoles.map { role in
            ConferenceStatement(role: role, text: CompanionConference.sampleStatements[role.id] ?? CompanionConference.emptyNotice,
                                withheld: false)
        }
        return StoredConference(createdAt: now.addingTimeInterval(-2 * 3600), factsText: CompanionConference.sampleFacts,
                                statements: statements, synthesis: CompanionConference.sampleSynthesis,
                                synthesisWithheld: false, costUSD: nil, modelID: ClaudeModel.standard.id)
    }

    /// A plausible autumn day in Munich around `now` (36 hours from midnight), so the screen shows body weather
    /// without network. Test view only.
    static func sampleWeather(now: Date, calendar: Calendar = .current) -> WeatherSnapshot {
        let midnight = calendar.startOfDay(for: now)
        var hours: [WeatherHour] = []
        for h in 0..<36 {
            let hourOfDay = Double(h % 24)
            let angle: Double = (hourOfDay - 7) / 12 * Double.pi
            let daylight: Double = max(0, sin(angle))
            let temperature = 4 + 8 * daylight
            let rain: Double = (15...18).contains(h) ? 60 : 10
            hours.append(WeatherHour(time: midnight.addingTimeInterval(Double(h) * 3600),
                                     temperature: temperature.rounded(),
                                     apparentTemperature: (temperature - 2.5).rounded(),
                                     precipitationProbability: rain,
                                     windSpeed: 14,
                                     uvIndex: 2 * daylight,
                                     relativeHumidity: 78,
                                     surfacePressure: 1013))
        }
        return WeatherSnapshot(placeName: "München", latitude: 48.14, longitude: 11.58,
                               fetchedAt: now.addingTimeInterval(-1800), hours: hours,
                               sunrise: midnight.addingTimeInterval(7.5 * 3600),
                               sunset: midnight.addingTimeInterval(16.5 * 3600))
    }
}
