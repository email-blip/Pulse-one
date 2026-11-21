import Foundation

/// One companion run: night → signals → day type → forecast check → weather → day rhythm → quick actions → briefing.
/// Pure function over `CompanionInput`; the app gathers the input and stores the result.
public enum CompanionEngine {
    public static func run(_ input: CompanionInput) -> CompanionDay {
        let calendar = input.calendar
        let night = NightAnalyzer.summarize(input)
        let infection = InfectionWatch.assess(input)
        let dayType = DayTypeClassifier.classify(night: night, infection: infection,
                                                 sleepNeedHours: input.preferences.sleepNeedHours)

        // Yesterday's forecast is only checked against the day it was made for.
        let outcome: ForecastOutcome?
        if let pending = input.pendingForecast, calendar.isDate(pending.targetDay, inSameDayAs: input.now) {
            outcome = MorningForecaster.evaluate(pending, night: night, input: input)
        } else {
            outcome = nil
        }

        let todayStart = calendar.startOfDay(for: input.now)
        let tomorrowStart = calendar.date(byAdding: .day, value: 1, to: todayStart) ?? todayStart.addingTimeInterval(86_400)
        let nextForecast = MorningForecaster.forecast(for: tomorrowStart, input: input)

        let bodyPace = BodyPace.estimate(input)
        let bodyWeather: BodyWeatherReport?
        if let weather = input.weather {
            bodyWeather = BodyWeather.report(weather, now: input.now, calendar: calendar, findings: input.findings)
        } else {
            bodyWeather = nil
        }

        let wake = night.wake.time ?? input.confirmedWake ?? input.now
        let nudges = DayRhythmPlanner.plan(wake: wake, dayType: dayType, night: night, weather: bodyWeather,
                                           preferences: input.preferences, now: input.now, calendar: calendar)

        let dayGuard = input.dayGuard(dayType: dayType, infection: infection.level)
        let actions = QuickActionPicker.pick(dayType: dayType, night: night, weather: input.weather,
                                             preferences: input.preferences, now: input.now, calendar: calendar,
                                             dayGuard: dayGuard)

        let parts = BriefingParts(night: night, dayType: dayType, infection: infection, forecastOutcome: outcome,
                                  bodyPace: bodyPace, bodyWeather: bodyWeather, actions: actions,
                                  topFinding: input.findings.first)
        let briefing = MorningBriefingComposer.compose(day: parts, preferences: input.preferences, now: input.now,
                                                       calendar: calendar)

        return CompanionDay(night: night, dayType: dayType, infection: infection, forecastOutcome: outcome,
                            nextForecast: nextForecast, bodyPace: bodyPace, bodyWeather: bodyWeather,
                            nudges: nudges, briefing: briefing)
    }
}
