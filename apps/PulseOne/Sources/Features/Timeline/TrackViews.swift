import Charts
import os
import PulseCore
import SwiftUI

// Track views of the Verlauf. All of them map time to x the same way (window start = 0, end = width,
// no inner padding), so the hypnogram, the value tracks, the events and the shared cursor line up.

/// One value track (pulse, HRV, SpO₂, stress, movement) drawn with Swift Charts. Equatable, so moving the
/// cursor does not redraw the marks. Faint grid lines at the y-axis values and the time ticks; the labels
/// sit outside the plot (`YAxisLabels`, `TimeRuler`), so every track keeps the same time-to-x mapping.
struct ValueTrackChart: View, Equatable {
    let kind: SampleKind
    let values: [TrackValue]
    let gaps: [DateInterval]
    let window: DateInterval
    let yDomain: ClosedRange<Double>
    let landing: Set<String>
    let showsPoints: Bool
    var comparison: [TrackValue] = []
    var yTicks: [Double] = []
    var timeTicks: [Date] = []
    var calendar: Calendar = .current

    /// Up to this many original values each get a clear point with value and time.
    static let labelledLimit = 8

    nonisolated static func == (lhs: ValueTrackChart, rhs: ValueTrackChart) -> Bool {
        lhs.kind == rhs.kind && lhs.window == rhs.window && lhs.yDomain == rhs.yDomain && lhs.showsPoints == rhs.showsPoints
            && lhs.landing == rhs.landing && lhs.gaps == rhs.gaps && lhs.values == rhs.values
            && lhs.comparison == rhs.comparison && lhs.yTicks == rhs.yTicks && lhs.timeTicks == rhs.timeTicks
    }

    var body: some View {
        let tint = MetricStyle.of(kind).color
        let _ = TimelineProbe.chartBody(kind: kind, marks: values.count)
        let cumulative = kind.aggregation == .cumulative
        let labelled = showsPoints && !cumulative && values.count <= Self.labelledLimit
        let lonely = Self.lonelyIDs(values)
        let named = labelled ? Self.namedIDs(values, window: window) : []
        Chart {
            grid
            comparisonMarks(cumulative: cumulative)
            if cumulative {
                bars(tint: tint)
            } else {
                lines(tint: tint, labelled: labelled, named: named, lonely: lonely)
            }
        }
        .chartXScale(domain: window.start...window.end, range: .plotDimension(padding: 0))
        .chartYScale(domain: yDomain, range: .plotDimension(padding: 0))
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .accessibilityHidden(true)   // the scrub surface and the read-out speak for the tracks
    }

    /// Faint grid at the y-axis values and the time ticks. Gaps of point values: a faint band, never a line to
    /// zero and never a bridged line. Movement shows no band: a stretch without steps simply has no bar (the
    /// grey blocks read as data).
    @ChartContentBuilder
    private var grid: some ChartContent {
        ForEach(yTicks, id: \.self) { tick in
            RuleMark(y: .value("Raster", tick))
                .foregroundStyle(DKColor.gridLine.opacity(0.8))
                .lineStyle(StrokeStyle(lineWidth: 0.5))
        }
        ForEach(timeTicks, id: \.self) { tick in
            RuleMark(x: .value("Uhrzeit", tick))
                .foregroundStyle(DKColor.gridLine.opacity(0.8))
                .lineStyle(StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
        }
        if kind.aggregation != .cumulative {
            ForEach(gaps, id: \.start) { gap in
                RectangleMark(xStart: .value("Beginn", gap.start), xEnd: .value("Ende", gap.end),
                              yStart: .value("unten", yDomain.lowerBound), yEnd: .value("oben", yDomain.upperBound))
                    .foregroundStyle(DKColor.hairline.opacity(0.25))
            }
        }
    }

    /// Comparison (yesterday / mean of seven days): thin dashed line behind today's values.
    @ChartContentBuilder
    private func comparisonMarks(cumulative: Bool) -> some ChartContent {
        ForEach(comparison) { value in
            LineMark(x: .value("Zeit", value.at), y: .value("Vergleich", kind.displayNumber(value.value)),
                     series: .value("Abschnitt", "c\(value.run)"))
                .foregroundStyle(DKColor.textSecondary.opacity(0.9))
                .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [4, 3]))
                .interpolationMethod(cumulative ? InterpolationMethod.stepCenter : InterpolationMethod.monotone)
        }
    }

    @ChartContentBuilder
    private func bars(tint: Color) -> some ChartContent {
        ForEach(values) { value in
            BarMark(xStart: .value("Beginn", value.start),
                    xEnd: .value("Ende", max(value.end, value.start.addingTimeInterval(window.duration / 400))),
                    y: .value(kind.title, kind.displayNumber(value.value)))
                .foregroundStyle(landing.contains(value.id) ? DKColor.pulseCoral : tint)
        }
    }

    @ChartContentBuilder
    private func lines(tint: Color, labelled: Bool, named: Set<String>, lonely: Set<String>) -> some ChartContent {
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
            if labelled, named.contains(value.id) {
                // Few values (SpO₂, stress): clear points with value and time instead of a lost dot. The label
                // stays inside the plot, so it never runs into the track title above.
                PointMark(x: .value("Zeit", value.at), y: .value(kind.title, kind.displayNumber(value.value)))
                    .symbolSize(landing.contains(value.id) ? 140 : 70)
                    .foregroundStyle(landing.contains(value.id) ? DKColor.pulseCoral : tint)
                    .annotation(position: isHigh(value) ? .bottom : .top, spacing: 3,
                                overflowResolution: .init(x: .fit(to: .plot), y: .fit(to: .plot))) {
                        pointLabel(value)
                    }
            } else if labelled {
                // Too close to a labelled neighbour: the point without text (the cursor reads it out).
                PointMark(x: .value("Zeit", value.at), y: .value(kind.title, kind.displayNumber(value.value)))
                    .symbolSize(landing.contains(value.id) ? 140 : 70)
                    .foregroundStyle(landing.contains(value.id) ? DKColor.pulseCoral : tint)
            } else if showsPoints || landing.contains(value.id) || lonely.contains(value.id) {
                PointMark(x: .value("Zeit", value.at), y: .value(kind.title, kind.displayNumber(value.value)))
                    .symbolSize(landing.contains(value.id) ? 140 : (lonely.contains(value.id) ? 40 : 14))
                    .foregroundStyle(landing.contains(value.id) ? DKColor.pulseCoral : tint)
            }
        }
    }

    /// Points that get a value label: from the newest backwards, each at least a sixth of the window away from
    /// the last labelled one, so labels never stack on top of each other ("9898 %" in Build 19 screenshots).
    static func namedIDs(_ values: [TrackValue], window: DateInterval) -> Set<String> {
        let gap = window.duration / 6
        var result: Set<String> = []
        var last: Date?
        for value in values.sorted(by: { $0.at > $1.at }) {
            if let last, last.timeIntervalSince(value.at) < gap { continue }
            result.insert(value.id)
            last = value.at
        }
        return result
    }

    /// Values that stand alone in their run (a single measurement between gaps) get a visible point.
    static func lonelyIDs(_ values: [TrackValue]) -> Set<String> {
        var counts: [Int: Int] = [:]
        for value in values { counts[value.run, default: 0] += 1 }
        return Set(values.filter { counts[$0.run] == 1 }.map(\.id))
    }

    private func isHigh(_ value: TrackValue) -> Bool {
        let span = max(yDomain.upperBound - yDomain.lowerBound, 0.0001)
        return (kind.displayNumber(value.value) - yDomain.lowerBound) / span > 0.6
    }

    private func pointLabel(_ value: TrackValue) -> some View {
        VStack(spacing: 0) {
            Text("\(kind.display(value.value)) \(kind.displayUnit)")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(DKColor.textPrimary)
            Text(value.start.formatted(TimelineModel.clock(calendar)))
                .font(.caption2)
                .foregroundStyle(DKColor.textSecondary)
        }
        .monospacedDigit()
        .padding(.horizontal, 3)
        // On its own opaque plate: the label never sits on the line or a point with too little contrast.
        .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(DKColor.surface))
        .fixedSize()
    }
}

/// The y-axis values left of a value track, in the same gutter for every row.
struct YAxisLabels: View {
    let ticks: [Double]
    let domain: ClosedRange<Double>
    /// UI tests (team 06) read the drawn values under this id; no-op outside `-qaProbe YES`.
    var probeID: String?

    var body: some View {
        GeometryReader { proxy in
            let height = proxy.size.height
            let span = max(domain.upperBound - domain.lowerBound, 0.0001)
            ForEach(ticks, id: \.self) { tick in
                let y = (1 - (tick - domain.lowerBound) / span) * height
                Text(Self.text(tick))
                    .font(DKFont.axis)
                    .foregroundStyle(DKColor.axisLabel)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(width: max(proxy.size.width - 4, 1), alignment: .trailing)
                    .position(x: (proxy.size.width - 4) / 2, y: min(max(y, 6), max(height - 6, 6)))
            }
        }
        .accessibilityHidden(true)
        .task(id: ticks) {
            if let probeID { QAProbe.note(probeID, ticks.map(Self.text).joined(separator: "|")) }
        }
    }

    static func text(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)).locale(Locale(identifier: "de_DE")))
    }
}

/// The value at the shared cursor, written beside the cursor line of one track ("64 bpm · 14:05").
/// VoiceOver hears the same in the read-out, so this label is hidden from it.
struct CursorBadge: View {
    let model: TimelineModel
    let track: TimelineTrack

    var body: some View {
        GeometryReader { proxy in
            if let cursor = model.cursor, let row = model.cursorRow(for: track) {
                let width = proxy.size.width
                let x = CGFloat(model.fraction(of: cursor)) * width
                let leftSide = x > width * 0.6
                badge(row, compare: model.comparisonText(for: track))
                    .frame(width: max(leftSide ? x - 6 : width - x - 6, 1), alignment: leftSide ? .trailing : .leading)
                    .offset(x: leftSide ? 0 : x + 6, y: 2)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func badge(_ row: CursorRow, compare: String?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(row.note == nil ? "\(row.value) · \(row.time)" : "keine Messung")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(DKColor.textPrimary)
            if let compare {
                Text(compare)
                    .font(.caption2)
                    .foregroundStyle(DKColor.textSecondary)
            }
        }
        .monospacedDigit()
        .lineLimit(1)
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        // Fully opaque: a value label under it showed through as ghost text ("96 %" behind "keine Messung"),
        // which the contrast audit reports on the track title above.
        .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(DKColor.surfaceRaised))
        .fixedSize()
    }
}

/// Header line above a value track: name + symbol, unit, the drawn range and whether values are aggregated.
/// The name is never hyphenated ("Anspan-nung"): one line, slightly smaller if needed; at large text sizes
/// the range moves under the name.
struct TrackHeader: View {
    let kind: SampleKind
    let values: [TrackValue]
    let resolution: TimelineResolution
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let style = MetricStyle.of(kind)
        let layout = DKLayout.stacksHeader(typeSize)
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: DKSpace.s))
        layout {
            Label(style.name, systemImage: style.systemImage)
                .font(DKFont.label)
                .foregroundStyle(DKColor.textPrimary)
                .labelStyle(TintedIconLabel(tint: style.color))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .layoutPriority(1)
            if !DKLayout.stacksHeader(typeSize) { Spacer(minLength: DKSpace.xs) }
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

    /// "52–118 bpm"; one value without a span when min = max ("99 %"); few values say how many.
    private var rangeText: String? {
        let lows = values.map(\.low)
        let highs = values.map(\.high)
        guard let low = lows.min(), let high = highs.max() else { return nil }
        if kind.aggregation == .cumulative {
            return "bis \(kind.display(high)) \(kind.displayUnit)"
        }
        let lowText = kind.display(low)
        let highText = kind.display(high)
        let span = lowText == highText ? "\(lowText) \(kind.displayUnit)" : "\(lowText)–\(highText) \(kind.displayUnit)"
        guard resolution == .original, values.count <= ValueTrackChart.labelledLimit else { return span }
        return values.count == 1 ? "\(span) · 1 Messung" : "\(span) · \(values.count) Messungen"
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

/// Time labels under a track, on the same axis: centred on their tick, kept inside the width, every second
/// one left out when large text would make them collide.
struct TimeRuler: View {
    let window: DateInterval
    let calendar: Calendar
    /// UI tests (team 06) read the drawn labels under this id; no-op outside `-qaProbe YES`.
    var probeID: String?
    @ScaledMetric(relativeTo: .caption) private var height: CGFloat = 18
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let ticks = shownTicks
        GeometryReader { proxy in
            let width = proxy.size.width
            let slot: CGFloat = typeSize >= .xxLarge ? 96 : 64
            ZStack(alignment: .topLeading) {
                ForEach(ticks, id: \.date) { tick in
                    let x = CGFloat(tick.date.timeIntervalSince(window.start) / max(window.duration, 1)) * width
                    Text(tick.label)
                        .font(DKFont.axis)
                        .foregroundStyle(DKColor.axisLabel)
                        .lineLimit(1)
                        .fixedSize()
                        .frame(width: slot)
                        .position(x: min(max(x, slot / 2), max(width - slot / 2, slot / 2)), y: height / 2)
                }
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
        .task(id: ticks.map(\.label)) {
            if let probeID { QAProbe.note(probeID, ticks.map(\.label).joined(separator: "|")) }
        }
    }

    /// Every tick, or every second one at large text sizes (labels must not collide).
    private var shownTicks: [TimeTicks.Tick] {
        let all = TimeTicks.ticks(for: window, calendar: calendar)
        guard typeSize >= .xxLarge, all.count > 3 else { return all }
        return all.enumerated().filter { $0.offset % 2 == 0 }.map(\.element)
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
