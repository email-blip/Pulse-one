import Foundation
import Observation
import PulseCore

/// User choices for the Analyse module: model, what may be shared, monthly budget (spec §2 "Einstellungen").
/// Stored in UserDefaults; nothing here is secret. Test scenarios keep everything in memory.
@MainActor
@Observable
final class IntelligenceSettings {
    var modelID: String { didSet { save() } }
    var consent: Set<ConsentCategory> { didSet { save() } }
    /// Monthly spending limit in US dollars (Anthropic bills in USD).
    var monthlyBudgetUSD: Double { didSet { save() } }
    /// Maximum sends to Claude per month, a second brake next to the budget.
    var maxSendsPerMonth: Int { didSet { save() } }
    /// Apple's on-device model may phrase the short daily lines (never leaves the iPhone).
    var useOnDeviceModel: Bool { didSet { save() } }
    /// Owner decision 2026-11-21: Claude interprets like a physician team (diagnoses, probabilities,
    /// work-up, treatment). Off: trends only, as before.
    var clinicalMode: Bool { didSet { save() } }

    @ObservationIgnored private let defaults: UserDefaults?

    private enum Key {
        static let model = "intelligence.model"
        static let consent = "intelligence.consent"
        static let budget = "intelligence.budgetUSD"
        static let sends = "intelligence.maxSends"
        static let onDevice = "intelligence.onDevice"
        static let clinical = "intelligence.clinicalMode"
    }

    init(defaults: UserDefaults?) {
        self.defaults = defaults
        modelID = defaults?.string(forKey: Key.model) ?? ClaudeModel.standard.id
        if let raw = defaults?.stringArray(forKey: Key.consent) {
            consent = Set(raw.compactMap(ConsentCategory.init(rawValue:)))
        } else {
            consent = ConsentCategory.defaultConsent
        }
        let budget = defaults?.double(forKey: Key.budget) ?? 0
        monthlyBudgetUSD = budget > 0 ? budget : 10
        let sends = defaults?.integer(forKey: Key.sends) ?? 0
        maxSendsPerMonth = sends > 0 ? sends : 30
        useOnDeviceModel = defaults?.object(forKey: Key.onDevice) as? Bool ?? true
        clinicalMode = defaults?.object(forKey: Key.clinical) as? Bool ?? true
    }

    var safetyMode: SafetyMode { clinicalMode ? .clinical : .descriptive }

    var model: ClaudeModel { ClaudeModel.model(id: modelID) }

    /// One category as a switch (`$settings[consent: .sleep]`).
    subscript(consent category: ConsentCategory) -> Bool {
        get { consent.contains(category) }
        set {
            if newValue { consent.insert(category) } else { consent.remove(category) }
        }
    }

    private func save() {
        guard let defaults else { return }
        defaults.set(modelID, forKey: Key.model)
        defaults.set(consent.map(\.rawValue).sorted(), forKey: Key.consent)
        defaults.set(monthlyBudgetUSD, forKey: Key.budget)
        defaults.set(maxSendsPerMonth, forKey: Key.sends)
        defaults.set(useOnDeviceModel, forKey: Key.onDevice)
        defaults.set(clinicalMode, forKey: Key.clinical)
    }
}

/// One set of services for the module. Views reach it through `IntelligenceServices.shared`, so the tab,
/// the profile sheet and the TODAY card share key, settings and transport without touching the app root.
@MainActor
final class IntelligenceServices {
    static let shared = IntelligenceServices(options: LaunchOptions.current)

    let settings: IntelligenceSettings
    let secrets: any SecretStore
    let transport: any ClaudeTransport
    let isTestScenario: Bool

    init(options: LaunchOptions) {
        isTestScenario = options.usesTestScenario
        if options.isUITesting {
            // UI tests never touch the Keychain or the network (spec §6). Only a scenario gets a fake key.
            settings = IntelligenceSettings(defaults: nil)
            secrets = MemorySecretStore(options.usesTestScenario ? "sk-ant-test-0000000000001234" : nil)
            transport = MockTransport()
        } else {
            settings = IntelligenceSettings(defaults: .standard)
            secrets = KeychainStore()
            transport = URLSessionTransport()
        }
    }

    /// The clock the module uses: fixed in screenshots so they never change.
    var now: Date { isTestScenario ? TestScenario.fixedTime : .now }

    var hasKey: Bool { !(secrets.read() ?? "").isEmpty }
}
