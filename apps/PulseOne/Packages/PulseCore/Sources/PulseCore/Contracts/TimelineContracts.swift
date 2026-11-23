import Foundation

/// Tracks that can be stacked on the shared time axis of the Verlauf ("Tonspuren").
public enum TimelineTrack: String, Codable, CaseIterable, Sendable {
    case heartRate, hrv, spo2, stress, sleepPhases, movement, training, notes, coachInsights

    /// Sample kinds drawn on a value track; empty for event and phase tracks.
    public var sampleKinds: [SampleKind] {
        switch self {
        case .heartRate: [.heartRate]
        case .hrv: [.ringHRV, .heartRateVariability]
        case .spo2: [.oxygenSaturation]
        case .stress: [.ringStress]
        case .movement: [.steps, .activeEnergy]
        case .sleepPhases, .training, .notes, .coachInsights: []
        }
    }
}

/// Coarse ranges for the picker; free zoom happens inside a range.
public enum TimelineRange: String, Codable, CaseIterable, Sendable {
    case day, week, month, quarter, year

    /// Above this span the charts aggregate (marked as such); below it they show original points.
    public static let originalResolutionLimit: TimeInterval = 2 * 24 * 3600
}

/// The one state every visible track, the spoken review and the coach annotations share.
public struct TimelineState: Equatable, Sendable {
    public var range: TimelineRange
    /// Visible window in absolute time; all tracks use this same domain.
    public var visible: DateInterval
    /// Shared vertical cursor; may sit between points (then no value is invented).
    public var cursor: Date?
    public var tracks: [TimelineTrack]
    /// The original point the user picked (nearest real measurement, with its own time).
    public var selected: MeasurementPoint?
    /// The sleep interval the user picked in the hypnogram.
    public var selectedSegment: SleepSegment?

    public init(range: TimelineRange, visible: DateInterval, cursor: Date? = nil,
                tracks: [TimelineTrack] = [.heartRate], selected: MeasurementPoint? = nil,
                selectedSegment: SleepSegment? = nil) {
        self.range = range
        self.visible = visible
        self.cursor = cursor
        self.tracks = tracks
        self.selected = selected
        self.selectedSegment = selectedSegment
    }

    /// Zoom level as seconds visible on screen.
    public var span: TimeInterval { visible.duration }

    public var showsOriginalPoints: Bool { span <= TimelineRange.originalResolutionLimit }

    /// Nearest real point to the cursor within `tolerance`; nil if the cursor sits in a gap.
    public static func nearest(to time: Date, in points: [MeasurementPoint],
                               tolerance: TimeInterval) -> MeasurementPoint? {
        guard let best = points.min(by: { abs($0.measuredAt.timeIntervalSince(time)) < abs($1.measuredAt.timeIntervalSince(time)) })
        else { return nil }
        return abs(best.measuredAt.timeIntervalSince(time)) <= tolerance ? best : nil
    }
}

/// A spoken or shown sentence tied to a place on the time axis (audio timeline, "Warum?").
public struct NarrationCue: Identifiable, Equatable, Sendable, Codable {
    public let id: UUID
    public let text: String
    /// Time window the sentence talks about; the cursor moves there while it is spoken.
    public let anchor: DateInterval?
    public let track: TimelineTrack?

    public init(id: UUID = UUID(), text: String, anchor: DateInterval?, track: TimelineTrack?) {
        self.id = id
        self.text = text
        self.anchor = anchor
        self.track = track
    }
}
