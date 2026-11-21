import Foundation

public enum MealType: String, Codable, Sendable, CaseIterable, Identifiable {
    case breakfast, lunch, dinner, snack

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .breakfast: "Frühstück"
        case .lunch: "Mittagessen"
        case .dinner: "Abendessen"
        case .snack: "Zwischendurch"
        }
    }

    /// A sensible default from the clock time; the user can always change it.
    public static func suggested(for date: Date, calendar: Calendar = .current) -> MealType {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        let minutes = (c.hour ?? 12) * 60 + (c.minute ?? 0)
        switch minutes {
        case 4 * 60 ..< 10 * 60 + 30: return .breakfast
        case 11 * 60 ..< 14 * 60 + 30: return .lunch
        case 17 * 60 + 30 ..< 21 * 60 + 30: return .dinner
        default: return .snack
        }
    }
}

/// How an entry was captured (NUTRITION-SPEC §2).
public enum MealEntryMethod: String, Codable, Sendable {
    case manual, search, barcode, photo, recipe, repeated, quickFluid
}

public enum MealEntryStatus: String, Codable, Sendable {
    case estimated, confirmed
}

/// One food eaten at one time. The food is stored as a snapshot so later database changes do not
/// rewrite the diary.
public struct MealEntry: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var date: Date
    public var mealType: MealType
    public var food: FoodItem
    /// In the food's unit (g or ml).
    public var amount: Double
    public var method: MealEntryMethod
    public var status: MealEntryStatus

    public static let plausibleAmount: ClosedRange<Double> = 1...5_000

    public init(id: UUID = UUID(), date: Date, mealType: MealType, food: FoodItem, amount: Double,
                method: MealEntryMethod, status: MealEntryStatus = .confirmed) {
        self.id = id
        self.date = date
        self.mealType = mealType
        self.food = food
        self.amount = amount
        self.method = method
        self.status = status
    }

    public var nutrients: NutrientValues { food.per100.scaled(toAmount: amount) }
    public var fluidMilliliters: Double { food.countsAsFluid && food.unit == .milliliter ? amount : 0 }
    public var quality: NutritionDataQuality { status == .estimated ? .estimated : food.quality }
    public var isAmountPlausible: Bool { Self.plausibleAmount.contains(amount) }
}
