import Foundation

/// USDA FoodData Central search (NUTRITION-SPEC §4): generic foods with per-100 g values.
/// Public domain data. Needs an api.data.gov key; `DEMO_KEY` works with low limits until the user adds an own key.
public enum USDAFoodData {
    public static let host = "api.nal.usda.gov"
    public static let demoKey = "DEMO_KEY"
    /// Requests per hour: 1 000 with an own key, 30 with the demo key.
    public static func hourlyLimit(apiKey: String?) -> Int { (apiKey?.isEmpty == false && apiKey != demoKey) ? 1_000 : 30 }

    public static func searchURL(query: String, apiKey: String?, pageSize: Int = 15) -> URL? {
        var c = URLComponents()
        c.scheme = "https"
        c.host = host
        c.path = "/fdc/v1/foods/search"
        let key = apiKey.flatMap { $0.isEmpty ? nil : $0 } ?? demoKey
        c.queryItems = [
            URLQueryItem(name: "api_key", value: key),
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "dataType", value: "Foundation,SR Legacy"),
            URLQueryItem(name: "pageSize", value: String(pageSize))
        ]
        return c.url
    }

    /// Nutrient ids in FoodData Central.
    enum NutrientID {
        static let energyKcal = 1008, energyAtwaterGeneral = 2047, energyAtwaterSpecific = 2048
        static let protein = 1003, fat = 1004, carbohydrates = 1005, fiber = 1079
        static let sugars = 2000, sugarsNLEA = 1063, saturatedFat = 1258, sodium = 1093
    }

    private struct SearchResponse: Decodable {
        let foods: [Food]?
    }

    private struct Food: Decodable {
        let fdcId: Int
        let description: String
        let foodNutrients: [FoodNutrient]?
    }

    private struct FoodNutrient: Decodable {
        let nutrientId: Int?
        let unitName: String?
        let value: Double?
    }

    /// Parses a `/foods/search` response. `germanName` is attached when the search came from a German term.
    public static func parseSearch(_ data: Data, germanName: String?, fetchedAt: Date) throws -> [FoodItem] {
        let response = try JSONDecoder().decode(SearchResponse.self, from: data)
        return (response.foods ?? []).compactMap { food in
            var byID: [Int: (value: Double, unit: String)] = [:]
            for n in food.foodNutrients ?? [] {
                if let id = n.nutrientId, let v = n.value { byID[id] = (v, (n.unitName ?? "").uppercased()) }
            }
            func grams(_ id: Int) -> Double? {
                guard let entry = byID[id] else { return nil }
                switch entry.unit {
                case "MG": return entry.value / 1_000
                case "UG", "µG": return entry.value / 1_000_000
                default: return entry.value
                }
            }
            func kcal(_ id: Int) -> Double? {
                guard let entry = byID[id] else { return nil }
                return entry.unit == "KJ" ? entry.value / NutrientValues.kilojoulesPerKilocalorie : entry.value
            }
            var values = NutrientValues(
                energyKcal: kcal(NutrientID.energyKcal) ?? kcal(NutrientID.energyAtwaterGeneral) ?? kcal(NutrientID.energyAtwaterSpecific),
                protein: grams(NutrientID.protein),
                carbohydrates: grams(NutrientID.carbohydrates),
                sugars: grams(NutrientID.sugars) ?? grams(NutrientID.sugarsNLEA),
                fat: grams(NutrientID.fat),
                saturatedFat: grams(NutrientID.saturatedFat),
                fiber: grams(NutrientID.fiber),
                salt: grams(NutrientID.sodium).map { $0 * 2.5 })
            values = values.sanitizedPer100().values
            guard !values.isEmpty else { return nil }
            return FoodItem(source: .usda, sourceID: String(food.fdcId), name: food.description, nameDe: germanName,
                            per100: values, quality: FoodItem.grade(values, ifComplete: .verified), fetchedAt: fetchedAt)
        }
    }
}
