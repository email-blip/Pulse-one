import Foundation

/// Totals for one calendar day, overall and per meal. Missing values stay visible as "incomplete".
public struct DailyNutritionSummary: Sendable {
    public let day: Date
    public let totals: NutrientTotals
    public let perMeal: [MealType: NutrientTotals]
    public let entriesByMeal: [MealType: [MealEntry]]
    public let fluidMilliliters: Double
    public let entryCount: Int
    public let estimatedCount: Int

    public var isEmpty: Bool { entryCount == 0 }

    /// Summarises the entries that fall on `day` in `calendar`'s time zone; other entries are ignored.
    public static func build(entries: [MealEntry], day: Date, calendar: Calendar = .current) -> DailyNutritionSummary {
        let start = calendar.startOfDay(for: day)
        let todays = entries
            .filter { calendar.isDate($0.date, inSameDayAs: start) }
            .sorted { $0.date < $1.date }
        var totals = NutrientTotals()
        var perMeal: [MealType: NutrientTotals] = [:]
        var byMeal: [MealType: [MealEntry]] = [:]
        var fluid = 0.0
        for entry in todays {
            // Water and other zero-energy drinks still count as complete parts.
            totals.add(entry.nutrients)
            perMeal[entry.mealType, default: NutrientTotals()].add(entry.nutrients)
            byMeal[entry.mealType, default: []].append(entry)
            fluid += entry.fluidMilliliters
        }
        return DailyNutritionSummary(day: start, totals: totals, perMeal: perMeal, entriesByMeal: byMeal,
                                     fluidMilliliters: fluid, entryCount: todays.count,
                                     estimatedCount: todays.filter { $0.status == .estimated }.count)
    }

    /// Share of energy from protein, carbohydrates and fat (4/4/9 kcal per g), each 0…1; nil if a value is missing.
    public var macroEnergyShares: (protein: Double, carbohydrates: Double, fat: Double)? {
        guard let p = totals[.protein], let c = totals[.carbohydrates], let f = totals[.fat] else { return nil }
        let kcal = p * 4 + c * 4 + f * 9
        guard kcal > 0 else { return nil }
        return (p * 4 / kcal, c * 4 / kcal, f * 9 / kcal)
    }
}

/// Text formatting shared by screens and tests ("ca." for estimates, "mind." for incomplete sums).
public enum NutritionFormat {
    public static func amount(_ value: Double, unit: FoodUnit) -> String {
        "\(Int(value.rounded())) \(unit.rawValue)"
    }

    public static func value(_ value: Double?, of nutrient: Nutrient, incomplete: Bool = false, estimated: Bool = false) -> String {
        guard let value else { return "keine Angabe" }
        let number: String
        if nutrient == .energy || value >= 10 {
            number = String(Int(value.rounded()))
        } else {
            number = value.formatted(.number.precision(.fractionLength(1)).locale(Locale(identifier: "de_DE")))
        }
        let prefix = incomplete ? "mind. " : (estimated ? "ca. " : "")
        return "\(prefix)\(number) \(nutrient.unitSymbol)"
    }
}
