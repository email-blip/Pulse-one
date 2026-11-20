import Foundation

/// What a person chose as preferred source for one kind (Review 3.2 §4, "Geräte → Bevorzugte Quelle").
public enum SourceChoice: Hashable, Codable, Sendable {
    case automatic
    /// One concrete device or account.
    case device(SampleOrigin)
    /// Any device of a source system, e.g. Apple Health.
    case source(DataSourceKind)
}

/// Preferred source per kind for one profile. Kinds without an entry are automatic.
public struct SourcePreferences: Equatable, Codable, Sendable {
    public private(set) var choices: [String: SourceChoice] = [:]

    public init() {}

    public func choice(for kind: SampleKind) -> SourceChoice { choices[kind.rawValue] ?? .automatic }

    public mutating func set(_ choice: SourceChoice, for kind: SampleKind) {
        choices[kind.rawValue] = choice == .automatic ? nil : choice
    }
}

/// The situation a value was measured in. Pulse during training wants a chest strap, pulse at rest a ring.
public enum UsageContext: String, Codable, Sendable {
    case general, workout, rest
}

/// Why an origin was chosen; shown in the app and checked in tests.
public enum ResolutionReason: Equatable, Sendable {
    case preferred
    case automatic
    /// The preferred source had no usable data here; the automatic order filled in.
    case fallback(preferredMissing: SourceChoice)
}

public struct ResolvedOrigin: Equatable, Sendable {
    public let origin: SampleOrigin
    public let reason: ResolutionReason
}

/// Deterministic choice between origins:
/// 1. the profile's preference for the kind, if that origin has data;
/// 2. otherwise the automatic order for kind and situation (`automaticOrder`);
/// 3. inside one source system: `devicePriority`, then device id (stable, never "last added wins").
public struct SourcePolicy: Equatable, Sendable {
    public var preferences: SourcePreferences
    public var context: UsageContext
    /// Replaces the automatic order for every kind (tests, legacy callers).
    public var sourceOrder: [DataSourceKind]?
    public var devicePriority: [String]

    public init(preferences: SourcePreferences = SourcePreferences(), context: UsageContext = .general,
                sourceOrder: [DataSourceKind]? = nil, devicePriority: [String] = []) {
        self.preferences = preferences
        self.context = context
        self.sourceOrder = sourceOrder
        self.devicePriority = devicePriority
    }

    /// Automatic order per kind and situation. Sources not listed follow in a fixed order.
    public static func automaticOrder(for kind: SampleKind, context: UsageContext) -> [DataSourceKind] {
        let listed: [DataSourceKind]
        switch kind {
        case .heartRate:
            switch context {
            case .workout: listed = [.bluetoothStandard, .appleHealth, .colmiRing, .ouraCloud]
            case .rest: listed = [.colmiRing, .ouraCloud, .appleHealth, .bluetoothStandard]
            case .general: listed = [.bluetoothStandard, .colmiRing, .ouraCloud, .appleHealth]
            }
        case .heartRateVariability:
            listed = context == .workout ? [.bluetoothStandard, .appleHealth, .colmiRing, .ouraCloud]
                                         : [.ouraCloud, .colmiRing, .appleHealth, .bluetoothStandard]
        case .restingHeartRate: listed = [.ouraCloud, .appleHealth, .colmiRing, .bluetoothStandard]
        case .oxygenSaturation: listed = [.colmiRing, .ouraCloud, .appleHealth]
        case .sleepDuration: listed = [.ouraCloud, .colmiRing, .appleHealth]
        case .steps, .distance, .activeEnergy, .elevationGain: listed = [.appleHealth, .colmiRing, .ouraCloud]
        case .trainingDuration: listed = [.appleHealth, .bluetoothStandard]
        case .skinTemperature: listed = [.colmiRing, .ouraCloud]
        case .skinTemperatureDeviation: listed = [.ouraCloud, .appleHealth, .colmiRing]
        case .bodyTemperature: listed = [.manual, .appleHealth]
        case .deviceBattery: listed = []
        }
        let rest: [DataSourceKind] = [.bluetoothStandard, .colmiRing, .ouraCloud, .appleHealth, .manual]
        return listed + rest.filter { !listed.contains($0) }
    }

    public func order(for kind: SampleKind) -> [DataSourceKind] {
        sourceOrder ?? Self.automaticOrder(for: kind, context: context)
    }

    public func choose(kind: SampleKind, among origins: Set<SampleOrigin>) -> ResolvedOrigin? {
        guard !origins.isEmpty else { return nil }
        let choice = preferences.choice(for: kind)
        switch choice {
        case .device(let origin) where origins.contains(origin):
            return ResolvedOrigin(origin: origin, reason: .preferred)
        case .source(let source):
            if let best = automatic(kind: kind, among: origins.filter { $0.source == source }) {
                return ResolvedOrigin(origin: best, reason: .preferred)
            }
        default: break
        }
        guard let best = automatic(kind: kind, among: origins) else { return nil }
        return ResolvedOrigin(origin: best, reason: choice == .automatic ? .automatic : .fallback(preferredMissing: choice))
    }

    private func automatic(kind: SampleKind, among origins: Set<SampleOrigin>) -> SampleOrigin? {
        let order = order(for: kind)
        func rank(_ o: SampleOrigin) -> (Int, Int) {
            (order.firstIndex(of: o.source) ?? Int.max, devicePriority.firstIndex(of: o.deviceID) ?? Int.max)
        }
        return origins.min { a, b in
            let ra = rank(a), rb = rank(b)
            return ra != rb ? ra < rb : a < b
        }
    }
}
