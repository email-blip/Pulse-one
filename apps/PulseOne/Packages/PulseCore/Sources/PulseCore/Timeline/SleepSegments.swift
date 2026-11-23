import Foundation

// Sleep phases as real intervals (team 01, M1). Source: the ring's `BC 27` answer, parsed by
// `ColmiHistory.parseSleep`. Each stage follows the previous one without a gap, starting at the
// session start (checked on the R03 2026-11-23: the stage minutes add up exactly to end − start).

extension RingHistoryMapper {
    /// Session id of the ring night that ends on `wakeDay`: one night per wake day and ring.
    public func sleepSessionID(nightEnding end: Date) -> UUID {
        let parts = calendar.dateComponents([.year, .month, .day], from: end)
        let day = String(format: "%04d%02d%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
        return StableID.uuid("colmi-sleep|\(deviceID)|night\(day)")
    }

    /// One `SleepSegment` per ring stage, with real start and end times. Stage start = session start plus
    /// the elapsed minutes of the earlier stages, so a daylight-saving night keeps its true durations.
    /// Unknown stage codes stay `unknown` with their raw code; a session without stages yields nothing.
    public func sleepSegments(_ sessions: [SleepSession], subjectID: UUID? = nil, firmware: String? = nil) -> [SleepSegment] {
        sessions.flatMap { session -> [SleepSegment] in
            guard !session.stages.isEmpty, let span = session.interval(today: today, calendar: calendar),
                  span.end <= today.addingTimeInterval(MeasurementNormalizer.futureTolerance) else { return [] }
            let sessionID = sleepSessionID(nightEnding: span.end)
            var cursor = span.start
            return session.stages.enumerated().map { index, stage in
                let end = cursor.addingTimeInterval(Double(stage.minutes) * 60)
                defer { cursor = end }
                return SleepSegment(id: StableID.uuid("\(sessionID.uuidString)|\(index)|\(stage.rawType)|\(stage.minutes)"),
                                    subjectID: subjectID, sessionID: sessionID, rawCode: stage.rawType,
                                    phase: SleepPhase.colmi(code: stage.rawType), start: cursor, end: end,
                                    source: .colmiRing, deviceID: deviceID, firmware: firmware)
            }
        }
    }
}

/// How a batch of segments changes the store. The ring sends whole nights; a night that changed between
/// two syncs (it grew, or the ring revised it) replaces the stored version completely. Nights the ring no
/// longer sends stay stored.
public struct SleepSegmentPlan: Equatable, Sendable {
    public var inserts: [SleepSegment] = []
    /// Sessions whose stored segments are removed before the inserts.
    public var replacedSessions: Set<UUID> = []
    public var unchangedSessions = 0

    public init() {}

    public var isEmpty: Bool { inserts.isEmpty && replacedSessions.isEmpty }
}

public enum SleepSegmentSync {
    /// - Parameter existing: stored segments of the sessions in `incoming` (others are ignored).
    public static func plan(incoming: [SleepSegment], existing: [SleepSegment]) -> SleepSegmentPlan {
        var plan = SleepSegmentPlan()
        let stored = Dictionary(grouping: existing, by: \.sessionID)
        // Duplicate segments inside one batch (same id) are dropped, the first one wins.
        var seen: Set<UUID> = []
        let unique = incoming.filter { seen.insert($0.id).inserted }
        for (session, segments) in Dictionary(grouping: unique, by: \.sessionID) {
            let new = segments.sorted { $0.start < $1.start }
            if let old = stored[session]?.sorted(by: { $0.start < $1.start }) {
                if same(old, new) { plan.unchangedSessions += 1; continue }
                plan.replacedSessions.insert(session)
            }
            plan.inserts += new
        }
        plan.inserts.sort { ($0.start, $0.id.uuidString) < ($1.start, $1.id.uuidString) }
        return plan
    }

    static func same(_ a: [SleepSegment], _ b: [SleepSegment]) -> Bool {
        a.count == b.count && zip(a, b).allSatisfy {
            $0.start == $1.start && $0.end == $1.end && $0.rawCode == $1.rawCode && $0.subjectID == $1.subjectID
        }
    }

    /// Groups stored segments into nights (one per session), oldest first.
    public static func nights(_ segments: [SleepSegment]) -> [SleepNight] {
        Dictionary(grouping: segments, by: \.sessionID)
            .map { SleepNight(sessionID: $0.key, segments: $0.value) }
            .sorted { ($0.inBed?.start ?? .distantPast) < ($1.inBed?.start ?? .distantPast) }
    }
}
