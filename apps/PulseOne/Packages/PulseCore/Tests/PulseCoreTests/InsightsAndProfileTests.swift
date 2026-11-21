import Foundation
import Testing
@testable import PulseCore

@Suite("Personal baseline")
struct PersonalBaselineTests {
    var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Berlin") ?? .gmt
        return c
    }
    var today: Date { calendar.date(from: DateComponents(year: 2026, month: 11, day: 21)) ?? .now }

    func day(_ offset: Int, _ value: Double, kind: SampleKind = .restingHeartRate) -> DailyValue {
        let date = calendar.date(byAdding: .day, value: offset, to: today) ?? today
        return DailyValue(day: date, kind: kind, aggregation: kind.aggregation, value: value, minimum: value, maximum: value,
                          sampleCount: 1, origins: [], sampleIDs: [], coveredHours: 1, caveats: [])
    }

    @Test func formsUntilSevenDays() {
        let days = (1...6).map { day(-$0, 60) }
        let status = PersonalBaseline.status(for: days, kind: .restingHeartRate, before: today, calendar: calendar)
        #expect(status == .forming(daysAvailable: 6, daysNeeded: 1))
        #expect(status.summary == "Noch 1 Tag bis zu deinem persönlichen Bereich")
        #expect(status.baseline == nil)
    }

    @Test func bandIsTheMiddleHalf() throws {
        let values: [Double] = [50, 52, 54, 56, 58, 60, 62, 64, 66]
        let days = values.enumerated().map { day(-($0.offset + 1), $0.element) }
        let baseline = try #require(PersonalBaseline.status(for: days, kind: .restingHeartRate, before: today,
                                                            calendar: calendar).baseline)
        #expect(baseline.median == 58)
        #expect(baseline.lower == 54)
        #expect(baseline.upper == 62)
        #expect(baseline.dayCount == 9)
        #expect(baseline.position(of: 53) == .below)
        #expect(baseline.position(of: 58) == .within)
        #expect(baseline.position(of: 70) == .above)
        #expect(BandPosition.above.description == "über deinem üblichen Bereich")
    }

    /// The reference day, other kinds and days outside the window never enter the band.
    @Test func usesOnlyEarlierDaysOfTheKindInTheWindow() throws {
        var days = (1...7).map { day(-$0, 60) }
        days.append(day(0, 200))
        days.append(day(-40, 10))
        days.append(day(-2, 999, kind: .steps))
        let baseline = try #require(PersonalBaseline.status(for: days, kind: .restingHeartRate, before: today,
                                                            calendar: calendar).baseline)
        #expect(baseline.dayCount == 7)
        #expect(baseline.lower == 60 && baseline.upper == 60)
    }

    @Test func percentileInterpolates() {
        #expect(PersonalBaseline.percentile([10, 20], 0.5) == 15)
        #expect(PersonalBaseline.percentile([7], 0.25) == 7)
        #expect(PersonalBaseline.percentile([], 0.5) == 0)
    }
}

@Suite("User profile")
struct UserProfileTests {
    @Test func implausibleValuesAreDropped() {
        let profile = UserProfile(displayName: "  Alex ", birthYear: 1850, heightCm: 182, weightKg: 5).sanitized()
        #expect(profile.displayName == "Alex")
        #expect(profile.birthYear == nil)
        #expect(profile.heightCm == 182)
        #expect(profile.weightKg == nil)
    }

    @Test func greetingUsesNameWhenKnown() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        let morning = calendar.date(from: DateComponents(year: 2026, month: 11, day: 21, hour: 7)) ?? .now
        #expect(UserProfile(displayName: "Alex").greeting(at: morning, calendar: calendar) == "Guten Morgen, Alex")
        #expect(UserProfile().greeting(at: morning, calendar: calendar) == "Guten Morgen")
        #expect(UserProfile(birthYear: 1990).approximateAge(at: morning, calendar: calendar) == 36)
    }

    @Test func roundTripsAsJSON() throws {
        let profile = UserProfile(displayName: "Alex", birthYear: 1990, sex: .undisclosed, heightCm: 180, weightKg: 78)
        let decoded = try JSONDecoder().decode(UserProfile.self, from: JSONEncoder().encode(profile))
        #expect(decoded == profile)
    }
}

@Suite("Display and trends")
struct DisplayAndTrendTests {
    var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Berlin") ?? .gmt
        return c
    }
    var now: Date { calendar.date(from: DateComponents(year: 2026, month: 11, day: 21, hour: 18)) ?? .now }

    func sample(_ kind: SampleKind, _ value: Double, hoursAgo: Double, device: String = "ring") -> HealthSample {
        let start = now.addingTimeInterval(-hoursAgo * 3600)
        return HealthSample(profileID: nil, kind: kind, value: value, unit: kind.canonicalUnit, start: start,
                            end: kind.aggregation == .point ? start : start.addingTimeInterval(60),
                            timeZoneIdentifier: "Europe/Berlin", source: .colmiRing, deviceID: device,
                            originalSampleID: UUID().uuidString, importedAt: now, quality: .valid, method: .liveSensor)
    }

    @Test func germanNumbersAndUnits() {
        #expect(SampleKind.steps.display(8412) == "8.412")
        #expect(SampleKind.sleepDuration.display(24_300) == "6,8")
        #expect(SampleKind.sleepDuration.displayUnit == "h")
        #expect(SampleKind.distance.display(5230) == "5,2")
        #expect(SampleKind.restingHeartRate.display(58.4) == "58")
        #expect(SampleKind.bodyMass.display(78.25) == "78,2" || SampleKind.bodyMass.display(78.25) == "78,3")
    }

    @Test func dayViewIsHourlyAndLeavesGaps() {
        let samples = [sample(.heartRate, 60, hoursAgo: 1), sample(.heartRate, 70, hoursAgo: 0.9),
                       sample(.heartRate, 80, hoursAgo: 5)]
        let points = TrendSeries.points(samples, kind: .heartRate, range: .day, now: now, calendar: calendar)
        #expect(points.count == 2)
        #expect(points.last?.value == 65)
        #expect(points.first?.value == 80)
    }

    @Test func weekViewIsDailyAndIgnoresOlderDays() {
        let samples = [sample(.steps, 1000, hoursAgo: 2), sample(.steps, 500, hoursAgo: 30), sample(.steps, 9999, hoursAgo: 24 * 10)]
        let points = TrendSeries.points(samples, kind: .steps, range: .week, now: now, calendar: calendar)
        #expect(points.map(\.value) == [500, 1000])
        let summary = TrendSeries.summary(points)
        #expect(summary?.median == 750)
        #expect(summary?.maximum == 1000)
    }

    @Test func rangesStartAtMidnight() {
        let start = TrendRange.week.start(now: now, calendar: calendar)
        #expect(calendar.component(.hour, from: start) == 0)
        #expect(calendar.dateComponents([.day], from: start, to: now).day == 6)
    }
}
