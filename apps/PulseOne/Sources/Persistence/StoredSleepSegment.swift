import Foundation
import PulseCore
import SwiftData

/// One sleep phase interval as the ring reported it (`SleepSegment`, team 01 M1). The raw code is always
/// kept; an unknown code is stored as phase `unknown`, never guessed. Rows are only replaced night by
/// night through `SleepSegmentSync`; nothing here deletes a night the ring no longer sends.
@Model
final class StoredSleepSegment {
    var segmentID: UUID
    var sessionID: UUID
    var subjectID: UUID?
    var rawCode: Int
    var phaseRaw: String
    var start: Date
    var end: Date
    var sourceRaw: String
    var deviceID: String
    var firmware: String?
    var importedAt: Date

    init(_ s: SleepSegment, importedAt: Date) {
        segmentID = s.id
        sessionID = s.sessionID
        subjectID = s.subjectID
        rawCode = s.rawCode
        phaseRaw = s.phase.rawValue
        start = s.start
        end = s.end
        sourceRaw = s.source.rawValue
        deviceID = s.deviceID
        firmware = s.firmware
        self.importedAt = importedAt
    }

    /// Back to the contract type. The phase is derived from the raw code again, so a later app version
    /// that learns a new code reads old rows correctly; nil only for an unknown source.
    var segment: SleepSegment? {
        guard let source = DataSourceKind(rawValue: sourceRaw) else { return nil }
        let phase = source == .colmiRing ? SleepPhase.colmi(code: rawCode) : (SleepPhase(rawValue: phaseRaw) ?? .unknown)
        return SleepSegment(id: segmentID, subjectID: subjectID, sessionID: sessionID, rawCode: rawCode, phase: phase,
                            start: start, end: end, source: source, deviceID: deviceID, firmware: firmware)
    }
}

/// Applies sleep segment plans to SwiftData and answers the window queries of the timeline (team 03 reads).
@MainActor
struct SleepSegmentStore {
    let context: ModelContext

    /// Stored segments of the given sessions.
    func segments(sessions: Set<UUID>) throws -> [SleepSegment] {
        guard !sessions.isEmpty else { return [] }
        let ids = Array(sessions)
        return try context.fetch(FetchDescriptor<StoredSleepSegment>(predicate: #Predicate { ids.contains($0.sessionID) }))
            .compactMap(\.segment)
    }

    /// Stores one batch of nights. A changed night replaces its stored rows; equal nights stay untouched.
    @discardableResult
    func ingest(_ incoming: [SleepSegment], now: Date = .now) throws -> SleepSegmentPlan {
        guard !incoming.isEmpty else { return SleepSegmentPlan() }
        let plan = SleepSegmentSync.plan(incoming: incoming, existing: try segments(sessions: Set(incoming.map(\.sessionID))))
        guard !plan.isEmpty else { return plan }
        if !plan.replacedSessions.isEmpty {
            let ids = Array(plan.replacedSessions)
            for row in try context.fetch(FetchDescriptor<StoredSleepSegment>(predicate: #Predicate { ids.contains($0.sessionID) })) {
                context.delete(row)
            }
        }
        for segment in plan.inserts { context.insert(StoredSleepSegment(segment, importedAt: now)) }
        try context.save()
        return plan
    }

    /// Segments that overlap the window, oldest first. Group with `SleepSegmentSync.nights`.
    func segments(in window: DateInterval, subjectID: UUID? = nil) throws -> [SleepSegment] {
        let from = window.start, to = window.end
        let descriptor = FetchDescriptor<StoredSleepSegment>(predicate: #Predicate { $0.end > from && $0.start < to },
                                                             sortBy: [SortDescriptor(\.start)])
        let rows = try context.fetch(descriptor).compactMap(\.segment)
        guard let subjectID else { return rows }
        return rows.filter { $0.subjectID == subjectID || $0.subjectID == nil }
    }

    /// Whole nights that overlap the window (a night crossing the window edge is returned complete).
    func nights(in window: DateInterval, subjectID: UUID? = nil) throws -> [SleepNight] {
        let touched = Set(try segments(in: window, subjectID: subjectID).map(\.sessionID))
        return SleepSegmentSync.nights(try segments(sessions: touched))
    }
}

/// Window reads of stored samples as `MeasurementPoint`s for the timeline (team 03 reads, team 01 owns).
@MainActor
struct MeasurementPointStore {
    let context: ModelContext

    /// Points of the given kinds whose interval overlaps the window, oldest first. Quality filtering and
    /// aggregation stay in `TimelineQuery`, so the caller sees the same rules as the tests.
    func points(kinds: Set<SampleKind>, in window: DateInterval) throws -> [MeasurementPoint] {
        guard !kinds.isEmpty else { return [] }
        let kindList = kinds.map(\.rawValue)
        let from = window.start, to = window.end
        let descriptor = FetchDescriptor<StoredSample>(predicate: #Predicate {
            kindList.contains($0.kindRaw) && $0.end >= from && $0.start <= to
        }, sortBy: [SortDescriptor(\.start)])
        return try context.fetch(descriptor).compactMap { row in
            row.sample.map { MeasurementPoint($0, receivedAt: $0.receivedAt) }
        }
    }

    /// Points of one timeline track.
    func points(for track: TimelineTrack, in window: DateInterval) throws -> [MeasurementPoint] {
        try points(kinds: Set(track.sampleKinds), in: window)
    }
}
