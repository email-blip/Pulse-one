import SwiftData

/// Every SwiftData model of the app in one list. Feature modules add exactly one line
/// (`+ <Module>Persistence.models`), see docs/pulse-one-coordination/INTEGRATION.md.
enum PulseSchema {
    static let core: [any PersistentModel.Type] = [StoredMeasurement.self, StoredSample.self]

    static let models: [any PersistentModel.Type] = core
        + IntelligenceModels.all
        + CoachPersistence.models
        + NutritionPersistence.models
        + CompanionPersistence.models
        + CheckInPersistence.models
}
