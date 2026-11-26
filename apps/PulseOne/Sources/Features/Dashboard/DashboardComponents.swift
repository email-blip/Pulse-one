import PulseCore
import SwiftUI


/// One cockpit tile with its controls while arranging. The tile itself is the button that opens the Verlauf
/// (`tile.<id>`); the arrows (`tile.<id>.moveUp/moveDown`) are the accessible alternative to dragging.
struct DashboardTileCell: View {
    let tile: DashboardTile
    let reading: TileReading?
    /// Sleep tile: last night's phases as a small hypnogram instead of a line.
    var night: SleepNight?
    /// Training tile: minutes per day of the last seven days.
    var week: TrainingWeek?
    var calendar: Calendar = .current
    let editing: Bool
    let isDropTarget: Bool
    let canMoveUp: Bool
    let canMoveDown: Bool
    let onOpen: () -> Void
    let onMove: (Int) -> Void
    let onResize: (DashboardTileSize) -> Void
    let onToggle: () -> Void

    var body: some View {
        VStack(spacing: DKSpace.s) {
            Button(action: onOpen) { tileView }
                .buttonStyle(.plain)
                .accessibilityHint(editing ? "Zum Verschieben gedrückt halten und ziehen" : "Öffnet den Verlauf")
                .accessibilityIdentifier("tile.\(tile.id)")
            if editing { controls }
        }
        .frame(maxWidth: .infinity)
        .opacity(tile.isVisible ? 1 : 0.5)
        .overlay(alignment: .leading) {
            if isDropTarget {
                // Visible insertion place: the dragged tile lands before this one.
                Capsule()
                    .fill(DKColor.accent)
                    .frame(width: 4)
                    .padding(.vertical, DKSpace.s)
                    .offset(x: -DKSpace.s)
                    .accessibilityHidden(true)
            }
        }
    }

    private var tileView: some View {
        let kind = tile.metricKind
        let style = kind.map(MetricStyle.of)
        let tint = style?.color ?? (tile.id == "sleep" ? MetricStyle.of(.sleepDuration).color : MetricStyle.of(.trainingDuration).color)
        return MetricTile(name: style?.name ?? tile.title, systemImage: style?.systemImage ?? tile.systemImage, tint: tint,
                          value: reading?.text, unit: reading?.unit ?? kind?.displayUnit ?? "",
                          reference: reading?.reference ?? (tile.id == "training" ? "Noch keine Einheit erfasst" : "noch kein Wert"),
                          size: tile.size) {
            if let night, let bed = night.inBed {
                TileHypnogram(segments: night.segments, window: bed, calendar: calendar)
            } else if let week {
                WeekBars(days: week.days, tint: tint)
            } else if let spark = reading?.spark, spark.count > 1 {
                Sparkline(values: Self.sparkValues(spark), tint: tint)
            }
        }
        .opacity(reading?.isOld == true ? 0.75 : 1)
    }

    /// Runs become one line each; a gap between runs stays a gap (nil).
    static func sparkValues(_ points: [SparkPoint]) -> [Double?] {
        var values: [Double?] = []
        for (index, point) in points.enumerated() {
            if index > 0, points[index - 1].run != point.run { values.append(nil) }
            values.append(point.value)
        }
        return values
    }

    private var controls: some View {
        FlowLayout(spacing: DKSpace.s) {
            Button { onMove(-1) } label: { Image(systemName: "arrow.up") }
                .buttonStyle(DKPillButtonStyle())
                .disabled(!canMoveUp || !tile.isVisible)
                .accessibilityLabel("\(tile.title) nach oben")
                .accessibilityIdentifier("tile.\(tile.id).moveUp")
            Button { onMove(1) } label: { Image(systemName: "arrow.down") }
                .buttonStyle(DKPillButtonStyle())
                .disabled(!canMoveDown || !tile.isVisible)
                .accessibilityLabel("\(tile.title) nach unten")
                .accessibilityIdentifier("tile.\(tile.id).moveDown")
            Menu {
                ForEach(DashboardTileSize.allCases, id: \.self) { size in
                    Button { onResize(size) } label: {
                        if size == tile.size { Label(Self.title(of: size), systemImage: "checkmark") } else { Text(Self.title(of: size)) }
                    }
                }
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(DKFont.label)
                    .foregroundStyle(DKColor.textPrimary)
                    .frame(minWidth: DKSize.minTouch, minHeight: DKSize.minTouch)
                    .background(Capsule().fill(DKColor.surfaceRaised))
            }
            .accessibilityLabel("Größe von \(tile.title): \(Self.title(of: tile.size))")
            .accessibilityIdentifier("tileSize.\(tile.id)")
            Button(action: onToggle) {
                Image(systemName: tile.isVisible ? "eye.slash" : "eye")
            }
            .buttonStyle(DKPillButtonStyle())
            .accessibilityLabel(tile.isVisible ? "\(tile.title) ausblenden" : "\(tile.title) einblenden")
            .accessibilityIdentifier("tileVisible.\(tile.id)")
        }
    }

    static func title(of size: DashboardTileSize) -> String {
        switch size {
        case .small: "Klein"
        case .wide: "Breit"
        case .large: "Groß"
        }
    }
}

/// Last night at a glance: asleep time, bed times and the phases as a small hypnogram. Opens the Verlauf.
struct SleepPreview: View {
    let night: SleepNight
    let calendar: Calendar
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            DKCard {
                HStack(alignment: .firstTextBaseline) {
                    Label("Letzte Nacht", systemImage: "moon.stars")
                        .font(DKFont.section)
                        .foregroundStyle(DKColor.textPrimary)
                        .labelStyle(TintedIconLabel(tint: MetricStyle.of(.sleepDuration).color))
                    Spacer(minLength: DKSpace.s)
                    Image(systemName: "chevron.right")
                        .foregroundStyle(DKColor.textTertiary)
                        .accessibilityHidden(true)
                }
                Text(summary)
                    .font(DKFont.body)
                    .foregroundStyle(DKColor.textSecondary)
                    .wraps()
                if let bed = night.inBed {
                    VStack(spacing: 2) {
                        MiniHypnogram(segments: night.segments, window: bed)
                            .frame(height: 56)
                        TimeRuler(window: bed, calendar: calendar)
                    }
                }
                SleepPhaseLegend(phases: phases)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Letzte Nacht")
        .accessibilityValue(summary)
        .accessibilityHint("Öffnet die Schlafphasen im Verlauf")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("dashboard.sleep")
    }

    private var phases: [SleepPhase] {
        night.segments.contains { $0.phase == .unknown } ? Hypnogram.lanes : Hypnogram.lanes.filter { $0 != .unknown }
    }

    private var summary: String {
        let clock = TimelineModel.clock(calendar)
        var parts = ["\(TileSummary.duration(night.asleep)) Schlaf"]
        if let bed = night.inBed { parts.append("\(bed.start.formatted(clock))–\(bed.end.formatted(clock))") }
        let deep = night.duration(of: .deep)
        if deep > 0 { parts.append("Tief \(TileSummary.duration(deep))") }
        let rem = night.duration(of: .rem)
        if rem > 0 { parts.append("REM \(TileSummary.duration(rem))") }
        return parts.joined(separator: " · ")
    }
}

/// The sleep tile's trend: the night's phases with bedtime and wake time under them.
struct TileHypnogram: View {
    let segments: [SleepSegment]
    let window: DateInterval
    let calendar: Calendar

    var body: some View {
        let clock = TimelineModel.clock(calendar)
        VStack(spacing: 2) {
            MiniHypnogram(segments: segments, window: window)
            HStack {
                Text(window.start.formatted(clock))
                Spacer(minLength: DKSpace.xs)
                Text(window.end.formatted(clock))
            }
            .font(.caption2)
            .foregroundStyle(DKColor.textSecondary)
            .monospacedDigit()
            .lineLimit(1)
            .accessibilityHidden(true)
        }
    }
}

/// The training tile's trend: minutes per day of the last seven days, today last and full colour.
struct WeekBars: View {
    let days: [Double]
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            let high = max(days.max() ?? 0, 1)
            let gap: CGFloat = 4
            let width = max((proxy.size.width - gap * CGFloat(max(days.count - 1, 0))) / CGFloat(max(days.count, 1)), 1)
            HStack(alignment: .bottom, spacing: gap) {
                ForEach(Array(days.enumerated()), id: \.offset) { index, minutes in
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(index == days.count - 1 ? tint : tint.opacity(0.55))
                        .frame(width: width, height: minutes > 0 ? max(CGFloat(minutes / high) * proxy.size.height, 3) : 2)
                        .opacity(minutes > 0 ? 1 : 0.35)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .bottomLeading)
        }
        .accessibilityHidden(true)
    }
}

/// Non-interactive hypnogram for the preview (the interactive one lives in the Verlauf).
struct MiniHypnogram: View {
    let segments: [SleepSegment]
    let window: DateInterval

    var body: some View {
        GeometryReader { proxy in
            let lanes = segments.contains { $0.phase == .unknown } ? Hypnogram.lanes : Hypnogram.lanes.filter { $0 != .unknown }
            let row = proxy.size.height / CGFloat(max(lanes.count, 1))
            ZStack(alignment: .topLeading) {
                ForEach(segments) { segment in
                    let x = CGFloat(segment.start.timeIntervalSince(window.start) / max(window.duration, 1)) * proxy.size.width
                    let width = max(CGFloat(segment.duration / max(window.duration, 1)) * proxy.size.width, 1.5)
                    let lane = CGFloat(lanes.firstIndex(of: segment.phase) ?? 0)
                    SleepPhaseFill(phase: segment.phase, cornerRadius: 2)
                        .frame(width: width, height: max(row - 3, 2))
                        .offset(x: x, y: lane * row + 1.5)
                }
            }
        }
        .accessibilityHidden(true)
    }
}
