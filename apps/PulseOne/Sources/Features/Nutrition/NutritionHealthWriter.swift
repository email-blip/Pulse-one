import Foundation
import HealthKit
import PulseCore

/// Writes confirmed diary entries to Apple Health, only after the user switched it on
/// (NUTRITION-SPEC §9). Every sample carries the entry id so a deleted entry is removed again.
final class NutritionHealthWriter: @unchecked Sendable {
    // @unchecked: HKHealthStore is thread-safe per Apple's documentation; nothing else is mutable.
    private let store = HKHealthStore()
    private static let entryKey = "PulseOneMealEntryID"

    static var available: Bool { HKHealthStore.isHealthDataAvailable() }

    /// Computed (HKUnit is not Sendable, so no shared static storage).
    private static var mapping: [(HKQuantityTypeIdentifier, Nutrient?, HKUnit)] {
        [
        (.dietaryEnergyConsumed, .energy, .kilocalorie()),
        (.dietaryProtein, .protein, .gram()),
        (.dietaryCarbohydrates, .carbohydrates, .gram()),
        (.dietaryFatTotal, .fat, .gram()),
        (.dietaryFiber, .fiber, .gram()),
        (.dietarySugar, .sugars, .gram()),
        (.dietaryWater, nil, .literUnit(with: .milli))
        ]
    }

    private static var shareTypes: Set<HKSampleType> {
        Set<HKSampleType>(mapping.map { HKQuantityType($0.0) as HKSampleType })
    }

    func requestAuthorization() async throws {
        try await store.requestAuthorization(toShare: Self.shareTypes, read: [])
    }

    /// Writes the known nutrient values of one entry. Missing values are skipped, never written as 0.
    func write(_ entry: MealEntry) async throws {
        let nutrients = entry.nutrients
        var samples: [HKQuantitySample] = []
        for (identifier, nutrient, unit) in Self.mapping {
            let value: Double?
            if let nutrient {
                value = nutrients[nutrient]
            } else {
                value = entry.fluidMilliliters > 0 ? entry.fluidMilliliters : nil
            }
            guard let value, value > 0 else { continue }
            let type = HKQuantityType(identifier)
            guard store.authorizationStatus(for: type) == .sharingAuthorized else { continue }
            samples.append(HKQuantitySample(
                type: type, quantity: HKQuantity(unit: unit, doubleValue: value), start: entry.date, end: entry.date,
                metadata: [HKMetadataKeyFoodType: entry.food.displayName, Self.entryKey: entry.id.uuidString]))
        }
        guard !samples.isEmpty else { return }
        try await store.save(samples)
    }

    func delete(entryID: UUID) async throws {
        let predicate = HKQuery.predicateForObjects(withMetadataKey: Self.entryKey, allowedValues: [entryID.uuidString])
        for (identifier, _, _) in Self.mapping {
            let type = HKQuantityType(identifier)
            guard store.authorizationStatus(for: type) == .sharingAuthorized else { continue }
            _ = try await store.deleteObjects(of: type, predicate: predicate)
        }
    }
}
