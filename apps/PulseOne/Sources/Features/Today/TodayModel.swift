import Foundation
import PulseCore

/// One card on TODAY, already formatted. Built from stored samples only.
struct TodayMetric: Identifiable, Equatable {
    let kind: SampleKind
    let value: String
    let unit: String
    let detail: String
    let bandText: String?
    var id: String { kind.rawValue }
}

@MainActor
enum TodayModel {
    /// Kinds TODAY shows when data exists, in this order.
    static let kinds: [SampleKind] = [.restingHeartRate, .heartRateVariability, .sleepDuration, .steps,
                                      .oxygenSaturation, .heartRate, .activeEnergy, .respiratoryRate]

    static func metrics(reader: SampleReader, profileID: UUID?, now: Date = .now,
                        calendar: Calendar = .current) -> [TodayMetric] {
        kinds.compactMap { metric(for: $0, reader: reader, profileID: profileID, now: now, calendar: calendar) }
    }

    static func metric(for kind: SampleKind, reader: SampleReader, profileID: UUID?, now: Date,
                       calendar: Calendar) -> TodayMetric? {
        let today = calendar.startOfDay(for: now)
        let daily = reader.daily(kind, days: PersonalBaseline.defaultWindowDays + 7, profileID: profileID,
                                 calendar: calendar, now: now)
        guard let last = daily.last,
              let age = calendar.dateComponents([.day], from: last.day, to: today).day, age <= 1 else { return nil }
        let sources = Set(last.origins.map(\.source.title)).sorted().joined(separator: ", ")
        var parts = [dayLabel(last.day, today: today, calendar: calendar)]
        let value: String
        let band: String?
        if kind == .heartRate, let latest = reader.latest(.heartRate, within: 2, profileID: profileID, now: now) {
            // Single readings: the newest one, at its time; a day mean would hide it.
            value = kind.display(latest.value)
            parts = [timeLabel(latest.start, today: today, calendar: calendar)]
            band = nil
        } else {
            value = kind.display(last.value)
            parts.append(kind.dailyMeaning)
            let status = PersonalBaseline.status(for: daily, kind: kind, before: last.day, calendar: calendar)
            if let baseline = status.baseline {
                band = "\(baseline.position(of: last.value).description) (\(kind.display(baseline.lower))–\(kind.display(baseline.upper)) \(kind.displayUnit))"
            } else {
                band = status.summary
            }
        }
        if !sources.isEmpty { parts.append(sources) }
        if last.isProvisional { parts.append("vorläufig") }
        return TodayMetric(kind: kind, value: value, unit: kind.displayUnit, detail: parts.joined(separator: " · "),
                           bandText: band)
    }

    static func dayLabel(_ day: Date, today: Date, calendar: Calendar) -> String {
        if calendar.isDate(day, inSameDayAs: today) { return "heute" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: today), calendar.isDate(day, inSameDayAs: yesterday) {
            return "gestern"
        }
        return day.formatted(.dateTime.day().month(.abbreviated).locale(Locale(identifier: "de_DE")))
    }

    static func timeLabel(_ date: Date, today: Date, calendar: Calendar) -> String {
        let time = date.formatted(.dateTime.hour().minute().locale(Locale(identifier: "de_DE")))
        return "\(dayLabel(calendar.startOfDay(for: date), today: today, calendar: calendar)) \(time)"
    }
}
