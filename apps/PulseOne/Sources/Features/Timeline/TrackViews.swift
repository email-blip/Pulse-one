import Charts
import os
import PulseCore
import SwiftUI

// Track views of the Verlauf. All of them map time to x the same way (window start = 0, end = width,
// no inner padding), so the hypnogram, the value tracks, the events and the shared cursor line up.

/// One value track (pulse, HRV, SpO₂, stress, movement) drawn with Swift Charts. Equatable, so moving the
/// cursor does not redraw the marks.
struct ValueTrackChart: View, Equatable {
    let kind: SampleKind
    let values: [TrackValue]
    let gaps: [DateInterval]
    let window: DateInterval
    let yDomain: ClosedRange<Double>
    let landing: Set<String>
    let showsPoints: Bool

    nonisolated static func == (lhs: ValueTrackChart, rhs: ValueTrackChart) -> Bool {
        lhs.kind == rhs.kind && lhs.window == rhs.window && lhs.yDomain == rhs.yDomain && lhs.showsPoints == rhs.showsPoints
            && lhs.landing == rhs.landing && lhs.gaps == rhs.gaps && lhs.values == rhs.values
    }

    var body: some View {
        let tint = MetricStyle.of(kind).color
        let _ = TimelineProbe.chartBody(kind: kind, marks: values.count)
        Chart {
            // Gaps: a faint band, never a line to zero and never a bridged line.
            ForEach(gaps, id: \.start) { gap in
                RectangleMark(xStart: .value("Beginn", gap.start), xEnd: .value("Ende", gap.end),
                              yStart: .value("unten", yDomain.lowerBound), yEnd: .value("oben", yDomain.upperBound))
                    .foregroundStyle(DKColor.hairline.opacity(0.45))
            }
            if kind.aggregation == .cumulative {
                ForEach(values) { value in
                    BarMark(xStart: .value("Beginn", value.start),
                            xEnd: .value("Ende", max(value.end, value.start.addingTimeInterval(window.duration / 400))),
                            y: .value(kind.title, kind.displayNumber(value.value)))
                        .foregroundStyle(landing.contains(value.id) ? DKColor.pulseCoral : tint)
                }
            } else {
                ForEach(values) { value in
                    if value.isAggregated {
                        // Range of the bucket (min–max) behind its mean: aggregation stays visible.
                        RectangleMark(xStart: .value("Beginn", value.start), xEnd: .value("Ende", value.end),
                                      yStart: .value("min", kind.displayNumber(value.low)),
                                      yEnd: .value("max", kind.displayNumber(max(value.high, value.low + 0.01))))
                            .foregroundStyle(tint.opacity(0.22))
                    }
                    LineMark(x: .value("Zeit", value.at), y: .value(kind.title, kind.displayNumber(value.value)),
                             series: .value("Abschnitt", "r\(value.run)"))
                        .foregroundStyle(tint)
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                        .interpolationMethod(.monotone)
                    if showsPoints || landing.contains(value.id) {
                        PointMark(x: .value("Zeit", value.at), y: .value(kind.title, kind.displayNumber(value.value)))
                            .symbolSize(landing.contains(value.id) ? 140 : 14)
                            .foregroundStyle(landing.contains(value.id) ? DKColor.pulseCoral : tint)
                    }
                }
            }
        }
        .chartXScale(domain: window.start...window.end, range: .plotDimension(padding: 0))
        .chartYScale(domain: yDomain, range: .plotDimension(padding: 0))
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .accessibilityHidden(true)   // the scrub surface and the read-out speak for the tracks
    }
}

/// Header line above a value track: name + symbol, unit, the drawn range and whether values are aggregated.
struct TrackHeader: View {
    let kind: SampleKind
    let values: [TrackValue]
    let resolution: TimelineResolution

    var body: some View {
        let style = MetricStyle.of(kind)
        HStack(alignment: .firstTextBaseline, spacing: DKSpace.s) {
            Label(style.name, systemImage: style.systemImage)
                .font(DKFont.label)
                .foregroundStyle(DKColor.textPrimary)
                .labelStyle(TintedIconLabel(tint: style.color))
            Spacer(minLength: DKSpace.xs)
            if let range = rangeText {
                Text(range)
                    .font(DKFont.caption)
                    .foregroundStyle(DKColor.textSecondary)
                    .monospacedDigit()
            }
        }
        .accessibilityElement(children: .combine)
        if let label = resolution.trackLabel(cumulative: kind.aggregation == .cumulative) {
            DKReference(text: label)
        }
    }

    private var rangeText: String? {
        let lows = values.map(\.low)
        let highs = values.map(\.high)
        guard let low = lows.min(), let high = highs.max() else { return nil }
        if kind.aggregation == .cumulative {
            return "bis \(kind.display(high)) \(kind.displayUnit)"
        }
        return "\(kind.display(low))–\(kind.display(high)) \(kind.displayUnit)"
    }
}

struct TintedIconLabel: LabelStyle {
    let tint: Color
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: DKSpace.xs) {
            configuration.icon.foregroundStyle(tint).accessibilityHidden(true)
            configuration.title
        }
    }
}

/// Hypnogram on the shared time axis: four phase rows plus a separate row for codes we cannot map.
/// Every interval keeps its real start and end; gaps stay empty. Each interval is its own VoiceOver element
/// (`hypnogram.segment.<n>`); a tap anywhere on the track picks the interval at that time.
struct HypnogramTrack: View {
    let segments: [SleepSegment]
    let window: DateInterval
    let selected: SleepSegment?
    let calendar: Calendar
    let onSelect: (SleepSegment) -> Void
    @ScaledMetric(relativeTo: .caption) private var rowHeight: CGFloat = 18

    private var lanes: [SleepPhase] {
        // The unknown row only appears when the night has such an interval.
        segments.contains { $0.phase == .unknown } ? Hypnogram.lanes : Hypnogram.lanes.filter { $0 != .unknown }
    }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .topLeading) {
                ForEach(Array(lanes.enumerated()), id: \.element) { row, _ in
                    Rectangle()
                        .fill(DKColor.hairline.opacity(0.35))
                        .frame(width: width, height: 1)
                        .offset(y: CGFloat(row) * rowHeight + rowHeight / 2)
                        .accessibilityHidden(true)
                }
                ForEach(Array(segments.enumerated()), id: \.element.id) { index, segment in
                    let frame = rect(for: segment, width: width)
                    // Not a button and no activate action (either makes it one for the audit): most intervals
                    // are a few points wide, below any usable hit area. The whole track takes the tap (by time,
                    // below); each interval stays its own VoiceOver element whose label already names phase,
                    // start, end and length.
                    SleepPhaseFill(phase: segment.phase, cornerRadius: 3)
                        .overlay {
                            if selected?.id == segment.id {
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .strokeBorder(DKColor.textPrimary, lineWidth: 2)
                            }
                        }
                        .frame(width: frame.width, height: frame.height)
                        .offset(x: frame.minX, y: frame.minY)
                        .accessibilityElement()
                        .accessibilityLabel(Hypnogram.describe(segment, calendar: calendar))
                        .accessibilityAddTraits(selected?.id == segment.id ? [.isStaticText, .isSelected] : .isStaticText)
                        .accessibilityIdentifier("hypnogram.segment.\(index)")
                }
            }
            .frame(width: width, height: proxy.size.height, alignment: .topLeading)
            .contentShape(Rectangle())
            .onTapGesture(coordinateSpace: .local) { location in
                let time = window.start.addingTimeInterval(Double(location.x / max(width, 1)) * window.duration)
                if let segment = Hypnogram.segment(at: time, in: segments) ?? nearest(to: time) { onSelect(segment) }
            }
        }
        .frame(height: rowHeight * CGFloat(lanes.count))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Schlafphasen")
        .accessibilityIdentifier("timeline.track.sleep")
    }

    /// A tap just beside a very short interval still picks it (within 10 minutes).
    private func nearest(to time: Date) -> SleepSegment? {
        guard let best = segments.min(by: { distance($0, time) < distance($1, time) }) else { return nil }
        return distance(best, time) <= 600 ? best : nil
    }

    private func distance(_ segment: SleepSegment, _ time: Date) -> TimeInterval {
        if time < segment.start { return segment.start.timeIntervalSince(time) }
        if time > segment.end { return time.timeIntervalSince(segment.end) }
        return 0
    }

    /// Segment rectangle, cut to the visible window, at least 2 pt wide so short intervals stay tappable.
    private func rect(for segment: SleepSegment, width: CGFloat) -> CGRect {
        let span = max(window.duration, 1)
        let start = max(segment.start, window.start)
        let end = min(segment.end, window.end)
        let x = CGFloat(start.timeIntervalSince(window.start) / span) * width
        let w = max(CGFloat(end.timeIntervalSince(start) / span) * width, 2)
        let row = lanes.firstIndex(of: segment.phase) ?? 0
        return CGRect(x: x, y: CGFloat(row) * rowHeight + 2, width: w, height: rowHeight - 4)
    }
}

/// Lane names next to the hypnogram, left aligned above the rows.
struct HypnogramLegendColumn: View {
    let hasUnknown: Bool
    var body: some View {
        SleepPhaseLegend(phases: hasUnknown ? Hypnogram.lanes : Hypnogram.lanes.filter { $0 != .unknown })
    }
}

/// Workouts and coach statements as marks on the time axis.
struct EventTrack: View {
    let events: [TimelineEvent]
    let window: DateInterval
    let calendar: Calendar
    let onSelect: (TimelineEvent) -> Void
    @ScaledMetric(relativeTo: .caption) private var height: CGFloat = 26

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .topLeading) {
                ForEach(events) { event in
                    let frame = rect(for: event, width: width)
                    Button { onSelect(event) } label: {
                        Group {
                            if event.kind == .workout {
                                Capsule().fill(MetricStyle.of(.trainingDuration).color)
                                    .overlay(alignment: .leading) {
                                        Image(systemName: "figure.run")
                                            .font(.caption2.weight(.bold))
                                            .foregroundStyle(DKColor.onAccent)
                                            .padding(.leading, 4)
                                            .opacity(frame.width > 18 ? 1 : 0)
                                    }
                            } else {
                                Image(systemName: "sparkle")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(DKColor.coach)
                            }
                        }
                        .frame(width: frame.width, height: frame.height)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .offset(x: frame.minX, y: frame.minY)
                    .accessibilityLabel(label(for: event))
                    .accessibilityIdentifier(event.kind == .workout ? "timeline.event.workout" : "timeline.event.coach")
                }
            }
        }
        .frame(height: height)
        .accessibilityElement(children: .contain)
    }

    private func label(for event: TimelineEvent) -> String {
        let clock = TimelineModel.clock(calendar)
        if event.kind == .workout {
            return "\(event.title), \(event.interval.start.formatted(clock)) bis \(event.interval.end.formatted(clock)), \(event.detail)"
        }
        return "ROOK um \(event.interval.start.formatted(clock)): \(event.detail)"
    }

    private func rect(for event: TimelineEvent, width: CGFloat) -> CGRect {
        let span = max(window.duration, 1)
        let start = max(event.interval.start, window.start)
        let end = min(event.interval.end, window.end)
        let x = CGFloat(start.timeIntervalSince(window.start) / span) * width
        let minimum: CGFloat = event.kind == .workout ? 10 : 18
        let w = max(CGFloat(end.timeIntervalSince(start) / span) * width, minimum)
        return CGRect(x: min(x, max(width - w, 0)), y: event.kind == .workout ? 4 : 2, width: w,
                      height: event.kind == .workout ? height - 8 : height - 4)
    }
}

/// Time labels under the tracks, on the same axis.
struct TimeRuler: View {
    let window: DateInterval
    let calendar: Calendar

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .topLeading) {
                ForEach(TimeTicks.ticks(for: window, calendar: calendar), id: \.date) { tick in
                    let x = CGFloat(tick.date.timeIntervalSince(window.start) / max(window.duration, 1)) * width
                    VStack(alignment: .leading, spacing: 2) {
                        Rectangle().fill(DKColor.lineStrong).frame(width: 1, height: 6)
                        Text(tick.label)
                            .font(DKFont.caption)
                            .foregroundStyle(DKColor.textSecondary)
                            .fixedSize()
                    }
                    .offset(x: min(x, max(width - 44, 0)))
                }
            }
        }
        .frame(height: 30)
        .accessibilityHidden(true)
    }
}

enum TimeTicks {
    struct Tick { let date: Date; let label: String }

    /// Four to six readable ticks for the window ("06:00", "Di 18.11.", "Nov").
    static func ticks(for window: DateInterval, calendar: Calendar) -> [Tick] {
        let span = window.duration
        let german = Locale(identifier: "de_DE")
        let (component, step, style): (Calendar.Component, Int, Date.FormatStyle) = {
            let base = Date.FormatStyle(locale: german, calendar: calendar, timeZone: calendar.timeZone)
            if span <= 3 * 3600 { return (.hour, 1, base.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)) }
            if span <= 14 * 3600 { return (.hour, 3, base.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)) }
            if span <= 36 * 3600 { return (.hour, 6, base.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)) }
            if span <= 10 * 86_400 { return (.day, span <= 4 * 86_400 ? 1 : 2, base.weekday(.abbreviated).day()) }
            if span <= 45 * 86_400 { return (.day, 7, base.day().month(.twoDigits)) }
            if span <= 120 * 86_400 { return (.month, 1, base.month(.abbreviated)) }
            return (.month, 2, base.month(.abbreviated))
        }()
        guard var cursor = calendar.dateInterval(of: component == .hour ? .day : component, for: window.start)?.start else { return [] }
        var ticks: [Tick] = []
        var guardCount = 0
        while cursor <= window.end, guardCount < 400 {
            guardCount += 1
            if cursor >= window.start {
                let aligned = component != .hour || calendar.component(.hour, from: cursor) % step == 0
                if aligned { ticks.append(Tick(date: cursor, label: cursor.formatted(style))) }
            }
            guard let next = calendar.date(byAdding: component, value: component == .hour ? 1 : step, to: cursor) else { break }
            cursor = next
        }
        return ticks
    }
}

/// Measuring points for the Verlauf (signposts in Instruments, subsystem de.sommerlabs.pulseone, category
/// Timeline). In test scenarios the counts also appear in the chart's accessibility value, so a UI test can
/// see whether a cursor step redraws the charts.
@MainActor
enum TimelineProbe {
    static let signposter = OSSignposter(subsystem: "de.sommerlabs.pulseone", category: "Timeline")
    private(set) static var chartBodies = 0
    private(set) static var marks = 0
    private(set) static var lastReloadMilliseconds = 0

    static func chartBody(kind: SampleKind, marks count: Int) {
        chartBodies += 1
        marks = count
        signposter.emitEvent("chartBody", "\(kind.rawValue, privacy: .public) \(count) marks")
    }

    static func reloaded(milliseconds: Int) { lastReloadMilliseconds = milliseconds }

    /// Body evaluations per view ("Verlauf", "Anzeige", "Fläche") and cursor steps, to see what a drag rebuilds.
    private(set) static var bodies: [String: Int] = [:]
    private(set) static var steps = 0
    private(set) static var stepMilliseconds = 0.0

    static func body(_ name: String) { bodies[name, default: 0] += 1 }

    static func step(milliseconds: Double) {
        steps += 1
        stepMilliseconds += milliseconds
    }

    static var summary: String {
        let views = bodies.keys.sorted().map { "\($0) \(bodies[$0] ?? 0)" }.joined(separator: ", ")
        return "Charts \(chartBodies)× (\(marks) Marks), \(views), Schritte \(steps) (\(Int(stepMilliseconds)) ms), Laden \(lastReloadMilliseconds) ms"
    }
}
