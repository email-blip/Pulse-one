import Foundation
import PulseCore
import SwiftData

/// Coach data on disk (Welle 3). Core values are stored as JSON so the engine types stay plain Swift;
/// every field has a default for lightweight migration. Stays on the device.
@Model
final class CoachSettingsRecord {
    var preferencesData: Data = Data()
    var programData: Data?
    var updatedAt: Date = Date.distantPast

    init(preferences: CoachPreferences, program: TrainingProgram?, updatedAt: Date) {
        preferencesData = (try? JSONEncoder().encode(preferences)) ?? Data()
        programData = program.flatMap { try? JSONEncoder().encode($0) }
        self.updatedAt = updatedAt
    }

    var preferences: CoachPreferences? { try? JSONDecoder().decode(CoachPreferences.self, from: preferencesData) }
    var program: TrainingProgram? { programData.flatMap { try? JSONDecoder().decode(TrainingProgram.self, from: $0) } }

    func update(preferences: CoachPreferences, program: TrainingProgram?, at date: Date) {
        preferencesData = (try? JSONEncoder().encode(preferences)) ?? preferencesData
        programData = program.flatMap { try? JSONEncoder().encode($0) }
        updatedAt = date
    }
}

/// One evening review per day.
@Model
final class CoachReviewRecord {
    var day: Date = Date.distantPast
    var data: Data = Data()

    init(_ review: EveningReview) {
        day = review.day
        data = (try? JSONEncoder().encode(review)) ?? Data()
    }

    var review: EveningReview? { try? JSONDecoder().decode(EveningReview.self, from: data) }

    func update(_ review: EveningReview) {
        data = (try? JSONEncoder().encode(review)) ?? data
    }
}

/// A confirmed plan change with its reason (spec §6.4: history of all revisions).
@Model
final class CoachRevisionRecord {
    var day: Date = Date.distantPast
    var createdAt: Date = Date.distantPast
    var data: Data = Data()

    init(_ revision: PlanRevision) {
        day = revision.day
        createdAt = revision.createdAt
        data = (try? JSONEncoder().encode(revision)) ?? Data()
    }

    var revision: PlanRevision? { try? JSONDecoder().decode(PlanRevision.self, from: data) }
}

enum CoachPersistence {
    static let models: [any PersistentModel.Type] = [CoachSettingsRecord.self, CoachReviewRecord.self, CoachRevisionRecord.self]
}
