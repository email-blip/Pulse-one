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
                add(.heartRate, (nightBase + 7.0 * shape + jitter + wakeRise).rounded(), at: hour(t))
            }
            // A few day values.
            for (h, bpm) in [(9.0, 68.0), (12.0, 74.0), (15.0, 77.0 + 3 * wave), (19.0, 70.0)] {
                add(.heartRate, bpm, at: hour(h))
            }
            add(.ringHRV, (ordinary ? 46.0 : 45.0 + 6.0 * cos(Double(offset) * 0.5)).rounded(), at: hour(3))
            add(.oxygenSaturation, offset % 4 == 0 ? 96 : 97, at: hour(3.5))

            let sleepHours = ordinary ? 7.2 : 7.1 + 0.5 * sin(Double(offset) * 0.7)
            let sleepStart = hour(-0.85 + Double(offset % 3) / 6.0)
            add(.sleepDuration, sleepHours * 3600, at: sleepStart, duration: sleepHours * 3600)

            for (h, steps) in [(7.5, 600.0), (10.0, 1300.0), (12.5, 1500.0), (15.0, 1100.0 + 400 * wave),
                               (17.5, 1700.0), (20.0, 900.0)] {
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
    }

    /// A plausible autumn day in Munich around `now` (36 hours from midnight), so the screen shows body weather
    /// without network. Test view only.
    static func sampleWeather(now: Date, calendar: Calendar = .current) -> WeatherSnapshot {
        let midnight = calendar.startOfDay(for: now)
        var hours: [WeatherHour] = []
        for h in 0..<36 {
            let hourOfDay = Double(h % 24)
            let daylight = max(0, sin((hourOfDay - 7) / 12 * Double.pi))
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
