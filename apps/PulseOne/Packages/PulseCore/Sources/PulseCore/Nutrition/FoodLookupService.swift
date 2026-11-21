import Foundation

/// Online food lookup: Open Food Facts for barcodes and branded products, USDA for generic foods.
/// Transport is injected so tests run without network. Caching lives in the app (SwiftData).
public actor FoodLookupService {
    public typealias Transport = @Sendable (URLRequest) async throws -> (Data, Int)

    public enum LookupError: Error, Equatable, Sendable {
        case invalidBarcode
        case rateLimited(retryAfter: TimeInterval)
        case http(status: Int)
        case unreachable
        case malformed
    }

    public struct SearchResults: Sendable {
        public var items: [FoodItem]
        /// Sources that could not answer, with a German reason for the screen.
        public var problems: [String]

        public init(items: [FoodItem], problems: [String]) {
            self.items = items
            self.problems = problems
        }
    }

    private let transport: Transport
    private let userAgent: String
    private let clock: @Sendable () -> Date
    private var usdaKey: String?
    private var productLimiter = SlidingWindowLimiter(limit: OpenFoodFacts.productLimit, window: 60)
    private var searchLimiter = SlidingWindowLimiter(limit: OpenFoodFacts.searchLimit, window: 60)
    private var usdaLimiter: SlidingWindowLimiter

    public init(appVersion: String, usdaKey: String? = nil,
                clock: @escaping @Sendable () -> Date = { Date() },
                transport: @escaping Transport = FoodLookupService.urlSessionTransport) {
        self.transport = transport
        self.userAgent = OpenFoodFacts.userAgent(appVersion: appVersion)
        self.clock = clock
        self.usdaKey = usdaKey
        self.usdaLimiter = SlidingWindowLimiter(limit: USDAFoodData.hourlyLimit(apiKey: usdaKey), window: 3_600)
    }

    public func setUSDAKey(_ key: String?) {
        let newLimit = USDAFoodData.hourlyLimit(apiKey: key)
        if newLimit != usdaLimiter.limit { usdaLimiter = SlidingWindowLimiter(limit: newLimit, window: 3_600) }
        usdaKey = key
    }

    public func lookup(barcode raw: String) async throws -> OpenFoodFacts.LookupResult {
        guard let code = Barcode.normalized(raw), let url = OpenFoodFacts.productURL(barcode: code) else {
            throw LookupError.invalidBarcode
        }
        let now = clock()
        guard productLimiter.tryAcquire(now: now) else {
            throw LookupError.rateLimited(retryAfter: productLimiter.retryAfter(now: now))
        }
        let (data, status) = try await send(url)
        // OFF answers 404 with a JSON body for unknown products.
        guard status == 200 || status == 404 else { throw LookupError.http(status: status) }
        do {
            return try OpenFoodFacts.parseProduct(data, barcode: code, fetchedAt: now)
        } catch {
            if status == 404 { return .notFound }
            throw LookupError.malformed
        }
    }

    /// Searches both databases. One failing source does not hide the other's results.
    public func search(_ query: String) async -> SearchResults {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard term.count >= 2 else { return SearchResults(items: [], problems: []) }
        var items: [FoodItem] = []
        var problems: [String] = []
        let now = clock()

        // Generic foods first: a known German term goes to USDA in English.
        let english = FoodTranslation.english(for: term)
        let usdaQuery = english ?? term
        if usdaLimiter.tryAcquire(now: now), let url = USDAFoodData.searchURL(query: usdaQuery, apiKey: usdaKey) {
            do {
                let (data, status) = try await send(url, sendUserAgent: false)
                if status == 200 {
                    let germanName = english == nil ? nil : term.capitalized(with: Locale(identifier: "de_DE"))
                    items += try USDAFoodData.parseSearch(data, germanName: germanName, fetchedAt: now).prefix(english == nil ? 5 : 8)
                } else {
                    problems.append(status == 429 ? "USDA: Abfragegrenze erreicht" : "USDA antwortet nicht (\(status))")
                }
            } catch {
                problems.append("USDA nicht erreichbar")
            }
        } else {
            problems.append("USDA: Abfragegrenze für diese Stunde erreicht")
        }

        if searchLimiter.tryAcquire(now: now), let url = OpenFoodFacts.searchURL(query: term) {
            do {
                let (data, status) = try await send(url)
                if status == 200 {
                    items += try OpenFoodFacts.parseSearch(data, fetchedAt: now)
                } else {
                    problems.append(status == 429 ? "Open Food Facts: Abfragegrenze erreicht" : "Open Food Facts antwortet nicht (\(status))")
                }
            } catch {
                problems.append("Open Food Facts nicht erreichbar")
            }
        } else {
            let wait = Int(searchLimiter.retryAfter(now: now).rounded(.up))
            problems.append("Open Food Facts: bitte \(wait) s warten (höchstens 10 Suchen pro Minute)")
        }
        return SearchResults(items: items, problems: problems)
    }

    private func send(_ url: URL, sendUserAgent: Bool = true) async throws -> (Data, Int) {
        var request = URLRequest(url: url, timeoutInterval: 15)
        if sendUserAgent { request.setValue(userAgent, forHTTPHeaderField: "User-Agent") }
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            return try await transport(request)
        } catch let error as LookupError {
            throw error
        } catch {
            throw LookupError.unreachable
        }
    }

    public static let urlSessionTransport: Transport = { request in
        let (data, response) = try await URLSession.shared.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }
}
