import Foundation
import PulseCore
import SwiftData

/// Fixed diary for the `nutrition` screenshot scenario (in-memory store only, shown with "Testansicht").
enum NutritionTestData {
    @MainActor
    static func insert(into context: ModelContext, now: Date = Date()) {
        let day = Calendar.current.startOfDay(for: now)
        func at(_ hour: Int, _ minute: Int = 0) -> Date {
            Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
        }
        let oats = FoodItem(source: .usda, sourceID: "173904", name: "Cereals, oats, regular and quick, not fortified, dry",
                            nameDe: "Haferflocken",
                            per100: NutrientValues(energyKcal: 379, protein: 13.2, carbohydrates: 67.7, sugars: 1, fat: 6.5,
                                                   saturatedFat: 1.1, fiber: 10.1, salt: 0.02),
                            quality: .verified)
        let yogurt = FoodItem(source: .openFoodFacts, sourceID: "4000000000001", name: "Naturjoghurt 3,5 %", brand: "Testmarke",
                              barcode: "4000000000001",
                              per100: NutrientValues(energyKcal: 66, protein: 3.8, carbohydrates: 4.6, sugars: 4.6, fat: 3.5,
                                                     saturatedFat: 2.3, salt: 0.13),
                              servings: [ServingSize(label: "1 Becher (150 g)", amount: 150)], quality: .community,
                              allergens: ["Milch"])
        let soup = FoodItem.custom(name: "Linsensuppe (selbst gekocht)", per100: NutrientValues(energyKcal: 85, protein: 5.2, carbohydrates: 11, fat: 1.8),
                                   id: UUID(uuidString: "00000000-0000-0000-0000-00000000F00D") ?? UUID())
        let entries = [
            MealEntry(date: at(7, 30), mealType: .breakfast, food: oats, amount: 60, method: .search),
            MealEntry(date: at(7, 30), mealType: .breakfast, food: yogurt, amount: 150, method: .barcode),
            MealEntry(date: at(12, 45), mealType: .lunch, food: soup, amount: 400, method: .manual),
            MealEntry(date: at(9), mealType: .breakfast, food: .water, amount: 500, method: .quickFluid)
        ]
        for entry in entries {
            context.insert(StoredMealEntry(entry))
            let row = StoredFoodItem(food: entry.food)
            row.useCount = 1
            row.lastUsed = entry.date
            context.insert(row)
        }
    }
}
