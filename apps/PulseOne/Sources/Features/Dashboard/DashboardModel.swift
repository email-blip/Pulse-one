import Foundation
import Observation
import PulseCore
import SwiftData

/// Data of the dashboard: one reading per tile (newest valid value with its time and real points for the
/// mini history), last night's phases and the coach statement. Stored values only.
@MainActor
@Observable
final class DashboardModel {
    private(set) var readings: [String: TileReading] = [:]
    private(set) var lastNight: SleepNight?
    private(set) var insight: CoachInsight?
    private(set) var hasAnyValue = false
    private(set) var loaded = false
    let calendar: Calendar

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    func reload(context: ModelContext, profileID: UUID?, now: Date) {
        let since = calendar.date(byAdding: .day, value: -8, to: calendar.startOfDay(for: now)) ?? now.addingTimeInterval(-8 * 86_400)
        let window = DateInterval(start: since, end: now.addingTimeInterval(60))
        let kinds: Set<SampleKind> = [.heartRate, .restingHeartRate, .ringHRV, .heartRateVariability, .oxygenSaturation,
                                      .ringStress, .steps, .activeEnergy, .trainingDuration, .sleepDuration]
        let points = ((try? MeasurementPointStore(context: context).points(kinds: kinds, in: window)) ?? [])
            .filter { $0.quality.usableForAnalysis && (profileID == nil || $0.subjectID == profileID) }
        var result: [String: TileReading] = [:]
        for kind in kinds where kind != .trainingDuration && kind != .sleepDuration {
            if let reading = TileSummary.reading(kind: kind, points: points, now: now, calendar: calendar) {
                result[DashboardTile.metric(kind).id] = reading
            }
        }
        // HRV tile: ring HRV first, Apple's SDNN when there is no ring value.
        if result[DashboardTile.metric(.ringHRV).id] == nil, let sdnn = result[DashboardTile.metric(.heartRateVariability).id] {
            result[DashboardTile.metric(.ringHRV).id] = sdnn
        }
        if result[DashboardTile.metric(.restingHeartRate).id] == nil,
           let night = nightResting(context: context, profileID: profileID, now: now) {
            result[DashboardTile.metric(.restingHeartRate).id] = night
        }
        let nights = (try? SleepSegmentStore(context: context).nights(in: DateInterval(start: since, end: now), subjectID: profileID)) ?? []
        lastNight = nights.last { ($0.inBed?.end ?? .distantPast) <= now.addingTimeInterval(60) }
        if let sleep = sleepReading(nights: nights, points: points, now: now) { result["sleep"] = sleep }
        if let training = trainingReading(points: points, now: now) { result["training"] = training }
        readings = result
        hasAnyValue = !points.isEmpty || lastNight != nil
        insight = TimelineDemo.isActive ? TimelineDemo.insight(now: now, calendar: calendar) : nil
        loaded = true
    }

    /// Ring-only users have no daily resting pulse from a source: the night resting pulse from heart rate,
    /// the same method and number as the coach (`NightRestingSeries`).
    private func nightResting(context: ModelContext, profileID: UUID?, now: Date) -> TileReading? {
        let reader = SampleReader(context: context)
        let start = NightRestingSeries.readStart(days: 8, now: now, calendar: calendar)
        let nights = NightRestingSeries.daily(reader.samples([.heartRate], since: start, profileID: profileID),
                                              days: 8, now: now, calendar: calendar)
        guard let last = nights.last else { return nil }
        let kind = SampleKind.restingHeartRate
        let reference = calendar.isDate(last.day, inSameDayAs: now) ? "LETZTE NACHT" : "NACHT ZUM \(Self.dayText(last.day, calendar))"
        return TileReading(value: last.value, text: kind.display(last.value), unit: kind.displayUnit, reference: reference,
                           at: last.day.addingTimeInterval(5 * 3600),
                           spark: nights.map { SparkPoint(at: $0.day, value: $0.value, run: 0) },
                           isOld: now.timeIntervalSince(last.day) > 2 * 86_400)
    }

    /// Asleep time of the newest night (phases from the ring), else the newest sleep duration of a source.
    private func sleepReading(nights: [SleepNight], points: [MeasurementPoint], now: Date) -> TileReading? {
        if let night = lastNight, let bed = night.inBed {
            let spark = nights.compactMap { night -> SparkPoint? in
                guard let end = night.inBed?.end else { return nil }
                return SparkPoint(at: end, value: night.asleep / 3600, run: 0)
            }
            return TileReading(value: night.asleep, text: Self.hoursMinutes(night.asleep), unit: "h",
                               reference: TileSummary.reference(for: bed.end, now: now, night: true, calendar: calendar),
                               at: bed.end, spark: spark, isOld: now.timeIntervalSince(bed.end) > 86_400)
        }
        let sleeps = points.filter { $0.kind == .sleepDuration }.sorted { $0.measuredUntil < $1.measuredUntil }
        guard let last = sleeps.last else { return nil }
        return TileReading(value: last.value, text: Self.hoursMinutes(last.value), unit: "h",
                           reference: TileSummary.reference(for: last.measuredUntil, now: now, night: true, calendar: calendar),
                           at: last.measuredUntil,
                           spark: sleeps.map { SparkPoint(at: $0.measuredUntil, value: $0.value / 3600, run: 0) },
                           isOld: now.timeIntervalSince(last.measuredUntil) > 86_400)
    }

    /// Training time of the newest day with a workout.
    private func trainingReading(points: [MeasurementPoint], now: Date) -> TileReading? {
        let workouts = points.filter { $0.kind == .trainingDuration }.sorted { $0.measuredAt < $1.measuredAt }
        guard let last = workouts.last else { return nil }
        let day = calendar.startOfDay(for: last.measuredAt)
        let total = workouts.filter { calendar.isDate($0.measuredAt, inSameDayAs: day) }.reduce(0) { $0 + $1.value }
        let minutes = Int((total / 60).rounded())
        return TileReading(value: total, text: "\(minutes)", unit: "min",
                           reference: TileSummary.reference(for: last.measuredUntil, now: now, calendar: calendar),
                           at: last.measuredAt, spark: [], isOld: now.timeIntervalSince(last.measuredUntil) > 86_400)
    }

    /// "7:12"
    static func hoursMinutes(_ seconds: TimeInterval) -> String {
        let minutes = Int((seconds / 60).rounded())
        return String(format: "%d:%02d", minutes / 60, minutes % 60)
    }

    static func dayText(_ date: Date, _ calendar: Calendar) -> String {
        date.formatted(Date.FormatStyle(locale: Locale(identifier: "de_DE"), calendar: calendar, timeZone: calendar.timeZone)
            .day(.twoDigits).month(.twoDigits))
    }
}
