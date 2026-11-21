import Foundation

// Companion (Begleiter) T1, idea P7: "Körper-Tempo", a rough, openly documented approximation (label C).
// Formula (years relative to the calendar age, total clamped to ±10):
//   resting heart rate (median of the last 14 nights):  (bpm − 60) × 0.25
//   daily steps (median of the last 14 days):           −(steps − 7000) / 1000 × 0.4, clamped ±3
//   sleep duration (median hours):                      |h − 7.5| × 1.0, clamped 0…3
//   SpO₂ night mean below 94 %:                         +1
// It is no medical statement and is always shown with its label.

public enum BodyPace {
    /// Nights with a resting heart rate needed (within the last 28).
    public static let minimumNights = 14
    /// Values used per input (the most recent ones).
    public static let windowDays = 14
    /// Days an optional input (steps, sleep, SpO₂) needs before it counts.
    static let minimumOptionalDays = 7
    public static let maximumYears = 10.0

    public static func estimate(_ input: CompanionInput) -> BodyPaceResult? {
        guard let birthYear = input.birthYear else { return nil }
        let calendar = input.calendar
        let calendarAge = calendar.component(.year, from: input.now) - birthYear
        guard calendarAge > 0, calendarAge < 120 else { return nil }

        let today = calendar.startOfDay(for: input.now)
        let records = NightMath.records(endingOn: today, count: NightAnalyzer.bandWindowNights, pool: NightSamples(input.samples),
                                        dailyResting: [:], calendar: calendar)
        let restingValues = Array(records.compactMap(\.nightRestingHeartRate).suffix(windowDays))
        guard records.compactMap(\.nightRestingHeartRate).count >= minimumNights,
              let resting = NightMath.median(restingValues) else { return nil }

        var components: [BodyPaceComponent] = []
        components.append(BodyPaceComponent(name: "Ruhepuls", years: (resting - 60) * 0.25,
                                            detail: "Nachts im Mittel \(Int(resting.rounded())) Schläge pro Minute"))

        // Complete days only: today is still running.
        let stepsByDay = NightMath.dailySteps(input.samples, calendar: calendar)
        let stepValues = Array((1...NightAnalyzer.bandWindowNights).reversed().compactMap { back in
            stepsByDay[NightMath.day(today, offset: -back, calendar: calendar)]
        }.suffix(windowDays))
        if stepValues.count >= minimumOptionalDays, let steps = NightMath.median(stepValues) {
            let years = min(max(-(steps - 7_000) / 1_000 * 0.4, -3), 3)
            components.append(BodyPaceComponent(name: "Schritte", years: years,
                                                detail: "Im Mittel \(Int(steps.rounded())) Schritte pro Tag"))
        }

        let sleepValues = Array(records.compactMap(\.sleepSeconds).suffix(windowDays))
        if sleepValues.count >= minimumOptionalDays, let sleep = NightMath.median(sleepValues) {
            let hours = sleep / 3_600
            let years = min(max(abs(hours - 7.5) * 1.0, 0), 3)
            components.append(BodyPaceComponent(name: "Schlaf", years: years,
                                                detail: "Im Mittel \(NightMath.oneDecimal(hours)) Stunden Schlaf"))
        }

        let spo2Values = Array(records.compactMap(\.spo2).suffix(windowDays))
        if spo2Values.count >= minimumOptionalDays, let spo2 = NightMath.mean(spo2Values) {
            components.append(BodyPaceComponent(name: "Sauerstoffsättigung", years: spo2 < 94 ? 1 : 0,
                                                detail: "Nachts im Mittel \(Int(spo2.rounded())) %"))
        }

        let total = min(max(components.reduce(0.0) { $0 + $1.years }, -maximumYears), maximumYears)
        let paceAge = calendarAge + Int(total.rounded())
        let sentence = "Dein Körper-Tempo liegt bei etwa \(paceAge) Jahren (Kalenderalter \(calendarAge)). "
            + "Grobe Annäherung aus Ruhepuls, Schritten und Schlaf, keine medizinische Aussage."
        return BodyPaceResult(calendarAge: calendarAge, paceAge: paceAge, components: components, label: .c, sentence: sentence)
    }
}
