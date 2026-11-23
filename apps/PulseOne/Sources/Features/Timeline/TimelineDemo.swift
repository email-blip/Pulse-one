import Foundation
import PulseCore
import SwiftData

/// Clock of the dashboard and the Verlauf. Test scenarios use a fixed time (stable screenshots); the
/// rebuild walkthrough (`neubauM1…`, team 06) anchors its data to the real day, so it uses the real time.
enum TimelineClock {
    static var now: Date {
        let options = LaunchOptions.current
        guard options.usesTestScenario, let scenario = options.scenario else { return .now }
        return TimelineDemo.liveClockScenarios.contains(scenario) ? .now : TestScenario.fixedTime
    }
}

/// Test view data for the dashboard and the Verlauf (`-uiTesting YES -uiTestScenario dashboard|timeline`).
/// Never reachable in normal use, always under the "Testansicht" banner, written only to the in-memory
/// store of the UI test. Same shape as the R03 history: pulse every 5 minutes, HRV/SpO₂ at night,
/// stress by day, steps per 15 minutes, nights with all phases plus one unknown code, and one visible gap.
enum TimelineDemo {
    /// Scenarios of this team that insert their own data.
    static let scenarios: Set<String> = ["dashboard", "dashboardEdit", "timeline", "timelineHypnogram", "timelineYear"]
    /// Team 06's walkthrough scenarios: they bring their own samples and run on the real clock.
    static let liveClockScenarios: Set<String> = ["neubauM1", "neubauM1Year"]

    static var isActive: Bool {
        let options = LaunchOptions.current
        guard options.usesTestScenario, let scenario = options.scenario else { return false }
        return scenarios.contains(scenario) || liveClockScenarios.contains(scenario)
    }

    /// Inserts samples and sleep segments. `timelineYear` holds a year (5-minute pulse for the last 30 days, hourly before) for scrubbing.
    @MainActor
    static func insert(_ name: String, into context: ModelContext, now: Date = TestScenario.fixedTime) {
        guard scenarios.contains(name) else { return }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let days = name == "timelineYear" ? 365 : 35
        for offset in 0...days {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            // Dense values for the last week, a few points a day before that (enough for month and year).
            insertDay(day, index: offset, dense: offset < (name == "timelineYear" ? 30 : 7), now: now, into: context)
            if offset % 30 == 29 { try? context.save() }
        }
        insertNights(count: 7, now: now, calendar: calendar, into: context)
        try? context.save()
    }

    /// Nights from 22:40 to 06:55 through team 01's ring parser; the newest night carries one unknown code.
    @MainActor
    static func insertNights(count: Int, now: Date, calendar: Calendar, into context: ModelContext) {
        var segments: [SleepSegment] = []
        for back in 0..<count {
            guard let day = calendar.date(byAdding: .day, value: -back, to: now) else { continue }
            segments += TimelineScenarios.sleepNight(startMinute: 22 * 60 + 40, endMinute: 6 * 60 + 55, now: day,
                                                     calendar: calendar, unknownCode: back == 0)
        }
        _ = try? SleepSegmentStore(context: context).ingest(segments, now: now)
    }

    /// Deterministic pseudo-noise in -1…1 (no random numbers, so screenshots stay the same).
    static func noise(_ i: Int, _ salt: Int) -> Double {
        var x = UInt64(truncatingIfNeeded: i &* 2_654_435_761 &+ salt &* 40_503)
        x ^= x >> 13
        x &*= 0x5bd1e995
        x ^= x >> 15
        return Double(x % 2001) / 1000 - 1
    }

    @MainActor
    private static func insertDay(_ day: Date, index: Int, dense: Bool, now: Date, into context: ModelContext) {
        let wave = sin(Double(index) * 0.45)
        let wake = day.addingTimeInterval(6 * 3600 + 55 * 60)
        // The ring was charging for 70 minutes until 83 minutes ago (13:00–14:10 at the fixed test time): a gap
        // the tracks must show, never as zero. Tied to `now` so UI tests find it at the same place in any time zone.
        let gap = index == 0 ? now.addingTimeInterval(-153 * 60)...now.addingTimeInterval(-83 * 60) : nil
        let slots = dense ? 288 : 24
        let step = 86_400 / Double(slots)
        for slot in 0..<slots {
            let t = day.addingTimeInterval(Double(slot) * step)
            if let gap, gap.contains(t) { continue }
            let hour = Double(slot) * step / 3600
            let asleep = t < wake || hour >= 22.67
            var bpm = asleep ? 54 + 3 * sin(hour * 1.3) : 66 + 8 * sin((hour - 9) / 3)
            if (17.0..<17.75).contains(hour) { bpm = 112 + 18 * sin((hour - 17) * 4) }
            bpm += 2.5 * noise(slot, index) + 2 * wave
            add(.heartRate, bpm.rounded(), at: t, now: now, into: context)
            let every = dense ? 6 : 1
            if slot % every == 0 {
                if asleep {
                    add(.ringHRV, (48 + 9 * wave + 6 * noise(slot, index + 7)).rounded(), at: t, now: now, into: context)
                    add(.oxygenSaturation, (97 + noise(slot, index + 3)).rounded(), at: t, now: now, into: context)
                } else {
                    let stress = 32 + 20 * max(0, sin((hour - 10) / 2)) + 8 * noise(slot, index + 5)
                    add(.ringStress, stress.rounded(), at: t, now: now, into: context)
                }
            }
            if !asleep, !dense || slot % 3 == 0 {
                let steps = (17.0..<17.75).contains(hour) ? 2100 : max(0, 180 + 160 * noise(slot, index + 11))
                add(.steps, (dense ? steps : steps * 3).rounded(), at: t, duration: dense ? 900 : 2700, now: now, into: context)
            }
        }
        add(.restingHeartRate, (55 + 2 * wave).rounded(), at: wake, now: now, into: context)
        // The evening run as a finished workout (training track and tile).
        add(.trainingDuration, 45 * 60, at: day.addingTimeInterval(17 * 3600), duration: 45 * 60, now: now, into: context)
    }

    @MainActor
    private static func add(_ kind: SampleKind, _ value: Double, at start: Date, duration: TimeInterval = 0, now: Date,
                            into context: ModelContext) {
        guard start.addingTimeInterval(duration) <= now else { return }
        let sample = HealthSample(profileID: TestScenario.owner, kind: kind, value: value, unit: kind.canonicalUnit, start: start,
                                  end: start.addingTimeInterval(duration), timeZoneIdentifier: TimeZone.current.identifier,
                                  source: .colmiRing, deviceID: "test-ring",
                                  originalSampleID: "demo-\(kind.rawValue)-\(Int(start.timeIntervalSince1970))",
                                  importedAt: now, quality: .valid, method: .deviceHistory)
        context.insert(StoredSample(sample))
    }

    /// The coach statement of the test view (tone from the owner's examples; 04 delivers the real ones).
    static func insight(now: Date, calendar: Calendar = .current) -> CoachInsight {
        let today = calendar.startOfDay(for: now)
        let night = DateInterval(start: today.addingTimeInterval(-80 * 60), end: today.addingTimeInterval(6 * 3600 + 55 * 60))
        let run = DateInterval(start: today.addingTimeInterval(-7 * 3600), duration: 45 * 60)
        return CoachInsight(
            subjectID: TestScenario.owner, createdAt: today.addingTimeInterval(7 * 3600),
            observation: "Ruhepuls in den letzten drei Nächten 2 Schläge tiefer, HRV nachts höher, Puls nach dem Lauf gestern schneller unten.",
            interpretation: "Dein Rhythmus wird wieder stabiler. Die letzten Nächte passen besser zusammen, und du kommst nach Belastung schneller zurück. Genau diese Regelmäßigkeit würde ich jetzt halten.",
            direction: .improving,
            evidence: [
                EvidenceRef(kind: .restingHeartRate, window: night, label: "Ruhepuls letzte Nacht", shownValue: "54 bpm",
                            comparison: "deine letzten 14 Nächte: 55–58 bpm"),
                EvidenceRef(kind: .ringHRV, window: night, label: "HRV in der Nacht", shownValue: "52 ms",
                            comparison: "deine letzten 14 Nächte: 44–50 ms"),
                EvidenceRef(kind: .heartRate, window: run, label: "Puls nach dem Lauf gestern", shownValue: nil,
                            comparison: "in 4 Minuten unter 100 bpm"),
            ],
            action: CoachAction(kind: .startWorkout, title: "Meine Einheit starten", payload: "easyRun"),
            priority: 1, valid: DateInterval(start: today, duration: 86_400), recheckAt: today.addingTimeInterval(86_400))
    }
}
