import Foundation
import PulseCore
import SwiftData

/// One diary entry on disk (NUTRITION-SPEC §2). The food is kept as a JSON snapshot so later
/// database changes never rewrite what was eaten. Stays on the device.
@Model
final class StoredMealEntry {
    @Attribute(.unique) var entryID: UUID
    var date: Date
    var mealTypeRaw: String
    var foodData: Data
    var amount: Double
    var methodRaw: String
    var statusRaw: String
    var createdAt: Date
    /// Set once the entry was written to Apple Health (only with the user's opt-in).
    var healthWrittenAt: Date?

    init(_ entry: MealEntry, createdAt: Date = Date()) {
        entryID = entry.id
        date = entry.date
        mealTypeRaw = entry.mealType.rawValue
        foodData = (try? JSONEncoder().encode(entry.food)) ?? Data()
        amount = entry.amount
        methodRaw = entry.method.rawValue
        statusRaw = entry.status.rawValue
        self.createdAt = createdAt
    }

    func update(from entry: MealEntry) {
        date = entry.date
        mealTypeRaw = entry.mealType.rawValue
        foodData = (try? JSONEncoder().encode(entry.food)) ?? foodData
        amount = entry.amount
        methodRaw = entry.method.rawValue
        statusRaw = entry.status.rawValue
    }

    /// nil only if the stored snapshot cannot be read (never silently replaced by zeros).
    var entry: MealEntry? {
        guard let food = try? JSONDecoder().decode(FoodItem.self, from: foodData) else { return nil }
        return MealEntry(id: entryID, date: date, mealType: MealType(rawValue: mealTypeRaw) ?? .snack, food: food,
                         amount: amount, method: MealEntryMethod(rawValue: methodRaw) ?? .manual,
                         status: MealEntryStatus(rawValue: statusRaw) ?? .confirmed)
    }
}

/// Local food cache, favourites and "recently used" (NUTRITION-SPEC §3, §4: cache includes "not found").
@Model
final class StoredFoodItem {
    /// `FoodItem.id` ("off:<barcode>", "usda:<fdcId>", "custom:<uuid>") or "off-missing:<barcode>".
    @Attribute(.unique) var key: String
    var foodData: Data?
    var barcode: String?
    var nameLower: String = ""
    var notFound: Bool = false
    var isFavorite: Bool = false
    var useCount: Int = 0
    var lastUsed: Date?
    var fetchedAt: Date

    init(food: FoodItem, fetchedAt: Date = Date()) {
        key = food.id
        foodData = try? JSONEncoder().encode(food)
        barcode = food.barcode
        nameLower = food.displayName.lowercased()
        self.fetchedAt = fetchedAt
    }

    init(missingBarcode: String, fetchedAt: Date = Date()) {
        key = "off-missing:\(missingBarcode)"
        barcode = missingBarcode
        notFound = true
        self.fetchedAt = fetchedAt
    }

    var food: FoodItem? { foodData.flatMap { try? JSONDecoder().decode(FoodItem.self, from: $0) } }

    func store(_ food: FoodItem, at date: Date) {
        foodData = try? JSONEncoder().encode(food)
        nameLower = food.displayName.lowercased()
        fetchedAt = date
    }
}

enum NutritionPersistence {
    static let models: [any PersistentModel.Type] = [StoredMealEntry.self, StoredFoodItem.self]
}
