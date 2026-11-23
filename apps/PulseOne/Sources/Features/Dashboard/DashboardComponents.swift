import PulseCore
import SwiftUI

/// What the ROOK block shows: a headline, one or two sentences, one action, and whether "Warum?" exists.
struct RookContent: Equatable {
    let headline: String
    let body: String
    let action: CoachAction?
    var actionID = "rook.action"
    var hasWhy: Bool
    var presence: RookPresence = .idle

    init(headline: String, body: String, action: CoachAction?, actionID: String = "rook.action", hasWhy: Bool) {
        self.headline = headline
        self.body = body
        self.action = action
        self.actionID = actionID
        self.hasWhy = hasWhy
    }

    /// The first sentence of the interpretation becomes the headline, the rest the body (contract: ≤3 sentences).
    init(insight: CoachInsight) {
        let text = insight.interpretation.trimmingCharacters(in: .whitespacesAndNewlines)
        if let end = text.firstIndex(where: { ".!?".contains($0) }), text.index(after: end) < text.endIndex {
            headline = String(text[...end])
            body = text[text.index(after: end)...].trimmingCharacters(in: .whitespaces)
        } else {
            headline = text
            body = ""
        }
        action = insight.action
        hasWhy = !insight.evidence.isEmpty || !insight.observation.isEmpty
        presence = insight.direction == .urgent || insight.direction == .clarify ? .alerting : .idle
    }
}

/// ROOK at the top of the dashboard: orb + name, "Vorlesen", headline with the interpretation, the primary
/// action and "Warum?". Headline and interpretation are one accessibility element (`rook.insight`).
struct RookPanel: View {
    let content: RookContent
    let isSpeaking: Bool
    let onSpeak: () -> Void
    let onAction: (CoachAction) -> Void
    let onWhy: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DKSpace.l) {
            HStack(spacing: DKSpace.m) {
                RookHeader(presence: isSpeaking ? .speaking : content.presence)
                Spacer(minLength: DKSpace.s)
                Button(action: onSpeak) {
                    Label(isSpeaking ? "Stopp" : "Vorlesen", systemImage: isSpeaking ? "stop.fill" : "speaker.wave.2")
                }
                .buttonStyle(DKPillButtonStyle())
                .accessibilityIdentifier("rook.speak")
            }
            VStack(alignment: .leading, spacing: DKSpace.m) {
                Text(content.headline)
                    .font(DKFont.headline)
                    .foregroundStyle(DKColor.textPrimary)
                    .wraps()
                if !content.body.isEmpty {
                    Text(content.body)
                        .font(DKFont.body)
                        .foregroundStyle(DKColor.textSecondary)
                        .lineSpacing(3)
                        .wraps()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier("rook.insight")
            FlowLayout(spacing: DKSpace.m) {
                if let action = content.action {
                    Button { onAction(action) } label: {
                        Label(action.title, systemImage: action.kind == .startWorkout ? "arrow.up.right" : "arrow.right")
                            .labelStyle(TrailingIconLabel())
                    }
                    .buttonStyle(DKPrimaryButtonStyle())
                    .accessibilityIdentifier(content.actionID)
                }
                if content.hasWhy {
                    Button("Warum?", action: onWhy)
                        .buttonStyle(DKSecondaryButtonStyle())
                        .accessibilityIdentifier("rook.why")
                }
            }
        }
    }
}

/// "Meine Einheit starten ↗": title first, icon after it.
struct TrailingIconLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: DKSpace.s) {
            configuration.title
            configuration.icon.accessibilityHidden(true)
        }
    }
}

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

/// "Warum?" until team 04's evidence view lands: observation, each piece of evidence (opens the Verlauf
/// at its window), and when ROOK looks again.
struct RookWhySheet: View {
    let insight: CoachInsight
    let onOpen: (EvidenceRef) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DKSpace.l) {
                    // In the content, not the toolbar: a toolbar button shows up twice in the UI test tree
                    // (bar item and its glass copy), so `why.close` would not be unique.
                    HStack {
                        Spacer()
                        Button("Fertig") { dismiss() }
                            .buttonStyle(DKTextButtonStyle())
                            .frame(minHeight: DKSize.minTouch)
                            .accessibilityIdentifier("why.close")
                    }
                    Text(insight.observation)
                        .font(DKFont.body)
                        .foregroundStyle(DKColor.textPrimary)
                        .wraps()
                    ForEach(Array(insight.evidence.enumerated()), id: \.offset) { index, evidence in
                        Button { onOpen(evidence) } label: {
                            DKCard {
                                Text(evidence.label)
                                    .font(DKFont.label)
                                    .foregroundStyle(DKColor.textPrimary)
                                    .wraps()
                                if let value = evidence.shownValue {
                                    Text(value).font(DKFont.bodyEmphasis).foregroundStyle(DKColor.textPrimary)
                                }
                                if let comparison = evidence.comparison {
                                    Text(comparison).font(DKFont.caption).foregroundStyle(DKColor.textSecondary).wraps()
                                }
                                DKReference(text: windowText(evidence.window))
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityElement(children: .combine)
                        .accessibilityHint("Öffnet diesen Zeitraum im Verlauf")
                        .accessibilityIdentifier("why.evidence.\(index)")
                    }
                    if let recheck = insight.recheckAt {
                        Text("Ich schaue \(recheck.formatted(.relative(presentation: .named).locale(Locale(identifier: "de_DE")))) wieder drauf.")
                            .font(DKFont.caption)
                            .foregroundStyle(DKColor.textSecondary)
                            .wraps()
                    }
                }
                .padding(DKSpace.page)
            }
            .dkPageBackground()
            .navigationTitle("Warum?")
            .navigationBarTitleDisplayMode(.inline)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.why")
    }

    private func windowText(_ window: DateInterval) -> String {
        let style = TimelineModel.dayClock(.current)
        return "\(window.start.formatted(style)) – \(window.end.formatted(style))"
    }
}
