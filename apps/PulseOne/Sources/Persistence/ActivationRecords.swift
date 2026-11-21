import Foundation
import PulseCore
import SwiftData

/// Activation ("Aktivierung") data of the companion on disk. Core values are stored as JSON (see `CompanionJSON`);
/// every stored property has a default for lightweight migration. Stays on the device.

/// The one settings row: activation settings and the person's current levels.
@Model
final class ActivationSettingsRecord {
    /// `ActivationSettings` as JSON (nil = defaults).
    var settingsJSON: Data?
    /// `ActivationProfile` as JSON (nil = no levels yet; the planner starts from the fitness level).
    var profileJSON: Data?
    var updatedAt: Date = Date.distantPast

    init() {}

    var settings: ActivationSettings {
        get { CompanionJSON.decode(ActivationSettings.self, from: settingsJSON) ?? ActivationSettings() }
        set { settingsJSON = CompanionJSON.encode(newValue) }
    }

    var profile: ActivationProfile {
        get { CompanionJSON.decode(ActivationProfile.self, from: profileJSON) ?? ActivationProfile() }
        set { profileJSON = CompanionJSON.encode(newValue) }
    }
}

/// One finished (or partly finished) session.
@Model
final class ActivationSessionRecord {
    /// Start of the local day the session belongs to.
    var day: Date = Date.distantPast
    var slotRaw: String = ActivationSlot.morning.rawValue
    var finishedAt: Date = Date.distantPast
    var minutes: Int = 0
    /// `ActivationFeedback` raw value, nil when the person gave none.
    var feedbackRaw: String?
    /// `ActivationResult` as JSON.
    var resultJSON: Data = Data()

    init(result: ActivationResult, day: Date, minutes: Int) {
        self.day = day
        slotRaw = result.plan.slot.rawValue
        finishedAt = result.finishedAt
        self.minutes = minutes
        feedbackRaw = result.feedback?.rawValue
        resultJSON = CompanionJSON.encode(result) ?? Data()
    }

    var result: ActivationResult? { CompanionJSON.decode(ActivationResult.self, from: resultJSON) }
    var slot: ActivationSlot { ActivationSlot(rawValue: slotRaw) ?? .snack }
    var feedback: ActivationFeedback? { feedbackRaw.flatMap(ActivationFeedback.init(rawValue:)) }
}
