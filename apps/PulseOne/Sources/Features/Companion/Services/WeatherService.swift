import Foundation
import PulseCore

/// Weather, air quality and place search from Open-Meteo (free, no key, CC BY 4.0; attribution shown by the UI).
/// Requests carry only the coordinates or the typed place name, never health data. No location permission:
/// the place is entered by hand. Snapshots are cached for one hour per place.
actor WeatherService {
    enum ServiceError: Error {
        case http(Int)
        case invalidPlace
    }

    private struct CacheEntry {
        let storedAt: Date
        let snapshot: WeatherSnapshot
    }

    static let cacheLifetime: TimeInterval = 3600

    private let session: URLSession
    private var cache: [String: CacheEntry] = [:]

    init(session: URLSession = .shared) {
        self.session = session
    }

    func snapshot(for place: GeoPlace) async throws -> WeatherSnapshot {
        try await snapshot(placeName: place.name, latitude: place.latitude, longitude: place.longitude)
    }

    /// Forecast plus air quality/pollen. An air-quality failure is not fatal (the snapshot comes without it).
    func snapshot(placeName: String, latitude: Double, longitude: Double, now: Date = Date()) async throws -> WeatherSnapshot {
        guard (-90...90).contains(latitude), (-180...180).contains(longitude) else { throw ServiceError.invalidPlace }
        let key = Self.cacheKey(latitude: latitude, longitude: longitude)
        if let entry = cache[key], now.timeIntervalSince(entry.storedAt) < Self.cacheLifetime, entry.storedAt <= now {
            return entry.snapshot
        }
        let forecastData = try await load(OpenMeteo.forecastURL(latitude: latitude, longitude: longitude))
        var snapshot = try OpenMeteo.parseForecast(forecastData, placeName: placeName)
        do {
            let airData = try await load(OpenMeteo.airQualityURL(latitude: latitude, longitude: longitude))
            snapshot = try OpenMeteo.parseAirQuality(airData, into: snapshot)
        } catch {
            // Air quality and pollen are optional extras; the weather alone is still useful.
        }
        cache[key] = CacheEntry(storedAt: now, snapshot: snapshot)
        return snapshot
    }

    /// Place search by name (German results). Empty input → no request.
    func search(_ name: String) async throws -> [GeoPlace] {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2, let url = OpenMeteo.geocodingURL(name: trimmed) else { return [] }
        return try OpenMeteo.parseGeocoding(try await load(url))
    }

    func clearCache() {
        cache.removeAll()
    }

    private func load(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw ServiceError.http(http.statusCode)
        }
        return data
    }

    /// Coordinates rounded to about 1 km, so tiny differences share one cache entry.
    static func cacheKey(latitude: Double, longitude: Double) -> String {
        let lat = Int((latitude * 100).rounded())
        let lon = Int((longitude * 100).rounded())
        return "\(lat),\(lon)"
    }
}
