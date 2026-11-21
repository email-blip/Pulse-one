import Foundation
import Testing
@testable import PulseCore

// Companion (Begleiter) T1 – night summary, wake detection, day type, infection pattern, forecast, body pace.
// All data synthetic, fixed calendar (Europe/Berlin) and fixed dates.

private let berlin: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Berlin") ?? calendar.timeZone
    return calendar
}()

/// 2026-11-21 00:00 Europe/Berlin.
private let today: Date = berlin.date(from: DateComponents(year: 2026, month: 11, day: 21)) ?? Date(timeIntervalSince1970: 1_795_215_600)

/// `dayOffset` days from today, then `hour:minute` later (minutes may run past midnight).
private func at(_ dayOffset: Int, _ hour: Int, _ minute: Int = 0) -> Date {
    let day = berlin.date(byAdding: .day, value: dayOffset, to: today) ?? today
    return berlin.date(byAdding: .minute, value: hour * 60 + minute, to: day) ?? day
}

private func sample(_ kind: SampleKind, _ value: Double, _ start: Date, end: Date? = nil,
                    source: DataSourceKind = .colmiRing) -> HealthSample {
    HealthSample(profileID: nil, kind: kind, value: value, unit: kind.canonicalUnit, start: start, end: end,
                 timeZoneIdentifier: "Europe/Berlin", source: source, deviceID: source == .colmiRing ? "ring" : "watch",
                 originalSampleID: UUID().uuidString, importedAt: start, quality: .valid,
                 method: source == .colmiRing ? .deviceHistory : .healthStore)
}

/// The night ending on the morning of `dayOffset`: heart rate every 10 min from 22:00 to 06:00,
/// 20 bpm above `resting` until 23:00, then `resting`. Optional HRV/SpO₂ at 03:00, sleep 23:00–06:00.
private func night(_ dayOffset: Int, resting: Double, hrv: Double? = nil, hrvKind: SampleKind = .ringHRV,
                   sleepHours: Double? = nil, spo2: Double? = nil, skinDeviation: Double? = nil) -> [HealthSample] {
    var result: [HealthSample] = []
    for minute in stride(from: 0, through: 480, by: 10) {
        result.append(sample(.heartRate, minute < 60 ? resting + 20 : resting, at(dayOffset - 1, 22, minute)))
    }
    if let hrv {
        result.append(sample(hrvKind, hrv, at(dayOffset, 3), source: hrvKind == .ringHRV ? .colmiRing : .appleHealth))
    }
    if let sleepHours {
        result.append(sample(.sleepDuration, sleepHours * 3_600, at(dayOffset - 1, 23), end: at(dayOffset, 6)))
    }
    if let spo2 { result.append(sample(.oxygenSaturation, spo2, at(dayOffset, 3, 30))) }
    if let skinDeviation { result.append(sample(.skinTemperatureDeviation, skinDeviation, at(dayOffset, 4))) }
    return result
}

/// Nights `first…28` before today: resting 50…56, ring HRV 40…52, sleep 7.0…8.2 h (each value 4× over 28 nights).
/// Band over all 28: resting 51–55, HRV 42–50, sleep 7.2–8.0 h.
private func history(from first: Int = 1, through last: Int = 28) -> [HealthSample] {
    (first...last).flatMap { back in
        night(-back, resting: 50 + Double(back % 7), hrv: 40 + Double(back % 7) * 2, sleepHours: 7 + Double(back % 7) * 0.2)
    }
}

private func input(_ samples: [HealthSample], now: Date = at(0, 7, 30), birthYear: Int? = nil, confirmedWake: Date? = nil,
                   feelsSick: Bool = false, alarmSymptoms: Bool = false) -> CompanionInput {
    CompanionInput(now: now, calendar: berlin, samples: samples, preferences: CompanionPreferences(), birthYear: birthYear,
                   confirmedWake: confirmedWake, feelsSick: feelsSick, alarmSymptoms: alarmSymptoms)
}

private func summary(resting: Double? = 52, restingPosition: BandPosition? = .within, hrv: Double? = 46,
                     hrvKind: SampleKind? = .ringHRV, hrvPosition: BandPosition? = .within,
                     sleepHours: Double? = 8) -> NightSummary {
    NightSummary(sleepStart: nil, wake: WakeEstimate(time: nil, method: .unknown, confidence: 0),
                 sleepDuration: sleepHours.map { $0 * 3_600 }, sleepDurationIsEstimated: false,
                 nightRestingHeartRate: resting, lowestHeartRate: resting, hrv: hrv, hrvKind: hrvKind, spo2Average: nil,
                 restingHeartRatePosition: restingPosition, hrvPosition: hrvPosition, sleepPosition: nil,
                 morningHeartRate: nil, missing: [])
}

private let quiet = InfectionSignal(level: .none, reasons: [], usedTemperature: false, sentence: "")

@Suite("Companion – night summary")
struct CompanionNightSummaryTests {
    @Test func normalNightUsesStoredSleepAndBands() {
        let samples = history() + night(0, resting: 52, hrv: 46, sleepHours: 7.5, spo2: 96)
        let result = NightAnalyzer.summarize(input(samples))
        #expect(result.nightRestingHeartRate == 52)
        #expect(result.lowestHeartRate == 52)
        #expect(result.sleepStart == at(-1, 23))
        #expect(result.sleepDuration == 27_000)
        #expect(result.sleepDurationIsEstimated == false)
        #expect(result.wake.method == .sleepRecordEnd)
        #expect(result.wake.time == at(0, 6))
        #expect(result.wake.confidence == 0.4)
        #expect(result.hrv == 46)
        #expect(result.hrvKind == .ringHRV)
        #expect(result.spo2Average == 96)
        #expect(result.restingHeartRatePosition == .within)
        #expect(result.hrvPosition == .within)
        #expect(result.sleepPosition == .within)
        #expect(result.missing.isEmpty)
        #expect(DayTypeClassifier.classify(night: result, infection: quiet, sleepNeedHours: 8) == .recovered)
    }

    @Test func shortNightIsBelowBandAndClassifiedShort() {
        let samples = history() + night(0, resting: 52, hrv: 46, sleepHours: 5)
        let result = NightAnalyzer.summarize(input(samples))
        #expect(result.sleepDuration == 18_000)
        #expect(result.sleepPosition == .below)
        #expect(result.missing == [.oxygenSaturation])
        #expect(DayTypeClassifier.classify(night: result, infection: quiet, sleepNeedHours: 8) == .shortNight)
    }

    @Test func wakeFromHeartRateAndStepsEstimatesSleep() {
        var samples = history() + night(0, resting: 52)
        for minute in stride(from: 10, through: 90, by: 10) { samples.append(sample(.heartRate, 70, at(0, 6, minute))) }
        samples.append(sample(.steps, 400, at(0, 6, 15), end: at(0, 6, 30)))
        let result = NightAnalyzer.summarize(input(samples, now: at(0, 7, 40)))
        #expect(result.wake.method == .heartRateAndSteps)
        #expect(result.wake.time == at(0, 6, 10))
        #expect(result.wake.confidence == 0.6)
        #expect(result.sleepDurationIsEstimated)
        #expect(result.sleepDuration == 25_800)
        #expect(result.missing.contains(.sleepDuration))
        #expect(result.missing.contains(.ringHRV))
    }

    @Test func confirmedWakeWins() {
        let samples = history() + night(0, resting: 52, sleepHours: 7)
        let result = NightAnalyzer.summarize(input(samples, confirmedWake: at(0, 6, 45)))
        #expect(result.wake == WakeEstimate(time: at(0, 6, 45), method: .confirmed, confidence: 1))
    }

    @Test func noDataGivesEmptySummary() {
        let result = NightAnalyzer.summarize(input([]))
        #expect(result.nightRestingHeartRate == nil)
        #expect(result.sleepDuration == nil)
        #expect(result.hrv == nil)
        #expect(result.wake.method == .unknown)
        #expect(result.restingHeartRatePosition == nil)
        #expect(result.missing == [.heartRate, .ringHRV, .sleepDuration, .oxygenSaturation])
        #expect(DayTypeClassifier.classify(night: result, infection: quiet, sleepNeedHours: 8) == .notEnoughData)
    }

    @Test func ringHRVIsPreferredAndNeverMixedWithApple() {
        var both = history() + night(0, resting: 52, hrv: 46, sleepHours: 7.5)
        both.append(sample(.heartRateVariability, 80, at(0, 2), source: .appleHealth))
        let ring = NightAnalyzer.summarize(input(both))
        #expect(ring.hrv == 46)
        #expect(ring.hrvKind == .ringHRV)

        let appleOnly = history() + night(0, resting: 52, hrv: 80, hrvKind: .heartRateVariability, sleepHours: 7.5)
        let apple = NightAnalyzer.summarize(input(appleOnly))
        #expect(apple.hrv == 80)
        #expect(apple.hrvKind == .heartRateVariability)
        // The history only has ring HRV, so there is no Apple band to compare with.
        #expect(apple.hrvPosition == nil)
    }
}

@Suite("Companion – wake detection")
struct CompanionWakeTests {
    /// Heart rate every 10 min from 23:00 to 07:30; `value` gets the minutes after 23:00.
    private func heart(_ value: (Int) -> Double) -> [HealthSample] {
        stride(from: 0, through: 510, by: 10).map { sample(.heartRate, value($0), at(-1, 23, $0)) }
    }

    @Test func confirmedBeatsEverything() {
        let estimate = WakeDetector.detect(heartRate: [], steps: [], sleepEnd: at(0, 6), confirmed: at(0, 7),
                                           now: at(0, 8), calendar: berlin)
        #expect(estimate == WakeEstimate(time: at(0, 7), method: .confirmed, confidence: 1))
    }

    @Test func heartRateRiseWithStepsAfterFour() {
        // Rise from 06:30 (minute 450) to 70 bpm, steps 06:30–06:45.
        let hr = heart { $0 >= 450 ? 70 : 52 }
        let steps = [sample(.steps, 300, at(0, 6, 30), end: at(0, 6, 45))]
        let estimate = WakeDetector.detect(heartRate: hr, steps: steps, sleepEnd: at(0, 6), confirmed: nil,
                                           now: at(0, 8), calendar: berlin)
        #expect(estimate.method == .heartRateAndSteps)
        #expect(estimate.time == at(0, 6, 30))
        #expect(estimate.confidence == 0.6)
    }

    @Test func riseWithoutStepsFallsBackToSleepEnd() {
        let hr = heart { $0 >= 450 ? 70 : 52 }
        let estimate = WakeDetector.detect(heartRate: hr, steps: [], sleepEnd: at(0, 6, 20), confirmed: nil,
                                           now: at(0, 8), calendar: berlin)
        #expect(estimate == WakeEstimate(time: at(0, 6, 20), method: .sleepRecordEnd, confidence: 0.4))
    }

    @Test func nightTimeRiseBeforeFourIsIgnored() {
        // 03:00–03:20 (minutes 240…260) up with steps, otherwise flat.
        let hr = heart { (240...260).contains($0) ? 75 : 52 }
        let steps = [sample(.steps, 40, at(0, 3), end: at(0, 3, 15))]
        let estimate = WakeDetector.detect(heartRate: hr, steps: steps, sleepEnd: nil, confirmed: nil,
                                           now: at(0, 8), calendar: berlin)
        #expect(estimate == WakeEstimate(time: nil, method: .unknown, confidence: 0))
    }
}

@Suite("Companion – day type")
struct CompanionDayTypeTests {
    @Test func classifierRules() {
        #expect(DayTypeClassifier.classify(night: summary(), infection: quiet, sleepNeedHours: 8) == .recovered)
        #expect(DayTypeClassifier.classify(night: summary(restingPosition: .above), infection: quiet, sleepNeedHours: 8) == .normal)
        #expect(DayTypeClassifier.classify(night: summary(sleepHours: 7), infection: quiet, sleepNeedHours: 8) == .normal)
        #expect(DayTypeClassifier.classify(night: summary(sleepHours: 6), infection: quiet, sleepNeedHours: 8) == .shortNight)
        #expect(DayTypeClassifier.classify(night: summary(resting: nil, sleepHours: nil), infection: quiet,
                                           sleepNeedHours: 8) == .notEnoughData)
        let pattern = InfectionSignal(level: .pattern, reasons: [], usedTemperature: false, sentence: "")
        #expect(DayTypeClassifier.classify(night: summary(), infection: pattern, sleepNeedHours: 8) == .unusualPattern)
    }
}

@Suite("Companion – infection pattern")
struct CompanionInfectionTests {
    @Test func usualNightsGiveNone() {
        let signal = InfectionWatch.assess(input(history() + night(0, resting: 52, hrv: 46)))
        #expect(signal.level == .none)
        #expect(signal.sentence == "Deine Nachtwerte liegen in deinem üblichen Bereich. Ein Infekt-Muster sehe ich heute nicht. "
            + "Das ist keine Diagnose.")
        #expect(signal.usedTemperature == false)
        #expect(signal.reasons.contains("ohne Hauttemperatur (R09) weniger aussagekräftig"))
    }

    @Test func oneSignalOneNightIsWatchAndFeelingIllRaisesToPattern() {
        let samples = history() + night(0, resting: 58, hrv: 46)
        let signal = InfectionWatch.assess(input(samples))
        #expect(signal.level == .watch)
        #expect(signal.sentence == "Ein Wert lag heute Nacht außerhalb deines üblichen Bereichs. Ich behalte das im Blick.")
        let sick = InfectionWatch.assess(input(samples, feelsSick: true))
        #expect(sick.level == .pattern)
        #expect(sick.sentence.contains("Das ist keine Diagnose."))
    }

    @Test func twoNightsRestingUpAndHRVDownIsPattern() {
        let samples = history(from: 2) + night(-1, resting: 60, hrv: 32) + night(0, resting: 61, hrv: 31)
        let signal = InfectionWatch.assess(input(samples))
        #expect(signal.level == .pattern)
        #expect(signal.sentence.hasPrefix("Ruhepuls seit 2 Nächten über deinem üblichen Bereich, HRV darunter. "
            + "So ein Muster zeigt sich manchmal bei Infekten, Stress, Alkohol oder Schlafmangel. Geh es heute ruhiger an."))
        #expect(signal.reasons.contains("Ruhepuls 2 Nächte über deinem üblichen Bereich"))
        #expect(!signal.sentence.contains("nicht krank"))
    }

    @Test func temperatureCanCompleteThePattern() {
        let samples = history(from: 2) + night(-1, resting: 60, hrv: 46) + night(0, resting: 60, hrv: 46, skinDeviation: 0.8)
        let signal = InfectionWatch.assess(input(samples))
        #expect(signal.level == .pattern)
        #expect(signal.usedTemperature)
        #expect(signal.sentence.contains("Hauttemperatur erhöht"))
        #expect(!signal.sentence.contains("HRV darunter"))
    }

    @Test func threeNightsAskForClarification() {
        let samples = history(from: 3) + night(-2, resting: 60, hrv: 32) + night(-1, resting: 61, hrv: 31)
            + night(0, resting: 62, hrv: 30)
        let signal = InfectionWatch.assess(input(samples))
        #expect(signal.level == .clarify)
        #expect(signal.sentence.hasPrefix("Ruhepuls seit 3 Nächten über deinem üblichen Bereich, HRV darunter."))
        #expect(signal.sentence.contains("lass es bitte ärztlich abklären"))
    }

    @Test func stronglyRaisedRestingPulseAsksForClarification() {
        let signal = InfectionWatch.assess(input(history() + night(0, resting: 67, hrv: 46)))
        #expect(signal.level == .clarify)
        #expect(signal.sentence.contains("lass es bitte ärztlich abklären"))
    }

    @Test func tooFewNightsSayWhatIsMissing() {
        let samples = history(from: 1, through: 3) + night(0, resting: 70, hrv: 20)
        let signal = InfectionWatch.assess(input(samples))
        #expect(signal.level == .none)
        #expect(signal.sentence == "Für ein Infekt-Muster brauche ich mindestens 7 Nächte mit Ringdaten.")
        let alarm = InfectionWatch.assess(input(samples, alarmSymptoms: true))
        #expect(alarm.level == .clarify)
    }
}

@Suite("Companion – morning forecast")
struct CompanionForecastTests {
    @Test func forecastFromMedianAndIQR() throws {
        let forecast = try #require(MorningForecaster.forecast(for: today, input: input(history(), now: at(-1, 21))))
        // Last 14 nights: 50…56 twice → median 53, IQR 3.5 → 53 ± 1.75.
        #expect(forecast.restingHeartRateLow == 51)
        #expect(forecast.restingHeartRateHigh == 55)
        #expect(forecast.hrvTendency == 0)
        #expect(forecast.trainingDays == 28)
        #expect(forecast.targetDay == today)
        #expect(forecast.madeAt == at(-1, 21))
    }

    @Test func tooFewNightsGiveNoForecast() {
        #expect(MorningForecaster.forecast(for: today, input: input(history(from: 1, through: 10))) == nil)
    }

    @Test func manyStepsYesterdayShiftTheRangeByAtMostThree() throws {
        // Steps on the day before night k: 4000 + 1000 × (k mod 7), so resting rises 1 bpm per 1000 steps.
        var samples = history()
        for back in 1...28 {
            samples.append(sample(.steps, 4_000 + 1_000 * Double(back % 7), at(-back - 1, 12)))
        }
        samples.append(sample(.steps, 12_000, at(-1, 12)))
        let forecast = try #require(MorningForecaster.forecast(for: today, input: input(samples, now: at(-1, 21))))
        // 53 + clamp(0.001 × (12000 − 7000), 3) = 56 → 54.25…57.75.
        #expect(forecast.restingHeartRateLow == 54)
        #expect(forecast.restingHeartRateHigh == 58)
    }

    @Test func evaluateHitAndMiss() throws {
        let context = input(history())
        let forecast = try #require(MorningForecaster.forecast(for: today, input: context))
        let hit = MorningForecaster.evaluate(forecast, night: summary(resting: 53, hrv: 46), input: context)
        #expect(hit.restingHeartRateHit == true)
        #expect(hit.sentence == "Gestern Abend tippte ich auf 51–55 Schläge, gemessen 53: Treffer.")
        #expect(hit.actualHRVTendency == 0)
        #expect(hit.hrvHit == true)
        let miss = MorningForecaster.evaluate(forecast, night: summary(resting: 63, hrv: 30), input: context)
        #expect(miss.restingHeartRateHit == false)
        #expect(miss.sentence == "Gestern Abend tippte ich auf 51–55 Schläge, gemessen 63: daneben.")
        #expect(miss.hrvHit == false)
        let none = MorningForecaster.evaluate(forecast, night: summary(resting: nil, hrv: nil, hrvKind: nil), input: context)
        #expect(none.restingHeartRateHit == nil)
    }

    @Test func hitRateCountsCheckedOutcomesOnly() {
        let forecast = MorningForecast(targetDay: today, madeAt: at(-1, 21), restingHeartRateLow: 51,
                                       restingHeartRateHigh: 55, hrvTendency: nil, trainingDays: 20)
        func outcome(_ hit: Bool?) -> ForecastOutcome {
            ForecastOutcome(forecast: forecast, actualRestingHeartRate: nil, actualHRVTendency: nil,
                            restingHeartRateHit: hit, hrvHit: nil, sentence: "")
        }
        #expect(MorningForecaster.hitRate([]) == nil)
        #expect(MorningForecaster.hitRate([outcome(nil)]) == nil)
        let rate = MorningForecaster.hitRate([outcome(true), outcome(false), outcome(true), outcome(nil)])
        #expect(rate == 2.0 / 3.0)
    }
}

@Suite("Companion – body pace")
struct CompanionBodyPaceTests {
    @Test func paceFromRestingStepsAndSleep() throws {
        var samples = history()
        for back in 1...20 { samples.append(sample(.steps, 9_000, at(-back, 12))) }
        let result = try #require(BodyPace.estimate(input(samples, birthYear: 1979)))
        // Resting median 53 → −1.75; steps 9000 → −0.8; sleep median 7.6 h → +0.1; total −2.45 → −2.
        #expect(result.calendarAge == 47)
        #expect(result.paceAge == 45)
        #expect(result.label == .c)
        #expect(result.components.map(\.name) == ["Ruhepuls", "Schritte", "Schlaf"])
        #expect(result.sentence == "Dein Körper-Tempo liegt bei etwa 45 Jahren (Kalenderalter 47). "
            + "Grobe Annäherung aus Ruhepuls, Schritten und Schlaf, keine medizinische Aussage.")
    }

    @Test func noBirthYearOrTooFewNightsGiveNothing() {
        #expect(BodyPace.estimate(input(history())) == nil)
        #expect(BodyPace.estimate(input(history(from: 1, through: 10), birthYear: 1979)) == nil)
    }
}
