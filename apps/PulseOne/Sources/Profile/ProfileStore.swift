import Foundation
import Observation
import PulseCore

/// The owner's profile on this device (JSON with complete file protection). Test scenarios keep it in memory.
@MainActor
@Observable
final class ProfileStore {
    private(set) var profile: UserProfile
    /// True once the first-start setup was finished or skipped.
    private(set) var setupCompleted: Bool
    /// Step the setup was left at, so it continues there after a restart.
    private(set) var setupStep: Int
    @ObservationIgnored private let fileURL: URL?

    private struct Stored: Codable {
        var profile: UserProfile
        var setupCompleted: Bool
        var setupStep: Int?
    }

    private init(profile: UserProfile, setupCompleted: Bool, setupStep: Int, fileURL: URL?) {
        self.profile = profile
        self.setupCompleted = setupCompleted
        self.setupStep = setupStep
        self.fileURL = fileURL
    }

    static func live() -> ProfileStore {
        let url = URL.applicationSupportDirectory.appending(path: "profile.json")
        let stored = (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(Stored.self, from: $0) }
        return ProfileStore(profile: stored?.profile ?? UserProfile(), setupCompleted: stored?.setupCompleted ?? false,
                            setupStep: stored?.setupStep ?? 0, fileURL: url)
    }

    /// In-memory store for UI tests; `setupCompleted` decides whether the first-start setup shows.
    static func preview(_ profile: UserProfile = UserProfile(displayName: "Alex"), setupCompleted: Bool = true) -> ProfileStore {
        ProfileStore(profile: profile, setupCompleted: setupCompleted, setupStep: 0, fileURL: nil)
    }

    func update(_ edit: (inout UserProfile) -> Void) {
        var copy = profile
        edit(&copy)
        profile = copy.sanitized()
        save()
    }

    func setSetupStep(_ step: Int) {
        setupStep = step
        save()
    }

    func completeSetup() {
        setupCompleted = true
        setupStep = 0
        save()
    }

    func restartSetup() {
        setupCompleted = false
        setupStep = 0
        save()
    }

    private func save() {
        guard let fileURL else { return }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(Stored(profile: profile, setupCompleted: setupCompleted, setupStep: setupStep))
            try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
        } catch {
            // The profile is a convenience; the app keeps working with the values in memory.
        }
    }
}
