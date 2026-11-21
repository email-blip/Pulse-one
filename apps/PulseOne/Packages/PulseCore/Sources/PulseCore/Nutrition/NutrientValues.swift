import Foundation

/// The nutrients PULSE ONE tracks for every food (NUTRITION-SPEC §2). Energy in kcal, the rest in grams.
public enum Nutrient: String, CaseIterable, Codable, Sendable {
    case energy, protein, carbohydrates, sugars, fat, saturatedFat, fiber, salt

    public var label: String {
        switch self {
        case .energy: "Energie"
        case .protein: "Eiweiß"
        case .carbohydrates: "Kohlenhydrate"
        case .sugars: "davon Zucker"
        case .fat: "Fett"
        case .saturatedFat: "davon gesättigt"
        case .fiber: "Ballaststoffe"
        case .salt: "Salz"
        }
    }

    public var unitSymbol: String { self == .energy ? "kcal" : "g" }

    /// Highest believable value per 100 g or 100 ml. Pure fat has about 900 kcal per 100 g.
    public var plausibleMaxPer100: Double { self == .energy ? 900 : 100 }

    /// The four values a food needs to count as complete.
    public static let core: [Nutrient] = [.energy, .protein, .carbohydrates, .fat]
}

/// Nutrient amounts. A missing value is `nil`, never 0 (a missing label is not "no sugar").
public struct NutrientValues: Codable, Hashable, Sendable {
    public var energyKcal: Double?
    public var protein: Double?
    public var carbohydrates: Double?
    public var sugars: Double?
    public var fat: Double?
    public var saturatedFat: Double?
    public var fiber: Double?
    public var salt: Double?

    public static let kilojoulesPerKilocalorie = 4.184

    public init(energyKcal: Double? = nil, protein: Double? = nil, carbohydrates: Double? = nil, sugars: Double? = nil,
                fat: Double? = nil, saturatedFat: Double? = nil, fiber: Double? = nil, salt: Double? = nil) {
        self.energyKcal = energyKcal
        self.protein = protein
        self.carbohydrates = carbohydrates
        self.sugars = sugars
        self.fat = fat
        self.saturatedFat = saturatedFat
        self.fiber = fiber
        self.salt = salt
    }

    public subscript(nutrient: Nutrient) -> Double? {
        get {
            switch nutrient {
            case .energy: energyKcal
            case .protein: protein
            case .carbohydrates: carbohydrates
            case .sugars: sugars
            case .fat: fat
            case .saturatedFat: saturatedFat
            case .fiber: fiber
            case .salt: salt
            }
        }
        set {
            switch nutrient {
            case .energy: energyKcal = newValue
            case .protein: protein = newValue
            case .carbohydrates: carbohydrates = newValue
            case .sugars: sugars = newValue
            case .fat: fat = newValue
            case .saturatedFat: saturatedFat = newValue
            case .fiber: fiber = newValue
            case .salt: salt = newValue
            }
        }
    }

    /// Energy in kJ, derived from kcal.
    public var energyKilojoules: Double? { energyKcal.map { $0 * Self.kilojoulesPerKilocalorie } }

    public var missing: [Nutrient] { Nutrient.allCases.filter { self[$0] == nil } }
    public var isEmpty: Bool { missing.count == Nutrient.allCases.count }
    public var hasCoreValues: Bool { Nutrient.core.allSatisfy { self[$0] != nil } }

    /// Values for `amount` grams (or ml) when `self` is given per 100.
    public func scaled(toAmount amount: Double) -> NutrientValues {
        var result = NutrientValues()
        for n in Nutrient.allCases { result[n] = self[n].map { $0 * amount / 100 } }
        return result
    }

    /// Drops values that cannot be true per 100 g/ml (negative, above the physical maximum, or a
    /// "davon" value larger than its parent). Returns the cleaned values and what was dropped.
    public func sanitizedPer100() -> (values: NutrientValues, dropped: [Nutrient]) {
        var clean = self
        var dropped: [Nutrient] = []
        for n in Nutrient.allCases {
            guard let v = clean[n] else { continue }
            if !v.isFinite || v < 0 || v > n.plausibleMaxPer100 {
                clean[n] = nil
                dropped.append(n)
            }
        }
        // Rounding on labels allows a small overshoot.
        if let s = clean.sugars, let c = clean.carbohydrates, s > c + 0.5 { clean.sugars = nil; dropped.append(.sugars) }
        if let s = clean.saturatedFat, let f = clean.fat, s > f + 0.5 { clean.saturatedFat = nil; dropped.append(.saturatedFat) }
        // Fibre is left out on purpose: USDA (and US labels) count it inside carbohydrates, so adding it
        // again would reject real foods such as chia seeds or flaxseed.
        if let p = clean.protein, let c = clean.carbohydrates, let f = clean.fat, p + c + f > 105 {
            // Macros cannot add up to more than the whole portion; keep energy, drop the macro block.
            for n in [Nutrient.protein, .carbohydrates, .fat] { clean[n] = nil; dropped.append(n) }
        }
        return (clean, dropped)
    }
}

/// Sum of several nutrient values that remembers where a value was missing in at least one part,
/// so a day total can say "at least" instead of pretending to be exact.
public struct NutrientTotals: Hashable, Sendable {
    public private(set) var values = NutrientValues()
    /// Nutrients that were missing in at least one summed part.
    public private(set) var incomplete: Set<Nutrient> = []
    public private(set) var partCount = 0

    public init() {}

    public mutating func add(_ part: NutrientValues) {
        partCount += 1
        for n in Nutrient.allCases {
            if let v = part[n] {
                values[n] = (values[n] ?? 0) + v
            } else {
                incomplete.insert(n)
            }
        }
    }

    /// Total for a nutrient; `nil` when no part had it.
    public subscript(nutrient: Nutrient) -> Double? { values[nutrient] }

    public func isComplete(_ nutrient: Nutrient) -> Bool { !incomplete.contains(nutrient) }
}
