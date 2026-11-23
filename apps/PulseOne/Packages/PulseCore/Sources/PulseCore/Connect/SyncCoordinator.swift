import Foundation

/// What a sync run changes in the store. Applying the same batch twice yields an empty plan the second time.
public struct SyncPlan: Equatable, Sendable {
    public var inserts: [HealthSample] = []
    /// Existing samples whose source changed the value or time; keeps the stored `id`.
    public var updates: [HealthSample] = []
    /// Stored sample ids the source reported as deleted.
    public var deletions: [UUID] = []
    public var unchanged = 0
    /// Same identity with different content inside one batch; the first one was kept.
    public var conflicts = 0
    public var rejected: [NormalizationError] = []

    public init() {}

    public var isEmpty: Bool { inserts.isEmpty && updates.isEmpty && deletions.isEmpty }
}

/// Idempotent merge of incoming source data into the store (directive §5, Review 3.2 §2–3).
public enum SyncCoordinator {
    /// - Parameters:
    ///   - existing: stored samples of this device, keyed by `deduplicationKey`.
    ///   - profiles: who wore the device when. New samples take the profile valid at their start time;
    ///     stored samples keep their profile, a sync never moves history to another person.
    public static func plan(batch: SyncBatch, existing: [String: HealthSample], profiles: ProfileTimeline,
                            importedAt: Date, sourceConfirmed: Bool = false) -> SyncPlan {
        var plan = SyncPlan()
        var seen: [String: HealthSample] = [:]
        for raw in batch.observations {
            let sample: HealthSample
            do {
                sample = try MeasurementNormalizer.normalize(raw, profileID: profiles.profile(at: raw.start),
                                                             importedAt: importedAt, sourceConfirmed: sourceConfirmed)
            } catch let error as NormalizationError {
                plan.rejected.append(error)
                continue
            } catch {
                continue
            }
            let key = sample.deduplicationKey
            if let first = seen[key] {
                // Same identity twice in one batch: keep the first; a different value is a conflict to report.
                if !sameContent(first, sample) { plan.conflicts += 1 }
                continue
            }
            seen[key] = sample
            if let stored = existing[key] {
                if sameContent(stored, sample) {
                    plan.unchanged += 1
                } else {
                    plan.updates.append(replacing(stored, with: sample))
                }
            } else {
                plan.inserts.append(sample)
            }
        }
        let deletedKeys = Set(batch.deletedOriginalIDs)
        if !deletedKeys.isEmpty {
            plan.deletions = existing.values
                .filter { deletedKeys.contains($0.originalSampleID) && seen[$0.deduplicationKey] == nil }
                .map(\.id)
                .sorted { $0.uuidString < $1.uuidString }
        }
        return plan
    }

    /// Convenience for sources that belong to one profile for all time.
    public static func plan(batch: SyncBatch, existing: [String: HealthSample], profileID: UUID?,
                            importedAt: Date) -> SyncPlan {
        plan(batch: batch, existing: existing, profiles: .constant(profileID), importedAt: importedAt)
    }

    /// After a logged assignment correction: the samples whose profile changes. Nothing else ever
    /// re-attributes stored samples.
    public static func reattribute(_ samples: [HealthSample], with profiles: ProfileTimeline) -> [HealthSample] {
        samples.compactMap { s in
            let target = profiles.profile(at: s.start)
            return target == s.profileID ? nil : s.attributed(to: target)
        }
    }

    /// Profile is deliberately not compared: it is not the source's content.
    static func sameContent(_ a: HealthSample, _ b: HealthSample) -> Bool {
        a.value == b.value && a.unit == b.unit && a.start == b.start && a.end == b.end
            && a.quality == b.quality && a.qualityReason == b.qualityReason && a.originDetail == b.originDetail
    }

    /// The source changed a sample (e.g. edited in Health). The stored id and profile stay.
    static func replacing(_ stored: HealthSample, with new: HealthSample) -> HealthSample {
        HealthSample(id: stored.id, profileID: stored.profileID, kind: new.kind, value: new.value, unit: new.unit,
                     start: new.start, end: new.end, timeZoneIdentifier: new.timeZoneIdentifier, source: new.source,
                     deviceID: new.deviceID, originalSampleID: new.originalSampleID, importedAt: new.importedAt,
                     quality: new.quality, qualityReason: new.qualityReason, method: new.method,
                     identity: new.identity, rawDataReference: new.rawDataReference, originDetail: new.originDetail,
                     receivedAt: stored.receivedAt ?? new.receivedAt)
    }
}

/// Where a sample came from: the source system and the device within it. Two rings of the same model
/// are two origins.
public struct SampleOrigin: Hashable, Codable, Sendable, Comparable {
    public let source: DataSourceKind
    public let deviceID: String

    public init(source: DataSourceKind, deviceID: String) {
        self.source = source
        self.deviceID = deviceID
    }

    public static func < (a: SampleOrigin, b: SampleOrigin) -> Bool {
        (a.source.rawValue, a.deviceID) < (b.source.rawValue, b.deviceID)
    }
}

extension HealthSample {
    public var origin: SampleOrigin { SampleOrigin(source: source, deviceID: deviceID) }
}

/// A period total, the origins it was taken from and why, so the number stays traceable.
public struct ResolvedTotal: Equatable, Sendable {
    public let total: Double
    /// The origin that contributed most.
    public let origin: SampleOrigin
    public let origins: [SampleOrigin]
    public let sampleCount: Int
    /// Hour buckets that had data.
    public let coveredBuckets: Int
    public let sampleIDs: [UUID]
    /// Why the total is only an estimate (Codex review P1-003 R2-2). Empty = no known reservation.
    public let caveats: [TotalCaveat]

    public var source: DataSourceKind { origin.source }
    /// Health totals stay "plausibel" until Apple's own statistics are used (HKStatisticsCollectionQuery, R2).
    public var isProvisional: Bool { !caveats.isEmpty }
}

/// Reservations about a resolved total, shown with it and kept in exports.
public enum TotalCaveat: String, Codable, Sendable, CaseIterable, Comparable {
    /// Added up from single Health samples, not from Apple's merged statistics.
    case healthRawSamples = "health_raw_samples"
    /// In at least one hour, samples of another app or device were left out to avoid counting twice.
    case overlapDropped = "overlap_dropped"
    /// Some samples do not name their device (older rows, or HealthKit gave no identifier).
    case unknownOrigin = "unknown_origin"

    public var label: String {
        switch self {
        case .healthRawSamples: "vorläufig: aus Einzelwerten von Apple Health summiert"
        case .overlapDropped: "vorläufig: Überschneidung mehrerer Geräte, je Stunde nur eines gezählt"
        case .unknownOrigin: "vorläufig: Herkunftsgerät teilweise unbekannt"
        }
    }

    public static func < (a: TotalCaveat, b: TotalCaveat) -> Bool { a.rawValue < b.rawValue }
}

/// Chooses between overlapping data without averaging or adding it twice (Review 3.2 §3 C, §4).
public enum DataSourceResolver {
    /// Legacy default order; kinds now use `SourcePolicy.automaticOrder`.
    public static let defaultPriority: [DataSourceKind] = [.bluetoothStandard, .colmiRing, .ouraCloud, .appleHealth, .manual]

    /// Point values (pulse, SpO₂ …): within each time bucket keep one origin (policy) and, inside that
    /// origin, one measuring path (live before history), so a live value and the history entry of the
    /// same minute never both count.
    public static func resolvePoints(_ samples: [HealthSample], bucket: TimeInterval = 60,
                                     policy: SourcePolicy) -> [HealthSample] {
        let usable = samples.filter { $0.quality.usableForAnalysis }
        let grouped = Dictionary(grouping: usable) { Int(($0.start.timeIntervalSince1970 / bucket).rounded(.down)) }
        return grouped.keys.sorted().flatMap { key -> [HealthSample] in
            let group = grouped[key] ?? []
            guard let kind = group.first?.kind,
                  let best = policy.choose(kind: kind, among: Set(group.map(\.origin)))?.origin else { return [] }
            let fromOrigin = group.filter { $0.origin == best }
            let method = MeasurementMethod.preference.first { m in fromOrigin.contains { $0.method == m } }
            return fromOrigin.filter { $0.method == method }.sorted { $0.start < $1.start }
        }
    }

    public static func resolvePoints(_ samples: [HealthSample], bucket: TimeInterval = 60,
                                     priority: [DataSourceKind] = defaultPriority,
                                     devicePriority: [String] = []) -> [HealthSample] {
        resolvePoints(samples, bucket: bucket, policy: SourcePolicy(sourceOrder: priority, devicePriority: devicePriority))
    }

    /// Counters (steps, energy …): per hour the best origin present, then summed over the hours. Gaps of the
    /// preferred source are filled by the next one, but no hour is counted from two origins.
    /// Inside one origin, samples written by different apps or devices (`originDetail`, e.g. iPhone and
    /// Watch in Apple Health) usually describe the same activity twice. Per hour only one of them counts:
    /// the one with the largest total, ties by name. This avoids double counting; it can under-count when
    /// two devices really recorded different activity in the same hour (documented in HEALTH-DATA-SPEC).
    /// Samples without a device identity (`HealthOrigin.identifiesDevice`) share one group and are not
    /// separated; the result then carries `.unknownOrigin` instead of claiming to be exact.
    /// Limit: a sample is booked to the hour it starts in.
    public static func resolveTotal(_ samples: [HealthSample], bucket: TimeInterval = 3_600,
                                    policy: SourcePolicy) -> ResolvedTotal? {
        let usable = samples.filter { $0.quality.usableForAnalysis }
        let grouped = Dictionary(grouping: usable) { Int(($0.start.timeIntervalSince1970 / bucket).rounded(.down)) }
        var chosen: [HealthSample] = []
        var caveats = Set<TotalCaveat>()
        for key in grouped.keys.sorted() {
            let group = grouped[key] ?? []
            guard let kind = group.first?.kind,
                  let best = policy.choose(kind: kind, among: Set(group.map(\.origin)))?.origin else { continue }
            let fromOrigin = group.filter { $0.origin == best }
            let kept = onePerDetail(fromOrigin)
            if kept.count < fromOrigin.count { caveats.insert(.overlapDropped) }
            chosen += kept
        }
        guard !chosen.isEmpty else { return nil }
        let fromHealth = chosen.filter { $0.source == .appleHealth }
        if !fromHealth.isEmpty { caveats.insert(.healthRawSamples) }
        if fromHealth.contains(where: { !HealthOrigin.identifiesDevice($0.originDetail) }) { caveats.insert(.unknownOrigin) }
        let byOrigin = Dictionary(grouping: chosen, by: \.origin)
        let main = byOrigin.max { a, b in
            let va = a.value.reduce(0) { $0 + $1.value }, vb = b.value.reduce(0) { $0 + $1.value }
            return va != vb ? va < vb : a.key > b.key
        }?.key ?? chosen[0].origin
        return ResolvedTotal(total: chosen.reduce(0) { $0 + $1.value }, origin: main, origins: byOrigin.keys.sorted(),
                             sampleCount: chosen.count, coveredBuckets: Set(chosen.map {
                                 Int(($0.start.timeIntervalSince1970 / bucket).rounded(.down)) }).count,
                             sampleIDs: chosen.map(\.id), caveats: caveats.sorted())
    }

    /// Keeps the samples of one `originDetail`: the largest total, ties by the detail text (nil sorts first).
    /// Provisional rule (R2-2): it is marked in `ResolvedTotal.caveats` whenever it drops something.
    static func onePerDetail(_ samples: [HealthSample]) -> [HealthSample] {
        let byDetail = Dictionary(grouping: samples) { $0.originDetail ?? "" }
        guard byDetail.count > 1 else { return samples }
        let best = byDetail.max { a, b in
            let va = a.value.reduce(0) { $0 + $1.value }, vb = b.value.reduce(0) { $0 + $1.value }
            return va != vb ? va < vb : a.key > b.key
        }?.key
        return byDetail[best ?? ""] ?? samples
    }

    public static func resolveTotal(_ samples: [HealthSample], priority: [DataSourceKind] = defaultPriority,
                                    devicePriority: [String] = []) -> ResolvedTotal? {
        resolveTotal(samples, policy: SourcePolicy(sourceOrder: priority, devicePriority: devicePriority))
    }
}
