import Foundation

/// Where a food's nutrient values come from (NUTRITION-SPEC §4).
public enum FoodSource: String, Codable, Sendable, CaseIterable {
    case openFoodFacts = "off"
    case usda
    case bls
    case custom

    public var label: String {
        switch self {
        case .openFoodFacts: "Open Food Facts"
        case .usda: "USDA FoodData Central"
        case .bls: "Bundeslebensmittelschlüssel"
        case .custom: "Eigene Eingabe"
        }
    }

    /// Attribution the source asks for, shown with every value from it.
    public var attribution: String {
        switch self {
        case .openFoodFacts: "Daten: Open Food Facts (ODbL), Herstellerangaben"
        case .usda: "Daten: USDA FoodData Central"
        case .bls: "Daten: Max Rubner-Institut, BLS"
        case .custom: "Von dir eingegeben"
        }
    }
}

/// How trustworthy a value is; always visible next to it (NUTRITION-SPEC §2).
public enum NutritionDataQuality: String, Codable, Sendable, CaseIterable {
    /// Official food composition table.
    case verified
    /// Open Food Facts with all core values.
    case community
    /// Core values missing.
    case incomplete
    /// Portion or values are a guess.
    case estimated
    /// Entered by the user.
    case user

    public var label: String {
        switch self {
        case .verified: "amtliche Tabelle"
        case .community: "Herstellerangabe"
        case .incomplete: "unvollständig"
        case .estimated: "geschätzt"
        case .user: "eigene Angabe"
        }
    }
}

/// Grams or millilitres. Nutrients are always given per 100 of this unit.
public enum FoodUnit: String, Codable, Sendable {
    case gram = "g"
    case milliliter = "ml"
}

/// A named portion such as "1 Portion (30 g)" or "1 Glas (250 ml)".
public struct ServingSize: Codable, Hashable, Sendable {
    public var label: String
    public var amount: Double

    public init(label: String, amount: Double) {
        self.label = label
        self.amount = amount
    }
}

public struct FoodItem: Codable, Hashable, Sendable, Identifiable {
    public var source: FoodSource
    /// Barcode for Open Food Facts, FDC id for USDA, a UUID for own foods.
    public var sourceID: String
    public var name: String
    /// German name when the source name is English (USDA) and a translation is known.
    public var nameDe: String?
    public var brand: String?
    public var barcode: String?
    public var unit: FoodUnit
    public var per100: NutrientValues
    public var servings: [ServingSize]
    public var quality: NutritionDataQuality
    /// Allergens as stated by the manufacturer, German labels.
    public var allergens: [String]
    /// Water, tea, coffee count towards the daily fluid amount.
    public var countsAsFluid: Bool
    public var fetchedAt: Date?

    public var id: String { "\(source.rawValue):\(sourceID)" }
    public var displayName: String { nameDe ?? name }

    public init(source: FoodSource, sourceID: String, name: String, nameDe: String? = nil, brand: String? = nil,
                barcode: String? = nil, unit: FoodUnit = .gram, per100: NutrientValues, servings: [ServingSize] = [],
                quality: NutritionDataQuality, allergens: [String] = [], countsAsFluid: Bool = false, fetchedAt: Date? = nil) {
        self.source = source
        self.sourceID = sourceID
        self.name = name
        self.nameDe = nameDe
        self.brand = brand
        self.barcode = barcode
        self.unit = unit
        self.per100 = per100
        self.servings = servings
        self.quality = quality
        self.allergens = allergens
        self.countsAsFluid = countsAsFluid
        self.fetchedAt = fetchedAt
    }

    /// A food the user typed in. Values are per 100 g/ml.
    public static func custom(name: String, unit: FoodUnit = .gram, per100: NutrientValues,
                              id: UUID = UUID(), countsAsFluid: Bool = false) -> FoodItem {
        FoodItem(source: .custom, sourceID: id.uuidString, name: name, unit: unit,
                 per100: per100.sanitizedPer100().values, quality: .user, countsAsFluid: countsAsFluid)
    }

    /// Plain water for the quick buttons.
    public static let water = FoodItem(
        source: .custom, sourceID: "water", name: "Wasser", unit: .milliliter,
        per100: NutrientValues(energyKcal: 0, protein: 0, carbohydrates: 0, sugars: 0, fat: 0, saturatedFat: 0, fiber: 0, salt: 0),
        servings: [ServingSize(label: "1 Glas", amount: 250), ServingSize(label: "1 Flasche", amount: 500)],
        quality: .user, countsAsFluid: true)

    /// Quality from the values present: a database entry without core values is `incomplete`.
    static func grade(_ values: NutrientValues, ifComplete: NutritionDataQuality) -> NutritionDataQuality {
        values.hasCoreValues ? ifComplete : .incomplete
    }
}
