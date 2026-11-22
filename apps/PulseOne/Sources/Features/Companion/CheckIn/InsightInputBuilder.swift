import Foundation
import PulseCore
import SwiftData

/// Collects the stored nights for the insight screen. Never invents a value: a night without a stored
/// measurement stays absent and shows as a gap.
@MainActor
enum InsightInputBuilder {
    static let answersKey = "insight.answers"
    static let answersDayKey = "insight.answersDay"
    private static let windowDays = 35

    static func make(context: ModelContext, owner: UUID, now: Date, calendar: Calendar = .current) -> InsightInput {
        let reader = SampleReader(context: context)
        func values(_ kind: SampleKind, scale: Double = 1, label: (DailyValue) -> String) -> [NightValue] {
            reader.daily(kind, days: windowDays, profileID: owner, calendar: calendar, now: now)
                .map { NightValue(day: $0.day, value: $0.value * scale, source: label($0)) }
        }
        func origin(_ value: DailyValue) -> String {
            value.origins.map(\.source.title).sorted().first ?? "Unbekannte Quelle"
        }
        let hrv = values(.ringHRV) { _ in "Ring-HRV" } + values(.heartRateVariability) { "SDNN · \(origin($0))" }
        let assembled = NightAssembler.assemble(
            restingHeartRate: values(.restingHeartRate, label: origin),
            hrv: hrv,
            sleepHours: values(.sleepDuration, scale: 1 / 3600, label: origin),
            calendar: calendar)
        let newest = [SampleKind.restingHeartRate, .ringHRV, .heartRateVariability, .sleepDuration]
            .compactMap { reader.latest($0, within: 3, profileID: owner, now: now)?.start }
            .max()
        let lastSync = UserDefaults.standard.object(forKey: ColmiCentral.lastSyncKey) as? Date
        return InsightInput(profileID: owner, now: now, nights: assembled.nights,
                            origin: NightAssembler.originText(assembled),
                            hrvMethod: assembled.hrvSource ?? "HRV",
                            newestSample: newest, lastSync: lastSync, answers: answers(now: now, calendar: calendar))
    }

    /// Answers are kept for the current day only; tomorrow's insight asks again.
    static func answers(now: Date, calendar: Calendar = .current) -> [String: String] {
        let defaults = UserDefaults.standard
        guard let day = defaults.object(forKey: answersDayKey) as? Date,
              calendar.isDate(day, inSameDayAs: now) else { return [:] }
        return defaults.dictionary(forKey: answersKey) as? [String: String] ?? [:]
    }

    static func storeAnswer(_ question: String, _ option: String, now: Date = .now) {
        var current = answers(now: now)
        current[question] = option
        UserDefaults.standard.set(current, forKey: answersKey)
        UserDefaults.standard.set(now, forKey: answersDayKey)
    }
}

/// Visibly synthetic nights for the three demonstration cases (Codex P1-005). Only used with
/// `-uiTesting YES`; the screen shows the "Testansicht" banner.
enum InsightDemo {
    static let scenarios = ["insightNormal", "insightNights", "insightGap"]

    static func input(for name: String, calendar: Calendar = .current) -> InsightInput {
        let now = TestScenario.fixedTime
        let today = calendar.startOfDay(for: now)
        func night(_ offset: Int, _ rhr: Double, _ hrv: Double, _ sleep: Double) -> NightPoint {
            let date = calendar.date(byAdding: .day, value: -offset, to: today) ?? today
            return NightPoint(date: date, restingHeartRate: rhr, hrv: hrv, sleepHours: sleep)
        }
        // 28 calm nights; two nights (offsets 9 and 16) are missing on purpose, so the axis shows real gaps.
        func calm(from start: Int) -> [NightPoint] {
            let offsets = (start...(start + 27)).filter { $0 != 9 && $0 != 16 }
            return offsets.map { (offset: Int) -> NightPoint in
                // Gentle, irregular variation instead of a sawtooth, so the chart reads like real nights.
                let wiggle: [Double] = [0, 1, 0, -1, 0, 1, 1, 0, -1, 0, 1]
                let rhr: Double = 56 + wiggle[offset % wiggle.count]
                let hrv: Double = 43 - 2 * wiggle[(offset + 3) % wiggle.count]
                let sleep: Double = 7.2 + 0.3 * wiggle[(offset + 5) % wiggle.count]
                return night(offset, rhr, hrv, sleep)
            }
        }
        let nights: [NightPoint]
        var newest: Date? = calendar.date(byAdding: .hour, value: 6, to: today)
        switch name {
        case "insightNights":
            nights = calm(from: 3) + [night(2, 62, 33, 7.0), night(1, 63, 31, 6.9), night(0, 64, 30, 7.1)]
        case "insightGap":
            nights = calm(from: 1)
            newest = calendar.date(byAdding: .hour, value: -18, to: today)
        default:
            nights = calm(from: 1) + [night(0, 54, 46, 7.4)]
        }
        return InsightInput(profileID: TestScenario.owner, now: now, nights: nights, origin: "Testansicht · synthetische Nächte",
                            hrvMethod: "Ring-HRV", newestSample: newest, lastSync: newest)
    }
}
