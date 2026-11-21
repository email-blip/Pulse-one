import Foundation
import PulseCore
import SwiftData

/// Read access to stored samples for every feature (TODAY, HEALTH, Intelligence, Coach, Nutrition).
/// Returns only samples usable for analysis (`valid` / `plausible`), never invented values.
@MainActor
struct SampleReader {
    let context: ModelContext

    /// Samples of `kinds` that start at or after `since`. With a `profileID`, only that person's samples;
    /// unresolved samples (no profile) are left out, because they may belong to someone else.
    func samples(_ kinds: Set<SampleKind>, since: Date, profileID: UUID?) -> [HealthSample] {
        let raws = kinds.map(\.rawValue)
        var descriptor = FetchDescriptor<StoredSample>(
            predicate: #Predicate { raws.contains($0.kindRaw) && $0.start >= since },
            sortBy: [SortDescriptor(\.start)])
        descriptor.includePendingChanges = true
        let rows = (try? context.fetch(descriptor)) ?? []
        return rows.compactMap(\.sample).filter { sample in
            sample.quality.usableForAnalysis && (profileID == nil || sample.profileID == profileID)
        }
    }

    /// Daily values of one kind over the last `days` days (today included).
    func daily(_ kind: SampleKind, days: Int, profileID: UUID?, calendar: Calendar = .current, now: Date = .now) -> [DailyValue] {
        let start = calendar.date(byAdding: .day, value: -days, to: calendar.startOfDay(for: now)) ?? now
        return DailySeries.build(samples([kind], since: start, profileID: profileID), kind: kind, calendar: calendar)
    }

    /// Newest sample of a kind, if any.
    func latest(_ kind: SampleKind, within days: Int = 30, profileID: UUID?, now: Date = .now) -> HealthSample? {
        let start = now.addingTimeInterval(-Double(days) * 86_400)
        return samples([kind], since: start, profileID: profileID).max { $0.start < $1.start }
    }
}
