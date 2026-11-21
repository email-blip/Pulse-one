import Foundation

// Open-Meteo request URLs and response parsers (pure, no I/O). The app's `WeatherService` fetches the
// data; this file only builds URLs and turns JSON into `WeatherSnapshot`. Coordinates are rounded to
// two decimals (about 1 km) before they leave the device.

/// A place found by the Open-Meteo geocoding search.
public struct GeoPlace: Codable, Equatable, Sendable, Identifiable {
    public let id: Int
    public let name: String
    /// State / region, e.g. "Bayern".
    public let admin1: String?
    public let country: String?
    public let latitude: Double
    public let longitude: Double

    public init(id: Int, name: String, admin1: String?, country: String?, latitude: Double, longitude: Double) {
        self.id = id
        self.name = name
        self.admin1 = admin1
        self.country = country
        self.latitude = latitude
        self.longitude = longitude
    }
}

public enum OpenMeteo {
    public static let forecastEndpoint = "https://api.open-meteo.com/v1/forecast"
    public static let airQualityEndpoint = "https://air-quality-api.open-meteo.com/v1/air-quality"
    public static let geocodingEndpoint = "https://geocoding-api.open-meteo.com/v1/search"

    static let hourlyForecastVariables = "temperature_2m,apparent_temperature,precipitation_probability,wind_speed_10m,uv_index,relative_humidity_2m,surface_pressure"
    static let hourlyAirQualityVariables = "european_aqi,birch_pollen,grass_pollen,alder_pollen,mugwort_pollen,ragweed_pollen"

    /// German pollen names used as keys in `WeatherSnapshot.pollen`.
    public static let pollenNames: [String] = ["Birke", "Gräser", "Erle", "Beifuß", "Ambrosia"]

    // MARK: URLs

    public static func forecastURL(latitude: Double, longitude: Double) -> URL {
        makeURL(forecastEndpoint, [
            URLQueryItem(name: "latitude", value: coordinate(latitude)),
            URLQueryItem(name: "longitude", value: coordinate(longitude)),
            URLQueryItem(name: "hourly", value: hourlyForecastVariables),
            URLQueryItem(name: "daily", value: "sunrise,sunset"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "forecast_days", value: "2"),
            URLQueryItem(name: "timeformat", value: "unixtime")
        ])
    }

    public static func airQualityURL(latitude: Double, longitude: Double) -> URL {
        makeURL(airQualityEndpoint, [
            URLQueryItem(name: "latitude", value: coordinate(latitude)),
            URLQueryItem(name: "longitude", value: coordinate(longitude)),
            URLQueryItem(name: "hourly", value: hourlyAirQualityVariables),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "forecast_days", value: "1"),
            URLQueryItem(name: "timeformat", value: "unixtime")
        ])
    }

    /// Search URL for a place name; nil when the trimmed name is shorter than 2 characters.
    public static func geocodingURL(name: String) -> URL? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2, var components = URLComponents(string: geocodingEndpoint) else { return nil }
        components.queryItems = [
            URLQueryItem(name: "name", value: trimmed),
            URLQueryItem(name: "count", value: "5"),
            URLQueryItem(name: "language", value: "de"),
            URLQueryItem(name: "format", value: "json")
        ]
        return components.url
    }

    /// Coordinate rounded to 2 decimals (privacy, ~1 km), written with a dot and without "-0.00".
    static func coordinate(_ value: Double) -> String {
        let rounded = (value * 100).rounded() / 100
        if rounded == 0 { return "0.00" }
        return String(format: "%.2f", rounded)
    }

    private static func makeURL(_ endpoint: String, _ items: [URLQueryItem]) -> URL {
        if var components = URLComponents(string: endpoint) {
            components.queryItems = items
            if let url = components.url { return url }
        }
        // Unreachable with the constant endpoints above; keeps the signature non-optional without a force unwrap.
        return URL(fileURLWithPath: "/")
    }

    // MARK: Parsers

    /// Parses a forecast response requested with `timeformat=unixtime`. Hours without a temperature are
    /// skipped; a missing apparent temperature falls back to the temperature. `fetchedAt` is the parse time.
    public static func parseForecast(_ data: Data, placeName: String) throws -> WeatherSnapshot {
        let dto = try JSONDecoder().decode(ForecastDTO.self, from: data)
        let hourly = dto.hourly
        var hours: [WeatherHour] = []
        for (index, seconds) in hourly.time.enumerated() {
            guard let temperature = value(hourly.temperature, index) else { continue }
            hours.append(WeatherHour(
                time: Date(timeIntervalSince1970: TimeInterval(seconds)),
                temperature: temperature,
                apparentTemperature: value(hourly.apparentTemperature, index) ?? temperature,
                precipitationProbability: value(hourly.precipitationProbability, index),
                windSpeed: value(hourly.windSpeed, index),
                uvIndex: value(hourly.uvIndex, index),
                relativeHumidity: value(hourly.relativeHumidity, index),
                surfacePressure: value(hourly.surfacePressure, index)))
        }
        let sunrise = dto.daily?.sunrise?.first.map { Date(timeIntervalSince1970: TimeInterval($0)) }
        let sunset = dto.daily?.sunset?.first.map { Date(timeIntervalSince1970: TimeInterval($0)) }
        return WeatherSnapshot(placeName: placeName, latitude: dto.latitude ?? 0, longitude: dto.longitude ?? 0,
                               fetchedAt: Date(), hours: hours, sunrise: sunrise, sunset: sunset)
    }

    /// Adds today's maximum European AQI and the daily maximum per pollen type (German keys) to a snapshot.
    /// Pollen types without any value are left out; without any AQI value the snapshot's AQI is kept.
    public static func parseAirQuality(_ data: Data, into snapshot: WeatherSnapshot) throws -> WeatherSnapshot {
        let dto = try JSONDecoder().decode(AirQualityDTO.self, from: data)
        let hourly = dto.hourly
        let aqi = maximum(hourly.europeanAQI)
        var pollen: [String: Double] = [:]
        if let peak = maximum(hourly.birch) { pollen["Birke"] = peak }
        if let peak = maximum(hourly.grass) { pollen["Gräser"] = peak }
        if let peak = maximum(hourly.alder) { pollen["Erle"] = peak }
        if let peak = maximum(hourly.mugwort) { pollen["Beifuß"] = peak }
        if let peak = maximum(hourly.ragweed) { pollen["Ambrosia"] = peak }
        return WeatherSnapshot(placeName: snapshot.placeName, latitude: snapshot.latitude, longitude: snapshot.longitude,
                               fetchedAt: snapshot.fetchedAt, hours: snapshot.hours, sunrise: snapshot.sunrise,
                               sunset: snapshot.sunset, europeanAQI: aqi ?? snapshot.europeanAQI, pollen: pollen)
    }

    /// Places from a geocoding response; a response without "results" means no match.
    public static func parseGeocoding(_ data: Data) throws -> [GeoPlace] {
        try JSONDecoder().decode(GeocodingDTO.self, from: data).results ?? []
    }

    private static func value(_ array: [Double?]?, _ index: Int) -> Double? {
        guard let array, index < array.count else { return nil }
        return array[index]
    }

    private static func maximum(_ array: [Double?]?) -> Double? {
        guard let array else { return nil }
        return array.compactMap { $0 }.max()
    }
}

// MARK: - Response DTOs

private struct ForecastDTO: Decodable {
    struct Hourly: Decodable {
        let time: [Int]
        let temperature: [Double?]?
        let apparentTemperature: [Double?]?
        let precipitationProbability: [Double?]?
        let windSpeed: [Double?]?
        let uvIndex: [Double?]?
        let relativeHumidity: [Double?]?
        let surfacePressure: [Double?]?

        enum CodingKeys: String, CodingKey {
            case time
            case temperature = "temperature_2m"
            case apparentTemperature = "apparent_temperature"
            case precipitationProbability = "precipitation_probability"
            case windSpeed = "wind_speed_10m"
            case uvIndex = "uv_index"
            case relativeHumidity = "relative_humidity_2m"
            case surfacePressure = "surface_pressure"
        }
    }

    struct Daily: Decodable {
        let sunrise: [Int]?
        let sunset: [Int]?
    }

    let latitude: Double?
    let longitude: Double?
    let hourly: Hourly
    let daily: Daily?
}

private struct AirQualityDTO: Decodable {
    struct Hourly: Decodable {
        let europeanAQI: [Double?]?
        let birch: [Double?]?
        let grass: [Double?]?
        let alder: [Double?]?
        let mugwort: [Double?]?
        let ragweed: [Double?]?

        enum CodingKeys: String, CodingKey {
            case europeanAQI = "european_aqi"
            case birch = "birch_pollen"
            case grass = "grass_pollen"
            case alder = "alder_pollen"
            case mugwort = "mugwort_pollen"
            case ragweed = "ragweed_pollen"
        }
    }

    let hourly: Hourly
}

private struct GeocodingDTO: Decodable {
    let results: [GeoPlace]?
}
