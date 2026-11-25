import Foundation
import Testing
@testable import PulseCore

@Suite("Chart readability (team 03)")
struct ChartSupportTests {
    /// 2027-01-15 09:00 in Berlin (a Friday).
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin") ?? .current
        calendar.firstWeekday = 2
        return calendar
    }

    func point(_ kind: SampleKind, _ value: Double, at offset: TimeInterval, duration: TimeInterval = 0) -> MeasurementPoint {
        let at = t0.addingTimeInterval(offset)
        return MeasurementPoint(id: UUID(), subjectID: nil, deviceID: "R03", source: .colmiRing, kind: kind, value: value,
                                unit: kind.canonicalUnit, method: .deviceHistory, measuredAt: at,
                                measuredUntil: at.addingTimeInterval(duration), receivedAt: at, importedAt: at,
                                quality: .valid, originalReference: "slot-\(Int(offset))")
    }

    // MARK: Y axis

    @Test func axisTicksAreRoundAndInside() {
        #expect(AxisTicks.values(in: 52...118) == [60, 80, 100])
        #expect(AxisTicks.values(in: 90.4...100) == [95, 100])
        #expect(AxisTicks.values(in: 0...8_800) == [0, 5_000])
        for domain in [52.0...118, 90.4...100, 0...8_800, 21.3...44.9, 0...1] {
            let ticks = AxisTicks.values(in: domain)
            #expect((2...3).contains(ticks.count), "\(domain): \(ticks)")
            #expect(ticks.allSatisfy { domain.contains($0) }, "\(domain): \(ticks)")
        }
        #expect(AxisTicks.values(in: 5...5).isEmpty)
    }

    // MARK: Comparison

    @Test func yesterdayIsShiftedOntoTheWindowAndGapsStayEmpty() {
        let day: TimeInterval = 86_400
        // Yesterday: pulse 60 every 5 minutes from 00:00 to 02:00 window time, nothing after.
        let yesterday = stride(from: 0.0, to: 2 * 3600, by: 300).map { point(.heartRate, 60, at: $0 - day) }
        let today = stride(from: 0.0, to: 4 * 3600, by: 300).map { point(.heartRate, 70, at: $0) }
        let window = DateInterval(start: t0, duration: day)
        let values = TrackComparison.profile((yesterday + today).sorted { $0.measuredAt < $1.measuredAt },
                                             kind: .heartRate, window: window, mode: .yesterday, calendar: calendar)
        #expect(!values.isEmpty)
        #expect(values.allSatisfy { $0.value == 60 }, "today's values must not leak into the comparison")
        #expect(values.allSatisfy { $0.start >= t0 && $0.end <= t0.addingTimeInterval(2 * 3600 + 600) })
        #expect(Set(values.map(\.run)).count == 1)
    }

    @Test func weekMeanNeedsThreeDaysPerSlot() {
        let day: TimeInterval = 86_400
        var points: [MeasurementPoint] = []
        // Slot at 00:00: days 1–4 measured (mean of 60, 62, 64, 66 = 63). Slot at 06:00: only two days.
        for (back, value) in [(1, 60.0), (2, 62), (3, 64), (4, 66)] {
            points.append(point(.heartRate, value, at: -Double(back) * day + 60))
        }
        for back in [1, 2] { points.append(point(.heartRate, 80, at: -Double(back) * day + 6 * 3600)) }
        let window = DateInterval(start: t0, duration: day)
        let values = TrackComparison.profile(points.sorted { $0.measuredAt < $1.measuredAt }, kind: .heartRate,
                                             window: window, mode: .week, calendar: calendar)
        #expect(values.count == 1)
        #expect(values.first?.value == 63)
        #expect(values.first?.count == 4)
        #expect(values.first?.low == 60 && values.first?.high == 66)
    }

    @Test func cumulativeComparisonSumsPerRingStep() {
        let day: TimeInterval = 86_400
        let steps = [point(.steps, 100, at: -day, duration: 900), point(.steps, 50, at: -day + 300, duration: 300)]
        let window = DateInterval(start: t0, duration: day)
        #expect(TrackComparison.slot(for: .steps, window: window) == 900)
        let values = TrackComparison.profile(steps, kind: .steps, window: window, mode: .yesterday, calendar: calendar)
        #expect(values.map(\.value) == [150])
        #expect(TrackComparison.profile(steps, kind: .steps, window: window, mode: .off, calendar: calendar).isEmpty)
    }

    @Test func comparisonOnlyOnTheDayScale() {
        #expect(TrackComparison.isAvailable(for: DateInterval(start: t0, duration: 86_400)))
        #expect(!TrackComparison.isAvailable(for: DateInterval(start: t0, duration: 7 * 86_400)))
        #expect(TrackComparison.slot(for: .heartRate, window: DateInterval(start: t0, duration: 86_400)) == 600)
    }

    // MARK: Training tile

    @Test func trainingTileShowsTodayThenTheWeek() {
        let session = { (offset: TimeInterval, minutes: Double) in
            TrainingSession(start: t0.addingTimeInterval(offset), end: t0.addingTimeInterval(offset + minutes * 60), title: "Lauf")
        }
        // Friday 09:00. Wednesday 18:00 (40 min) and Thursday 07:00 (25 min) this week; last Sunday 30 min.
        let sessions = [session(-2 * 86_400 + 9 * 3600, 40), session(-86_400 - 2 * 3600, 25), session(-5 * 86_400, 30)]
        let week = TrainingWeek(sessions: sessions, now: t0, calendar: calendar)
        #expect(week.todayCount == 0)
        #expect(week.weekCount == 2)
        #expect(week.weekMinutes == 65)
        #expect(week.days.count == 7)
        #expect(week.days.last == 0)
        #expect(week.days.reduce(0, +) == 95)
        let reading = week.reading(now: t0, calendar: calendar)
        #expect(reading?.text == "65")
        #expect(reading?.reference == "WOCHE · 2 EINHEITEN · LETZTE GESTERN 07:00")

        let withToday = TrainingWeek(sessions: sessions + [session(-3600, 30)], now: t0, calendar: calendar)
        #expect(withToday.reading(now: t0, calendar: calendar)?.reference == "HEUTE · 1 EINHEIT")
        #expect(withToday.reading(now: t0, calendar: calendar)?.text == "30")

        #expect(TrainingWeek(sessions: [], now: t0, calendar: calendar).reading(now: t0, calendar: calendar) == nil)
    }
}
