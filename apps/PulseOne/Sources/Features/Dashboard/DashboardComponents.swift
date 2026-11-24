import PulseCore
import SwiftUI


/// One cockpit tile with its controls while arranging. The tile itself is the button that opens the Verlauf
/// (`tile.<id>`); the arrows (`tile.<id>.moveUp/moveDown`) are the accessible alternative to dragging.
struct DashboardTileCell: View {
    let tile: DashboardTile
    let reading: TileReading?
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
                          reference: reading?.reference ?? (tile.id == "training" ? "Heute noch keine Einheit" : "noch kein Wert"),
                          size: tile.size) {
            if let spark = reading?.spark, spark.count > 1 {
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
                    MiniHypnogram(segments: night.segments, window: bed)
                        .frame(height: 56)
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

/// iOS 26: the tab bar floats as glass over the content, and a scroll view that touches the bottom safe-area
/// edge keeps drawing its content beneath it. Text resting there at the bottom of the dashboard (Ruhepuls, HRV,
/// sleep at y ≥ 808 on a 17 Pro) was on screen for the accessibility audit but hidden behind the bar: first
/// bent by the glass, then covered by an opaque strip; either way the contrast audit sometimes reported it as
/// text without an element (runs 204, 213). Ending the scroll view one point above the safe-area edge stops it
/// from extending under the bar, so content there is simply scrolled out of view, as with an opaque bar.
/// The page background still fills the whole screen behind the glass.
/// Screens that draw their own full-screen background behind the scroll view (Coach, Profil) pass
/// `pageBackground: false`.
struct EndsAboveTabBar: ViewModifier {
    var pageBackground = true

    func body(content: Content) -> some View {
        let wrapped = VStack(spacing: 0) {
            content
            Color.clear
                .frame(height: 1)
                .accessibilityHidden(true)
        }
        // The wrapper still touches every edge, so the page background fills the screen behind the bars.
        if pageBackground {
            wrapped.dkPageBackground()
        } else {
            wrapped
        }
    }
}
