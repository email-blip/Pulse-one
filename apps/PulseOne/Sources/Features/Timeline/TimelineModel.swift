import Foundation
import Observation
import PulseCore
import SwiftData

/// Where the Verlauf opens: from a tile, the sleep preview or a piece of evidence behind "Warum?".
struct TimelineFocus: Hashable {
    var track: TimelineTrack
    /// Cursor position to show first (the tile's value time, the evidence moment).
    var cursor: Date?
    /// Window to show (a night, an evidence window); nil = the last 24 hours.
    var window: DateInterval?
}

/// A workout or a coach statement on the time axis.
struct TimelineEvent: Identifiable, Equatable {
    enum Kind: String { case workout, coach }
    let id: String
    let kind: Kind
    let interval: DateInterval
    let title: String
    let detail: String
}

/// One line of the cursor read-out.
struct CursorRow: Identifiable, Equatable {
    let track: TimelineTrack
    let title: String
    /// "64 bpm", or "–" where nothing was measured.
    let value: String
    /// Original measuring time ("14:05") or the bucket ("14:00–15:00").
    let time: String
    /// "Mittel aus 12 Werten", "keine Messung an dieser Stelle".
    let note: String?
    /// Source details, shown on request.
    let source: String?
    var id: TimelineTrack { track }
}

/// State and data of the Verlauf. One `TimelineState` (contract) drives every track: the same window,
/// the same cursor. Values come from the store through team 01's queries; nothing is filled or invented.
@MainActor
@Observable
final class TimelineModel {
    /// Value tracks in drawing order (the hypnogram sits above them, events below).
    static let valueTracks: [TimelineTrack] = [.heartRate, .hrv, .spo2, .stress, .movement]
    static let minimumSpan: TimeInterval = 20 * 60
    static let maximumSpan: TimeInterval = 400 * 86_400

    private(set) var range: TimelineRange = .day
    private(set) var visible: DateInterval
    private(set) var cursor: Date?
    private(set) var selectedSegment: SleepSegment?
    private(set) var bounds: DateInterval
    private(set) var now: Date

    private(set) var points: [TimelineTrack: [MeasurementPoint]] = [:]
    private(set) var kinds: [TimelineTrack: SampleKind] = [:]
    private(set) var segments: [SleepSegment] = []
    private(set) var events: [TimelineEvent] = []
    /// Ids of values that just arrived (they land with motion); cleared after the animation.
    private(set) var landing: Set<String> = []
    private(set) var hasLoaded = false
    /// Bumped whenever drawable data change, so views can key animations on it.
    private(set) var dataVersion = 0

    private var loaded: DateInterval?
    private var known: Set<UUID> = []
    private var bucketCache: [String: [TrackValue]] = [:]
    let calendar: Calendar

    init(now: Date = TimelineClock.now, calendar: Calendar = .current) {
        self.now = now
        self.calendar = calendar
        visible = DateInterval(start: now.addingTimeInterval(-86_400), end: now)
        bounds = DateInterval(start: now.addingTimeInterval(-367 * 86_400), end: now.addingTimeInterval(30 * 60))
    }

    /// The contract view of the state (spoken review and coach markers read the same).
    var state: TimelineState {
        TimelineState(range: range, visible: visible, cursor: cursor, tracks: tracks,
                      selected: selectedPoint, selectedSegment: selectedSegment)
    }

    var resolution: TimelineResolution { TimelineQuery.resolution(for: visible) }

    /// Tracks with something to show in the loaded data.
    var tracks: [TimelineTrack] {
        var result: [TimelineTrack] = []
        if !segments.isEmpty { result.append(.sleepPhases) }
        result += Self.valueTracks.filter { !(points[$0] ?? []).isEmpty }
        if events.contains(where: { $0.kind == .workout }) { result.append(.training) }
        if events.contains(where: { $0.kind == .coach }) { result.append(.coachInsights) }
        return result
    }

    // MARK: Opening and loading

    func open(_ focus: TimelineFocus?) {
        now = TimelineClock.now
        bounds = DateInterval(start: now.addingTimeInterval(-367 * 86_400), end: now.addingTimeInterval(30 * 60))
        range = .day
        if let window = focus?.window {
            visible = clamp(window)
        } else if let around = focus?.cursor {
            let end = min(bounds.end, max(around.addingTimeInterval(6 * 3600), now))
            visible = clamp(DateInterval(start: end.addingTimeInterval(-86_400), end: end))
        } else {
            visible = clamp(DateInterval(start: now.addingTimeInterval(-86_400), end: now))
        }
        cursor = focus?.cursor
        selectedSegment = nil
    }

    /// Reads the window (plus a margin for panning) from the store. Later calls only stage values that were
    /// received and measured just now as "landing"; synced history appears in place.
    func reload(context: ModelContext, profileID: UUID?, coachInsights: [CoachInsight]) {
        let margin = max(visible.duration, 86_400)
        let wanted = DateInterval(start: max(bounds.start, visible.start.addingTimeInterval(-margin)),
                                  end: min(bounds.end, visible.end.addingTimeInterval(margin)))
        let kindsToRead = Set(Self.valueTracks.flatMap(\.sampleKinds) + [.trainingDuration])
        let read = (try? MeasurementPointStore(context: context).points(kinds: kindsToRead, in: wanted)) ?? []
        let mine = read.filter { profileID == nil || $0.subjectID == profileID }
        var byTrack: [TimelineTrack: [MeasurementPoint]] = [:]
        var chosen: [TimelineTrack: SampleKind] = [:]
        for track in Self.valueTracks {
            let trackPoints = TimelineQuery.points(for: track, in: wanted, from: mine, now: now.addingTimeInterval(60))
            // One kind per track (ring HRV and Apple SDNN are different methods; steps before energy).
            guard let kind = track.sampleKinds.first(where: { kind in trackPoints.contains { $0.kind == kind } }) else { continue }
            chosen[track] = kind
            byTrack[track] = trackPoints.filter { $0.kind == kind }
        }
        let fresh = hasLoaded ? LiveArrival.arrivals(known: known, current: byTrack[.heartRate] ?? [], now: now) : []
        points = byTrack
        kinds = chosen
        known = Set(byTrack.values.flatMap { $0.map(\.id) })
        segments = (try? SleepSegmentStore(context: context).segments(in: wanted, subjectID: profileID)) ?? []
        let workouts = mine.filter { $0.kind == .trainingDuration && $0.quality.usableForAnalysis }.map { point in
            TimelineEvent(id: "workout-\(point.id.uuidString)", kind: .workout,
                          interval: DateInterval(start: point.measuredAt, end: max(point.measuredUntil, point.measuredAt)),
                          title: "Training", detail: TileSummary.duration(point.value))
        }
        let marks = coachInsights.filter { wanted.contains($0.createdAt) }.map { insight in
            TimelineEvent(id: "coach-\(insight.id.uuidString)", kind: .coach,
                          interval: DateInterval(start: insight.createdAt, duration: 0),
                          title: "ROOK", detail: insight.interpretation)
        }
        events = (workouts + marks).sorted { $0.interval.start < $1.interval.start }
        loaded = wanted
        bucketCache = [:]
        hasLoaded = true
        dataVersion += 1
        landing = Set(fresh.map { $0.id.uuidString })
    }

    /// True when the visible window left the loaded data (after panning or zooming out).
    var needsReload: Bool {
        guard let loaded else { return true }
        return visible.start < loaded.start || visible.end > loaded.end
    }

    func clearLanding() { landing = [] }

    // MARK: Drawable values

    func values(for track: TimelineTrack) -> [TrackValue] {
        guard let kind = kinds[track], let all = points[track], !all.isEmpty else { return [] }
        let level = resolution
        if level == .original {
            let window = DateInterval(start: visible.start.addingTimeInterval(-TrackSeries.expectedInterval(kind)),
                                      end: visible.end.addingTimeInterval(TrackSeries.expectedInterval(kind)))
            return TrackSeries.values(TrackSeries.slice(all, in: window), kind: kind, in: window, resolution: .original,
                                      calendar: calendar)
        }
        // Buckets over the whole loaded data once per resolution, then cut to the window (fast pinch and pan).
        let key = "\(track.rawValue)-\(level)"
        let buckets: [TrackValue]
        if let cached = bucketCache[key] {
            buckets = cached
        } else {
            let span = loaded ?? visible
            buckets = TrackSeries.values(all, kind: kind, in: span, resolution: level, calendar: calendar)
            bucketCache[key] = buckets
        }
        return buckets.filter { $0.end >= visible.start && $0.start <= visible.end }
    }

    var visibleSegments: [SleepSegment] {
        segments.filter { $0.end > visible.start && $0.start < visible.end }.sorted { $0.start < $1.start }
    }

    var visibleEvents: [TimelineEvent] {
        events.filter { $0.interval.end >= visible.start && $0.interval.start <= visible.end }
    }

    // MARK: Cursor

    /// The original point the cursor picked on the first value track (contract `selected`).
    var selectedPoint: MeasurementPoint? {
        guard let cursor, resolution == .original else { return nil }
        for track in Self.valueTracks {
            if let kind = kinds[track], let all = points[track],
               let point = TrackSeries.pick(at: cursor, in: nearby(all, cursor, kind), kind: kind) {
                return point
            }
        }
        return nil
    }

    private func nearby(_ all: [MeasurementPoint], _ time: Date, _ kind: SampleKind) -> ArraySlice<MeasurementPoint> {
        let reach = max(TrackSeries.cursorTolerance(kind), 3600)
        return TrackSeries.slice(all, in: DateInterval(start: time.addingTimeInterval(-reach), end: time.addingTimeInterval(reach)))
    }

    func setCursor(_ time: Date?) {
        guard let time else {
            cursor = nil
            selectedSegment = nil
            return
        }
        let clamped = min(max(time, visible.start), visible.end)
        cursor = clamped
        selectedSegment = Hypnogram.segment(at: clamped, in: segments)
    }

    func select(_ segment: SleepSegment) {
        cursor = segment.start.addingTimeInterval(segment.duration / 2)
        selectedSegment = segment
    }

    /// Accessible step to the previous/next original point of the first track with data.
    func stepCursor(forward: Bool) {
        guard let track = Self.valueTracks.first(where: { !(points[$0] ?? []).isEmpty }), let all = points[track] else { return }
        let from = cursor ?? (forward ? visible.start : visible.end)
        guard let next = TrackSeries.step(from: from, in: all, forward: forward) else { return }
        if !visible.contains(next.measuredAt) {
            let shift = next.measuredAt.timeIntervalSince(forward ? visible.end : visible.start) + (forward ? 1 : -1) * visible.duration * 0.2
            visible = clamp(DateInterval(start: visible.start.addingTimeInterval(shift), duration: visible.duration))
        }
        setCursor(next.measuredAt)
    }

    /// Read-out of every visible track at the cursor. A cursor in a gap shows "keine Messung", never a value.
    var cursorRows: [CursorRow] {
        guard let cursor else { return [] }
        let clock = Self.clock(calendar)
        return Self.valueTracks.compactMap { track in
            guard let kind = kinds[track], let all = points[track] else { return nil }
            let title = MetricStyleName.name(kind)
            if resolution == .original {
                guard let point = TrackSeries.pick(at: cursor, in: nearby(all, cursor, kind), kind: kind) else {
                    return CursorRow(track: track, title: title, value: "–", time: cursor.formatted(clock),
                                     note: "keine Messung an dieser Stelle", source: nil)
                }
                let time = point.isInterval
                    ? "\(point.measuredAt.formatted(clock))–\(point.measuredUntil.formatted(clock))"
                    : point.measuredAt.formatted(clock)
                let source = "\(point.source.title) · \(Self.methodText(point.method)) · empfangen \(point.receivedAt.formatted(clock)) · Qualität \(point.quality.label)"
                return CursorRow(track: track, title: title, value: "\(kind.display(point.value)) \(kind.displayUnit)",
                                 time: time, note: nil, source: source)
            }
            let drawn = values(for: track)
            guard let bucket = TrackSeries.bucket(at: cursor, in: drawn) else {
                return CursorRow(track: track, title: title, value: "–", time: cursor.formatted(Self.dayClock(calendar)),
                                 note: "keine Messung in diesem Abschnitt", source: nil)
            }
            let span = resolution == .daily
                ? bucket.start.formatted(Self.dayOnly(calendar))
                : "\(bucket.start.formatted(Self.dayClock(calendar)))–\(bucket.end.formatted(clock))"
            let what = kind.aggregation == .cumulative ? "Summe aus \(bucket.count) Werten"
                : "Mittel aus \(bucket.count) Werten (\(kind.display(bucket.low))–\(kind.display(bucket.high)))"
            return CursorRow(track: track, title: title, value: "\(kind.display(bucket.value)) \(kind.displayUnit)",
                             time: span, note: what, source: nil)
        }
    }

    var cursorEvent: TimelineEvent? {
        guard let cursor else { return nil }
        return events.first { $0.kind == .workout && $0.interval.start <= cursor && cursor <= $0.interval.end }
    }

    // MARK: Window

    func setRange(_ newRange: TimelineRange) {
        range = newRange
        let span = Self.span(of: newRange)
        let end = newRange == .day ? min(bounds.end, max(visible.end, visible.start.addingTimeInterval(span))) : now
        visible = clamp(DateInterval(start: end.addingTimeInterval(-span), end: end))
        if let cursor, !visible.contains(cursor) { setCursor(nil) }
    }

    /// Moves the window by `seconds` (negative = into the past). Never beyond the data bounds.
    func pan(from start: DateInterval, by seconds: TimeInterval) {
        visible = clamp(DateInterval(start: start.start.addingTimeInterval(seconds), duration: start.duration))
    }

    func page(forward: Bool) {
        pan(from: visible, by: (forward ? 1 : -1) * visible.duration * 0.8)
    }

    /// Zooms from `start` by `factor` (>1 = closer) around `anchor` (0…1 across the width).
    func zoom(from start: DateInterval, factor: Double, anchor: Double) {
        let span = min(max(start.duration / max(factor, 0.01), Self.minimumSpan), Self.maximumSpan)
        let pivot = start.start.addingTimeInterval(start.duration * anchor)
        visible = clamp(DateInterval(start: pivot.addingTimeInterval(-span * anchor), duration: span))
    }

    func time(atFraction fraction: Double) -> Date {
        visible.start.addingTimeInterval(visible.duration * min(max(fraction, 0), 1))
    }

    func fraction(of time: Date) -> Double {
        guard visible.duration > 0 else { return 0 }
        return time.timeIntervalSince(visible.start) / visible.duration
    }

    private func clamp(_ window: DateInterval) -> DateInterval {
        let span = min(max(window.duration, Self.minimumSpan), bounds.duration)
        var start = window.start
        if start.addingTimeInterval(span) > bounds.end { start = bounds.end.addingTimeInterval(-span) }
        if start < bounds.start { start = bounds.start }
        return DateInterval(start: start, duration: span)
    }

    static func span(of range: TimelineRange) -> TimeInterval {
        switch range {
        case .day: 86_400
        case .week: 7 * 86_400
        case .month: 30 * 86_400
        case .quarter: 91 * 86_400
        case .year: 365 * 86_400
        }
    }

    // MARK: Formatting

    static func clock(_ calendar: Calendar) -> Date.FormatStyle {
        Date.FormatStyle(date: .omitted, time: .shortened, locale: Locale(identifier: "de_DE"), calendar: calendar,
                         timeZone: calendar.timeZone)
    }

    static func dayClock(_ calendar: Calendar) -> Date.FormatStyle {
        Date.FormatStyle(locale: Locale(identifier: "de_DE"), calendar: calendar, timeZone: calendar.timeZone)
            .day(.twoDigits).month(.twoDigits).hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)
    }

    static func dayOnly(_ calendar: Calendar) -> Date.FormatStyle {
        Date.FormatStyle(locale: Locale(identifier: "de_DE"), calendar: calendar, timeZone: calendar.timeZone)
            .weekday(.abbreviated).day(.twoDigits).month(.twoDigits)
    }

    static func methodText(_ method: MeasurementMethod) -> String {
        switch method {
        case .liveSensor: "Live-Messung"
        case .deviceHistory: "Verlauf vom Gerät"
        case .healthStore: "Apple Health"
        case .cloudAPI: "Cloud"
        case .manualEntry: "Eingabe"
        case .unknown: "Weg unbekannt"
        }
    }
}

/// Short track names (same as the DesignKit tile names).
enum MetricStyleName {
    static func name(_ kind: SampleKind) -> String { MetricStyle.of(kind).name }
}
