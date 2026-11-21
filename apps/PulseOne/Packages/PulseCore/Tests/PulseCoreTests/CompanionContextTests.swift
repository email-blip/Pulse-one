import Foundation
import Testing
@testable import PulseCore

// Begleiter T2 – weather (Open-Meteo), clothing, body weather, night researcher, day rhythm.

private let ctxCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Berlin") ?? TimeZone(secondsFromGMT: 3_600) ?? .current
    return calendar
}()

private func ctxDate(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
    ctxCalendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute)) ?? .distantPast
}

private func ctxHour(_ hour: Int, temp: Double, apparent: Double? = nil, rain: Double? = 0, wind: Double? = 5,
                     uv: Double? = 1, humidity: Double? = 60, pressure: Double? = 1_015) -> WeatherHour {
    WeatherHour(time: ctxDate(21, hour), temperature: temp, apparentTemperature: apparent ?? temp,
                precipitationProbability: rain, windSpeed: wind, uvIndex: uv, relativeHumidity: humidity,
                surfacePressure: pressure)
}

private func ctxSnapshot(_ hours: [WeatherHour], aqi: Double? = nil, pollen: [String: Double] = [:]) -> WeatherSnapshot {
    WeatherSnapshot(placeName: "Teststadt", latitude: 52.52, longitude: 13.41, fetchedAt: ctxDate(21, 6), hours: hours,
                    sunrise: nil, sunset: nil, europeanAQI: aqi, pollen: pollen)
}

private func ctxQuery(_ url: URL?) -> [String: String] {
    guard let url, let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { return [:] }
    var result: [String: String] = [:]
    for item in items { result[item.name] = item.value ?? "" }
    return result
}

private func ctxSample(_ kind: SampleKind, _ value: Double, at start: Date, end: Date? = nil,
                       source: DataSourceKind = .colmiRing) -> HealthSample {
    HealthSample(profileID: nil, kind: kind, value: value, unit: kind.canonicalUnit, start: start,
                 end: end ?? (kind.aggregation == .point ? start : start.addingTimeInterval(60)),
                 timeZoneIdentifier: "Europe/Berlin", source: source, deviceID: source == .colmiRing ? "ring" : "watch",
                 originalSampleID: UUID().uuidString, importedAt: ctxDate(21, 12), quality: .valid,
                 method: source == .colmiRing ? .deviceHistory : .healthStore)
}

private func ctxNight(wake: Date) -> NightSummary {
    NightSummary(sleepStart: nil, wake: WakeEstimate(time: wake, method: .confirmed, confidence: 1), sleepDuration: nil,
                 sleepDurationIsEstimated: false, nightRestingHeartRate: nil, lowestHeartRate: nil, hrv: nil, hrvKind: nil,
                 spo2Average: nil, restingHeartRatePosition: nil, hrvPosition: nil, sleepPosition: nil,
                 morningHeartRate: nil, missing: [])
}

@Suite("Begleiter – Open-Meteo")
struct CompanionOpenMeteoTests {
    @Test func forecastURLRoundsCoordinatesAndAsksForUnixTime() {
        let url = OpenMeteo.forecastURL(latitude: 52.523_44, longitude: -13.406_1)
        #expect(url.absoluteString.hasPrefix("https://api.open-meteo.com/v1/forecast?"))
        let query = ctxQuery(url)
        #expect(query["latitude"] == "52.52")
        #expect(query["longitude"] == "-13.41")
        #expect(query["hourly"] == "temperature_2m,apparent_temperature,precipitation_probability,wind_speed_10m,uv_index,relative_humidity_2m,surface_pressure")
        #expect(query["daily"] == "sunrise,sunset")
        #expect(query["timezone"] == "auto")
        #expect(query["forecast_days"] == "2")
        #expect(query["timeformat"] == "unixtime")
        #expect(OpenMeteo.coordinate(-0.001) == "0.00")
    }

    @Test func airQualityAndGeocodingURLs() {
        let air = OpenMeteo.airQualityURL(latitude: 48.137_1, longitude: 11.575_4)
        #expect(air.absoluteString.hasPrefix("https://air-quality-api.open-meteo.com/v1/air-quality?"))
        let airQuery = ctxQuery(air)
        #expect(airQuery["latitude"] == "48.14")
        #expect(airQuery["longitude"] == "11.58")
        #expect(airQuery["hourly"] == "european_aqi,birch_pollen,grass_pollen,alder_pollen,mugwort_pollen,ragweed_pollen")
        #expect(airQuery["forecast_days"] == "1")
        #expect(airQuery["timeformat"] == "unixtime")

        #expect(OpenMeteo.geocodingURL(name: "  a ") == nil)
        let geo = OpenMeteo.geocodingURL(name: " München ")
        #expect(geo?.absoluteString.hasPrefix("https://geocoding-api.open-meteo.com/v1/search?") == true)
        let geoQuery = ctxQuery(geo)
        #expect(geoQuery["name"] == "München")
        #expect(geoQuery["count"] == "5")
        #expect(geoQuery["language"] == "de")
        #expect(geoQuery["format"] == "json")
    }

    @Test func parsesForecastWithNulls() throws {
        let json = """
        {"latitude":52.52,"longitude":13.42,"timezone":"Europe/Berlin",
         "hourly":{"time":[1795255200,1795258800,1795262400],
                   "temperature_2m":[5.5,null,7.0],
                   "apparent_temperature":[3.0,2.0,null],
                   "precipitation_probability":[10,20,null],
                   "wind_speed_10m":[12.0,14.0,16.0],
                   "uv_index":[0.5,1.0,1.5],
                   "relative_humidity_2m":[80,82,85],
                   "surface_pressure":[1012.3,1011.0,1010.2]},
         "daily":{"time":[1795215600,1795302000],"sunrise":[1795240000,1795326500],"sunset":[1795271000,1795357300]}}
        """
        let snapshot = try OpenMeteo.parseForecast(Data(json.utf8), placeName: "Berlin")
        #expect(snapshot.placeName == "Berlin")
        #expect(snapshot.latitude == 52.52)
        #expect(snapshot.hours.count == 2)
        let first = try #require(snapshot.hours.first)
        #expect(first.time == Date(timeIntervalSince1970: 1_795_255_200))
        #expect(first.temperature == 5.5)
        #expect(first.apparentTemperature == 3.0)
        #expect(first.precipitationProbability == 10)
        #expect(first.surfacePressure == 1012.3)
        let last = try #require(snapshot.hours.last)
        #expect(last.apparentTemperature == 7.0)
        #expect(last.precipitationProbability == nil)
        #expect(snapshot.sunrise == Date(timeIntervalSince1970: 1_795_240_000))
        #expect(snapshot.sunset == Date(timeIntervalSince1970: 1_795_271_000))
    }

    @Test func parsesAirQualityMaximaAndSkipsEmptyPollen() throws {
        let json = """
        {"hourly":{"time":[1795255200,1795258800],
                   "european_aqi":[35,62],
                   "birch_pollen":[12.5,55.0],
                   "grass_pollen":[null,3.0],
                   "alder_pollen":[null,null],
                   "mugwort_pollen":[0.0,0.0],
                   "ragweed_pollen":[null,1.0]}}
        """
        let base = ctxSnapshot([ctxHour(8, temp: 10)])
        let snapshot = try OpenMeteo.parseAirQuality(Data(json.utf8), into: base)
        #expect(snapshot.europeanAQI == 62)
        #expect(snapshot.pollen["Birke"] == 55)
        #expect(snapshot.pollen["Gräser"] == 3)
        #expect(snapshot.pollen["Erle"] == nil)
        #expect(snapshot.pollen["Beifuß"] == 0)
        #expect(snapshot.pollen["Ambrosia"] == 1)
        #expect(snapshot.hours == base.hours)
        #expect(snapshot.placeName == base.placeName)
    }

    @Test func parsesGeocodingWithAndWithoutResults() throws {
        let json = """
        {"results":[{"id":2867714,"name":"München","latitude":48.13743,"longitude":11.57549,"elevation":524.0,
                     "country_code":"DE","admin1":"Bayern","country":"Deutschland"},
                    {"id":123,"name":"Münchenbernsdorf","latitude":50.82,"longitude":11.93}],
         "generationtime_ms":0.5}
        """
        let places = try OpenMeteo.parseGeocoding(Data(json.utf8))
        #expect(places.count == 2)
        #expect(places.first == GeoPlace(id: 2_867_714, name: "München", admin1: "Bayern", country: "Deutschland",
                                         latitude: 48.137_43, longitude: 11.575_49))
        #expect(places.last?.admin1 == nil)
        #expect(try OpenMeteo.parseGeocoding(Data(#"{"generationtime_ms":0.3}"#.utf8)).isEmpty)
    }
}

@Suite("Begleiter – Kleidung und Körperwetter")
struct CompanionClothingTests {
    @Test func coldDayAsksForWinterLayers() {
        let hours = (6...22).map { ctxHour($0, temp: 1, apparent: -3 + Double($0 - 6) * 0.1) }
        let advice = ClothingAdvisor.advise(ctxSnapshot(hours), from: ctxDate(21, 6), to: ctxDate(21, 22), calendar: ctxCalendar)
        #expect(advice.items == ["Wintermantel", "Mütze", "Handschuhe"])
        #expect(advice.sentence == "Zieh heute einen Wintermantel, eine Mütze und Handschuhe an.")
    }

    @Test func rainFromThreePmInTheSentence() {
        let hours = (6...22).map { h in
            ctxHour(h, temp: 12, apparent: 9 + Double(h - 6) * 0.25, rain: h >= 15 ? 60.0 : 10.0)
        }
        let advice = ClothingAdvisor.advise(ctxSnapshot(hours), from: ctxDate(21, 6), to: ctxDate(21, 22), calendar: ctxCalendar)
        #expect(advice.items == ["leichte Jacke", "Pullover", "Regenjacke oder Schirm"])
        #expect(advice.sentence == "Zieh heute eine leichte Jacke und einen Pullover an, ab 15 Uhr Regen wahrscheinlich: Schirm mitnehmen.")
    }

    @Test func hotSunnyDayAndWideSpread() {
        let hot = (6...22).map { ctxHour($0, temp: 29, apparent: $0 < 14 ? 27.0 : 31.0, uv: 8) }
        let advice = ClothingAdvisor.advise(ctxSnapshot(hot), from: ctxDate(21, 6), to: ctxDate(21, 22), calendar: ctxCalendar)
        #expect(advice.items == ["luftige Kleidung", "Wasser mitnehmen", "Sonnenschutz"])
        #expect(advice.sentence == "Zieh heute luftige Kleidung an. Hoher UV-Index: an Sonnenschutz denken. Wasser mitnehmen.")

        let spread = (6...22).map { ctxHour($0, temp: 12, apparent: 6 + Double($0 - 6), rain: 35, wind: 40) }
        let layered = ClothingAdvisor.advise(ctxSnapshot(spread), from: ctxDate(21, 6), to: ctxDate(21, 22), calendar: ctxCalendar)
        #expect(layered.items.contains("warme Jacke"))
        #expect(layered.items.contains("Schirm zur Sicherheit"))
        #expect(layered.items.contains("winddichte Schicht"))
        #expect(layered.items.contains("Zwiebelprinzip: morgens kühl, später wärmer"))
    }

    @Test func pressureDropAndOtherBodyNotes() {
        let falling = (6...22).map { ctxHour($0, temp: 4 + Double($0 - 6) * 0.5, pressure: 1_015 - Double($0 - 6) * 0.5) }
        let finding = ResearchFinding(cause: "weather_pressure", effect: "night_resting_hr", lagDays: 0, correlation: 0.4,
                                      sampleDays: 30, adjustedP: 0.05, sentence: "Eigener Befund zum Luftdruck.", label: .c)
        let report = BodyWeather.report(ctxSnapshot(falling, aqi: 65, pollen: ["Birke": 80, "Gräser": 10]),
                                        now: ctxDate(21, 7), calendar: ctxCalendar, findings: [finding])
        #expect(report.weatherLine == "Heute 4 bis 12 Grad.")
        #expect(report.bodyNotes.contains(BodyWeather.pressureDropNote))
        #expect(report.bodyNotes.contains("Viel Birkenpollen in der Luft."))
        #expect(!report.bodyNotes.contains { $0.contains("Gräser") })
        #expect(report.bodyNotes.contains(BodyWeather.airQualityNote))
        #expect(report.bodyNotes.last == "Eigener Befund zum Luftdruck.")
        #expect(report.attribution == "Wetterdaten: Open-Meteo.com (CC BY 4.0)")

        let steady = (6...22).map { ctxHour($0, temp: 29, apparent: 30, humidity: 85) }
        let summer = BodyWeather.report(ctxSnapshot(steady), now: ctxDate(21, 7), calendar: ctxCalendar, findings: [])
        #expect(!summer.bodyNotes.contains(BodyWeather.pressureDropNote))
        #expect(summer.bodyNotes.contains(BodyWeather.heatNote))
        #expect(summer.bodyNotes.contains(BodyWeather.humidNote))
    }

    @Test func bestOutdoorWindowIsLongestDryMildRun() {
        let hours = (6...22).map { h -> WeatherHour in
            let rain: Double = (7...9).contains(h) || h == 15 ? 60 : 0
            return ctxHour(h, temp: 15, rain: rain)
        }
        let report = BodyWeather.report(ctxSnapshot(hours), now: ctxDate(21, 7), calendar: ctxCalendar, findings: [])
        #expect(report.bestOutdoorWindow == DateInterval(start: ctxDate(21, 10), end: ctxDate(21, 15)))
        #expect(report.weatherLine == "Heute um 15 Grad, ab 7 Uhr Regen wahrscheinlich.")

        let wet = (6...22).map { ctxHour($0, temp: 15, rain: 80) }
        #expect(BodyWeather.report(ctxSnapshot(wet), now: ctxDate(21, 7), calendar: ctxCalendar, findings: []).bestOutdoorWindow == nil)
    }
}

@Suite("Begleiter – Nachtforscher")
struct CompanionResearcherTests {
    @Test func spearmanUsesAverageRanksForTies() throws {
        #expect(NightResearcher.ranks([10, 20, 20, 30]) == [1, 2.5, 2.5, 4])
        let rho = try #require(NightResearcher.spearman([1, 2, 3, 4, 5], [5, 6, 7, 8, 7]))
        #expect(abs(rho - 0.820_782_7) < 1e-6)
        #expect(NightResearcher.spearman([1, 2, 3], [4, 4, 4]) == nil)
    }

    @Test func benjaminiHochbergAndStudentP() {
        let adjusted = NightResearcher.benjaminiHochberg([0.01, 0.04, 0.03, 0.005])
        let expected = [0.02, 0.04, 0.04, 0.02]
        #expect(zip(adjusted, expected).allSatisfy { abs($0 - $1) < 1e-12 })
        #expect(abs(NightResearcher.studentTwoSidedP(t: 2, df: 10) - 0.073_388) < 1e-4)
        #expect(abs(NightResearcher.studentTwoSidedP(t: 12.706, df: 1) - 0.05) < 1e-3)
        #expect(NightResearcher.pValue(rho: 0, n: 30) == 1)
    }

    private func syntheticTable(days: Int) -> [Date: [String: Double]] {
        let start = ctxCalendar.startOfDay(for: ctxDate(1, 12))
        var table: [Date: [String: Double]] = [:]
        for i in 0..<days {
            guard let day = ctxCalendar.date(byAdding: .day, value: i, to: start),
                  let next = ctxCalendar.date(byAdding: .day, value: i + 1, to: start) else { continue }
            let steps = 5_000 + 1_000 * Double((i * 7) % days)
            table[day, default: [:]]["steps"] = steps
            table[next, default: [:]]["night_resting_hr"] = 70 - steps / 1_000
        }
        return table
    }

    @Test func findsLaggedAssociationWithEnoughDays() throws {
        let findings = NightResearcher.scan(syntheticTable(days: 30), calendar: ctxCalendar)
        let top = try #require(findings.first)
        #expect(top.cause == "steps")
        #expect(top.effect == "night_resting_hr")
        #expect(top.lagDays == 1)
        #expect(top.correlation == -1)
        #expect(top.sampleDays == 30)
        #expect(top.label == .c)
        #expect(top.sentence == "An Tagen mit mehr Schritten lag dein Ruhepuls in der Nacht danach eher niedriger (ρ = −1,00, 30 Tage). Das ist ein Zusammenhang, kein Beweis.")
        #expect(findings.count <= 5)
    }

    @Test func noFindingsBelowMinimumDays() {
        #expect(NightResearcher.scan(syntheticTable(days: 20), calendar: ctxCalendar).isEmpty)
    }

    @Test func dailyTableBuildsNightRestingPulseSleepAndOneHRVKind() {
        let samples = [
            ctxSample(.heartRate, 60, at: ctxDate(21, 1)), ctxSample(.heartRate, 62, at: ctxDate(21, 1, 10)),
            ctxSample(.heartRate, 52, at: ctxDate(21, 2)), ctxSample(.heartRate, 54, at: ctxDate(21, 2, 30)),
            ctxSample(.heartRate, 55, at: ctxDate(21, 3)), ctxSample(.heartRate, 90, at: ctxDate(21, 10)),
            ctxSample(.heartRate, 58, at: ctxDate(20, 1)), ctxSample(.heartRate, 57, at: ctxDate(20, 2)),
            ctxSample(.sleepDuration, 8 * 3_600, at: ctxDate(20, 23), end: ctxDate(21, 7)),
            ctxSample(.ringHRV, 45, at: ctxDate(21, 3)), ctxSample(.ringHRV, 40, at: ctxDate(20, 3)),
            ctxSample(.heartRateVariability, 30, at: ctxDate(21, 4), source: .appleHealth),
            ctxSample(.steps, 8_000, at: ctxDate(21, 10))
        ]
        let result = NightResearcher.dailyTable(samples, calendar: ctxCalendar)
        let day21 = ctxCalendar.startOfDay(for: ctxDate(21, 12))
        let day20 = ctxCalendar.startOfDay(for: ctxDate(20, 12))
        #expect(result[day21]?["night_resting_hr"] == 53)
        #expect(result[day20]?["night_resting_hr"] == nil)
        #expect(result[day21]?["sleep_hours"] == 8)
        #expect(result[day20]?["sleep_hours"] == nil)
        #expect(result[day21]?["hrv"] == 45)
        #expect(result[day20]?["hrv"] == 40)
        #expect(result[day21]?["steps"] == 8_000)
        #expect(result[day21]?["training_minutes"] == 0)
        #expect(NightResearcher.columnTitle("night_resting_hr") == "Ruhepuls in der Nacht")
    }
}

@Suite("Begleiter – Tagesrhythmus")
struct CompanionDayRhythmTests {
    private func preferences(max: Int = 20, quietStart: Int = 23, quietEnd: Int = 5) -> CompanionPreferences {
        CompanionPreferences(maxNudgesPerDay: max, quietStartHour: quietStart, quietEndHour: quietEnd)
    }

    @Test func quietHoursWrapPastMidnight() {
        let wrap = CompanionPreferences(quietStartHour: 22, quietEndHour: 7)
        #expect(DayRhythmPlanner.isQuiet(ctxDate(21, 23), preferences: wrap, calendar: ctxCalendar))
        #expect(DayRhythmPlanner.isQuiet(ctxDate(21, 3), preferences: wrap, calendar: ctxCalendar))
        #expect(!DayRhythmPlanner.isQuiet(ctxDate(21, 7), preferences: wrap, calendar: ctxCalendar))
        #expect(!DayRhythmPlanner.isQuiet(ctxDate(21, 21, 59), preferences: wrap, calendar: ctxCalendar))
        let plain = CompanionPreferences(quietStartHour: 13, quietEndHour: 15)
        #expect(DayRhythmPlanner.isQuiet(ctxDate(21, 14), preferences: plain, calendar: ctxCalendar))
        #expect(!DayRhythmPlanner.isQuiet(ctxDate(21, 15), preferences: plain, calendar: ctxCalendar))

        let wake = ctxDate(21, 6)
        let nudges = DayRhythmPlanner.plan(wake: wake, dayType: .normal, night: ctxNight(wake: wake), weather: nil,
                                           preferences: preferences(quietStart: 22, quietEnd: 7), now: wake, calendar: ctxCalendar)
        let kinds = nudges.map(\.kind)
        #expect(!kinds.contains(.daylight))
        #expect(!kinds.contains(.breakfast))
        // Bedtime (22:00) and wind-down are exempt from quiet hours; everything else stays inside 7–22.
        #expect(kinds.contains(.bedtime))
        #expect(kinds.contains(.windDown))
        #expect(nudges.filter { $0.kind != .bedtime && $0.kind != .windDown }
            .allSatisfy { (7..<22).contains(ctxCalendar.component(.hour, from: $0.time)) })
        #expect(nudges.map(\.time) == nudges.map(\.time).sorted())
    }

    @Test func capKeepsPriorityAndSortsByTime() {
        let wake = ctxDate(21, 6, 30)
        let nudges = DayRhythmPlanner.plan(wake: wake, dayType: .recovered, night: ctxNight(wake: wake), weather: nil,
                                           preferences: preferences(max: 3), now: wake, calendar: ctxCalendar)
        #expect(nudges.map(\.kind) == [.sportWindow, .windDown, .bedtime])
        #expect(nudges.first?.time == ctxDate(21, 17, 30))
        #expect(nudges.last?.time == ctxDate(21, 22, 30))
        #expect(nudges.last?.id == "companion.bedtime.20261121")
    }

    @Test func shortNightGetsNapAndEarlierBedtime() throws {
        let wake = ctxDate(21, 6, 30)
        let nudges = DayRhythmPlanner.plan(wake: wake, dayType: .shortNight, night: ctxNight(wake: wake), weather: nil,
                                           preferences: preferences(), now: wake, calendar: ctxCalendar)
        let nap = try #require(nudges.first { $0.kind == .nap })
        #expect(nap.time == ctxDate(21, 13, 30))
        #expect(nap.id == "companion.nap.20261121")
        #expect(nap.body.contains("10–20 Minuten hinlegen, Wecker stellen"))
        #expect(nudges.first { $0.kind == .bedtime }?.time == ctxDate(21, 22))
        #expect(nudges.first { $0.kind == .sportWindow }?.title == "Leichte Bewegung")
    }

    @Test func recoveredDayHasNoNapAndUsesWeatherWindow() {
        let wake = ctxDate(21, 6, 30)
        let report = BodyWeatherReport(weatherLine: "", clothing: ClothingAdvice(items: [], sentence: ""),
                                       bodyNotes: [BodyWeather.heatNote],
                                       bestOutdoorWindow: DateInterval(start: ctxDate(21, 11), end: ctxDate(21, 14)))
        let nudges = DayRhythmPlanner.plan(wake: wake, dayType: .recovered, night: ctxNight(wake: wake), weather: report,
                                           preferences: preferences(), now: wake, calendar: ctxCalendar)
        #expect(!nudges.contains { $0.kind == .nap })
        #expect(nudges.first { $0.kind == .sportWindow }?.time == ctxDate(21, 11))
        #expect(nudges.first { $0.kind == .hydration }?.time == ctxDate(21, 10, 30))
        #expect(nudges.first { $0.kind == .caffeineCutoff }?.time == ctxDate(21, 14, 30))
    }

    @Test func onlyFutureTimesAndCaffeineOptOut() {
        let wake = ctxDate(21, 6, 30)
        var prefs = preferences()
        prefs.allowsCaffeineTips = false
        let nudges = DayRhythmPlanner.plan(wake: wake, dayType: .normal, night: ctxNight(wake: wake), weather: nil,
                                           preferences: prefs, now: ctxDate(21, 12), calendar: ctxCalendar)
        #expect(nudges.allSatisfy { $0.time > ctxDate(21, 12) })
        #expect(!nudges.contains { $0.kind == .caffeineCutoff })
        #expect(nudges.contains { $0.kind == .lunch && $0.time == ctxDate(21, 12, 30) })
    }
}
