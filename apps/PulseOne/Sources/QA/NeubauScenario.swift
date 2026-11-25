import Foundation
import PulseCore
import SwiftData

/// Test data for the M1 walkthrough (`-uiTesting YES -scenario neubauM1`) and the scrubbing
/// performance test (`neubauM1Year`). Owner: team 06 (QA). Only reachable in UI tests: the store is
/// in memory, every screen shows the "Testansicht" banner, nothing is ever written to the real store.
///
/// Values are deterministic (no random numbers) and anchored to the newest day whose night is over (today from
/// 07:00, yesterday before), so the dashboard shows a finished "last night" whenever the test runs. Team 01 adds
/// the stored sleep segments of the night (22:40–06:55) from `TimelineScenarios.sleepNight`; its edge cases (gap, unknown
/// phase code, double sync, DST) are covered by `TimelineScenarios` in the PulseCore tests.
enum NeubauScenario {
    /// One day plus the night before, 5-minute heart rate like the R03 history, one visible gap.
    static let walkthrough = "neubauM1"
    /// A full year of 5-minute heart rate (about 105 000 points) for the scrubbing measurement.
    static let year = "neubauM1Year"
    static let all: Set<String> = [walkthrough, year]

    /// Same test device as the sleep segments (`TimelineScenarios.deviceID`), so pulse and sleep share one axis.
    static let ringDevice = TimelineScenarios.deviceID

    @MainActor
    static func insert(_ name: String, into context: ModelContext, now: Date = Date()) {
        guard all.contains(name) else { return }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        // Before 07:00 tonight's sleep is not over yet (22:40–06:55), so the newest scenario day is yesterday and
        // "last night" is always a finished night. Run 45514208613 started the hypnogram at 00:22 and found no sleep track.
        let nightOver = now >= today.addingTimeInterval(7 * 3600)
        let newest = nightOver ? today : (calendar.date(byAdding: .day, value: -1, to: today) ?? today)
        let sleepAnchor = nightOver ? now : (calendar.date(byAdding: .day, value: -1, to: now) ?? now)
        let days = name == year ? 365 : 1
        let writer = Writer(context: context, now: now, timeZone: calendar.timeZone.identifier)
        for offset in 0...days {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: newest) else { continue }
            writer.day(day, index: offset)
            // Save in chunks so the year scenario does not hold 100 000 unsaved objects at once.
            if offset % 30 == 29 { try? context.save() }
        }
        try? context.save()
        // Last night's sleep phases through the real BC 27 parser (team 01): 22:40 to 06:55.
        _ = try? SleepSegmentStore(context: context).ingest(
            TimelineScenarios.sleepNight(startMinute: 22 * 60 + 40, endMinute: 6 * 60 + 55, now: sleepAnchor, calendar: calendar),
            now: now)
    }

    /// Deterministic pseudo-noise in -1…1 for index `i` (no RNG, so screenshots are stable).
    static func noise(_ i: Int, _ salt: Int = 0) -> Double {
        var x = UInt64(truncatingIfNeeded: i &* 2_654_435_761 &+ salt &* 40_503)
        x ^= x >> 13; x &*= 0x5bd1e995; x ^= x >> 15
        return Double(x % 2001) / 1000 - 1
    }

    @MainActor
    private struct Writer {
        let context: ModelContext
        let now: Date
        let timeZone: String

        func day(_ day: Date, index: Int) {
            let wave = sin(Double(index) * 0.45)
            // Night: 22:40 the evening before until 06:55, lower pulse, HRV and SpO₂ readings.
            let sleepStart = day.addingTimeInterval(-80 * 60)            // 22:40 previous evening
            let sleepEnd = day.addingTimeInterval(6 * 3600 + 55 * 60)    // 06:55
            // Ring off the finger (charging) 13:00–14:10 on the newest day: a gap the chart must show.
            let gap = index == 0 ? day.addingTimeInterval(13 * 3600)...day.addingTimeInterval(14 * 3600 + 10 * 60) : nil
            for slot in 0..<288 {
                let t = day.addingTimeInterval(Double(slot) * 300)
                if let gap, gap.contains(t) { continue }
                let asleep = t < sleepEnd
                let hour = Double(slot) / 12
                var bpm = asleep ? 54 + 3 * sin(hour * 1.3) : 66 + 8 * sin((hour - 9) / 3)
                if (17.0..<17.75).contains(hour) { bpm = 112 + 18 * sin((hour - 17) * 4) }   // evening run
                bpm += 2.5 * NeubauScenario.noise(slot, index) + 2 * wave
                add(.heartRate, bpm.rounded(), at: t, method: .deviceHistory)
                if slot % 6 == 0 {
                    if asleep {
                        add(.ringHRV, (48 + 9 * wave + 6 * NeubauScenario.noise(slot, index + 7)).rounded(), at: t,
                            method: .deviceHistory)
                        if slot % 12 == 0 {
                            add(.oxygenSaturation, (97 + NeubauScenario.noise(slot, index + 3)).rounded(), at: t,
                                method: .deviceHistory)
                        }
                    } else {
                        add(.ringStress, (32 + 20 * max(0, sin((hour - 10) / 2)) + 8 * NeubauScenario.noise(slot, index + 5))
                            .rounded(), at: t, method: .deviceHistory)
                    }
                }
                if !asleep, slot % 3 == 0 {
                    let steps = (17.0..<17.75).contains(hour) ? 2100 : max(0, 180 + 160 * NeubauScenario.noise(slot, index + 11))
                    add(.steps, steps.rounded(), at: t, duration: 900, method: .deviceHistory)
                }
            }
            add(.restingHeartRate, (55 + 2 * wave).rounded(), at: sleepEnd, method: .deviceHistory)
            add(.sleepDuration, sleepEnd.timeIntervalSince(sleepStart) - 38 * 60, at: sleepStart,
                duration: sleepEnd.timeIntervalSince(sleepStart), method: .deviceHistory)
        }

        func add(_ kind: SampleKind, _ value: Double, at start: Date, duration: TimeInterval = 0, method: MeasurementMethod) {
            guard start <= now else { return }
            let sample = HealthSample(profileID: TestScenario.owner, kind: kind, value: value, unit: kind.canonicalUnit,
                                      start: start, end: start.addingTimeInterval(duration), timeZoneIdentifier: timeZone,
                                      source: .colmiRing, deviceID: NeubauScenario.ringDevice,
                                      originalSampleID: "m1-\(kind.rawValue)-\(Int(start.timeIntervalSince1970))",
                                      importedAt: now, quality: .valid, method: method)
            context.insert(StoredSample(sample))
        }
    }
}
