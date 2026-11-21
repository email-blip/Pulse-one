import Foundation

/// Open Food Facts API v2 (NUTRITION-SPEC §4): product by barcode, simple text search.
/// Requests carry only the barcode or search term and an app User-Agent, never profile or health data.
public enum OpenFoodFacts {
    public static let host = "world.openfoodfacts.org"
    /// Required by Open Food Facts; contains no personal data.
    public static func userAgent(appVersion: String) -> String { "PulseOne/\(appVersion) (iOS; private health diary)" }
    /// Documented limits: 100 product reads and 10 searches per minute.
    public static let productLimit = 100
    public static let searchLimit = 10

    static let fields = [
        "code", "product_name", "product_name_de", "generic_name", "generic_name_de", "brands", "nutriments",
        "serving_size", "serving_quantity", "quantity", "product_quantity_unit", "allergens_tags", "categories_tags"
    ].joined(separator: ",")

    public static func productURL(barcode: String) -> URL? {
        var c = URLComponents()
        c.scheme = "https"
        c.host = host
        c.path = "/api/v2/product/\(barcode)"
        c.queryItems = [URLQueryItem(name: "fields", value: fields)]
        return c.url
    }

    public static func searchURL(query: String, pageSize: Int = 20) -> URL? {
        var c = URLComponents()
        c.scheme = "https"
        c.host = host
        c.path = "/cgi/search.pl"
        c.queryItems = [
            URLQueryItem(name: "search_terms", value: query),
            URLQueryItem(name: "search_simple", value: "1"),
            URLQueryItem(name: "action", value: "process"),
            URLQueryItem(name: "json", value: "1"),
            URLQueryItem(name: "lc", value: "de"),
            URLQueryItem(name: "page_size", value: String(pageSize)),
            URLQueryItem(name: "fields", value: fields)
        ]
        return c.url
    }

    public enum LookupResult: Sendable, Equatable {
        case found(FoodItem)
        case notFound
    }

    public enum ParseError: Error, Equatable {
        case malformed
    }

    /// Parses a `/api/v2/product/{code}` response. Unknown or empty products are `notFound`.
    public static func parseProduct(_ data: Data, barcode: String, fetchedAt: Date) throws -> LookupResult {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw ParseError.malformed }
        let status = number(root["status"]) ?? 0
        guard status == 1, let product = root["product"] as? [String: Any],
              let item = food(from: product, fallbackCode: barcode, fetchedAt: fetchedAt) else { return .notFound }
        return .found(item)
    }

    /// Parses a search response; products without a name or without any nutrient value are skipped.
    public static func parseSearch(_ data: Data, fetchedAt: Date) throws -> [FoodItem] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw ParseError.malformed }
        let products = root["products"] as? [[String: Any]] ?? []
        var seen = Set<String>()
        return products.compactMap { food(from: $0, fallbackCode: nil, fetchedAt: fetchedAt) }
            .filter { !$0.per100.isEmpty && seen.insert($0.id).inserted }
    }

    static func food(from p: [String: Any], fallbackCode: String?, fetchedAt: Date) -> FoodItem? {
        guard let code = string(p["code"]) ?? fallbackCode else { return nil }
        let names = ["product_name_de", "product_name", "generic_name_de", "generic_name"].compactMap { string(p[$0]) }
        guard let name = names.first else { return nil }
        let brand = string(p["brands"])?.split(separator: ",").first.map { $0.trimmingCharacters(in: .whitespaces) }
        let n = p["nutriments"] as? [String: Any] ?? [:]
        var values = NutrientValues(
            energyKcal: number(n["energy-kcal_100g"]),
            protein: number(n["proteins_100g"]),
            carbohydrates: number(n["carbohydrates_100g"]),
            sugars: number(n["sugars_100g"]),
            fat: number(n["fat_100g"]),
            saturatedFat: number(n["saturated-fat_100g"]),
            fiber: number(n["fiber_100g"]),
            salt: number(n["salt_100g"]))
        if values.energyKcal == nil, let kj = number(n["energy-kj_100g"]) ?? number(n["energy_100g"]) {
            values.energyKcal = kj / NutrientValues.kilojoulesPerKilocalorie
        }
        if values.salt == nil, let sodium = number(n["sodium_100g"]) { values.salt = sodium * 2.5 }
        values = values.sanitizedPer100().values

        let unit = liquidUnit(p) ? FoodUnit.milliliter : .gram
        var servings: [ServingSize] = []
        if let amount = number(p["serving_quantity"]), amount > 0, amount <= 2_000 {
            let label = string(p["serving_size"]) ?? "\(Int(amount.rounded())) \(unit.rawValue)"
            servings.append(ServingSize(label: "1 Portion (\(label))", amount: amount))
        }
        if let pack = packageAmount(string(p["quantity"])), pack > 0, pack <= 2_000, !servings.contains(where: { $0.amount == pack }) {
            servings.append(ServingSize(label: "Packung (\(Int(pack.rounded())) \(unit.rawValue))", amount: pack))
        }
        let allergens = (p["allergens_tags"] as? [String] ?? []).map(allergenLabel)
        let categories = p["categories_tags"] as? [String] ?? []
        let fluid = unit == .milliliter && categories.contains { $0.hasSuffix(":waters") || $0.hasSuffix(":teas") || $0.hasSuffix(":coffees") }
        return FoodItem(source: .openFoodFacts, sourceID: code, name: name, brand: brand, barcode: code, unit: unit,
                        per100: values, servings: servings, quality: FoodItem.grade(values, ifComplete: .community),
                        allergens: allergens, countsAsFluid: fluid, fetchedAt: fetchedAt)
    }

    static func liquidUnit(_ p: [String: Any]) -> Bool {
        if let unit = string(p["product_quantity_unit"])?.lowercased() { return unit == "ml" }
        guard let q = string(p["quantity"])?.lowercased() else { return false }
        return q.range(of: #"\d\s*(ml|cl|l)\b"#, options: .regularExpression) != nil
    }

    /// "500 g", "1,5 l", "330 ml" -> amount in g or ml.
    static func packageAmount(_ text: String?) -> Double? {
        guard let text = text?.lowercased().replacingOccurrences(of: ",", with: "."),
              let match = text.range(of: #"(\d+(\.\d+)?)\s*(kg|g|ml|cl|l)\b"#, options: .regularExpression) else { return nil }
        let token = String(text[match])
        let numberPart = token.prefix { $0.isNumber || $0 == "." }
        guard let value = Double(numberPart) else { return nil }
        let unit = token.drop { $0.isNumber || $0 == "." || $0 == " " }
        switch unit {
        case "kg", "l": return value * 1_000
        case "cl": return value * 10
        default: return value
        }
    }

    /// The 14 EU allergens in German; unknown tags are shown as given without the language prefix.
    static func allergenLabel(_ tag: String) -> String {
        let key = tag.split(separator: ":").last.map(String.init) ?? tag
        let labels = [
            "gluten": "Gluten", "milk": "Milch", "eggs": "Eier", "nuts": "Schalenfrüchte", "peanuts": "Erdnüsse",
            "soybeans": "Soja", "fish": "Fisch", "crustaceans": "Krebstiere", "molluscs": "Weichtiere",
            "celery": "Sellerie", "mustard": "Senf", "sesame-seeds": "Sesam", "lupin": "Lupinen",
            "sulphur-dioxide-and-sulphites": "Sulfite"
        ]
        return labels[key] ?? key.replacingOccurrences(of: "-", with: " ")
    }

    static func string(_ any: Any?) -> String? {
        let s: String?
        switch any {
        case let v as String: s = v
        case let v as NSNumber: s = v.stringValue
        default: s = nil
        }
        let trimmed = s?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    /// Open Food Facts mixes numbers and numeric strings (sometimes with a decimal comma).
    static func number(_ any: Any?) -> Double? {
        switch any {
        case let v as NSNumber:
            // JSON booleans arrive as NSNumber too; they are never a nutrient value.
            return CFGetTypeID(v) == CFBooleanGetTypeID() ? nil : v.doubleValue
        case let v as String:
            return Double(v.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "."))
        default:
            return nil
        }
    }
}
