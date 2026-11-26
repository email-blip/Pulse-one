import PulseCore
import SwiftData
import SwiftUI

/// VERLAUF: all tracks on one time axis. Day, week, month, three months, year; pinch to zoom, drag
/// sideways to move, tap or hold-and-drag to move the shared cursor. The cursor picks the nearest original
/// measurement with its own time; in a gap it picks nothing. Above two days values are aggregated (marked).
struct TimelineScreen: View {
    var focus: TimelineFocus?
    /// Coach statements to mark on the axis (team 04 delivers them; the test view brings one).
    var coachInsights: [CoachInsight] = []

    @Environment(\.modelContext) private var modelContext
    @Environment(SourcesStore.self) private var sources
    @Environment(RingStore.self) private var ring
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.reduceMotionEffective) private var reduceMotion
    @Environment(\.freezeAnimations) private var frozen
    @State private var model = TimelineModel()
    @State private var opened = false
    @State private var showsSource = false
    /// Gutter for the y-axis values; every row (hypnogram, events, rulers) keeps it, so the time axis lines up.
    @ScaledMetric(relativeTo: .caption) private var scaledAxisWidth: CGFloat = 32
    /// Capped so the tracks keep most of the width at the largest text sizes (labels shrink a little).
    private var axisWidth: CGFloat { min(scaledAxisWidth, 56) }
    /// Saved sessions (team 05); a newly saved one reloads the window.
    @Query(sort: \WorkoutRecord.endedAt) private var savedWorkouts: [WorkoutRecord]

    var body: some View {
        let _ = TimelineProbe.body("Verlauf")
        ScrollView {
            VStack(alignment: .leading, spacing: DKSpace.l) {
                if showsOwnBanner { TestBanner() }
                rangePicker
                windowBar
                // Above the tracks, so it is on screen when the cursor moves (opened from a tile the cursor is
                // already set). Without a cursor only the step buttons: no empty box.
                CursorReadout(model: model, showsSource: $showsSource)
                tracks
                if model.comparisonAvailable { comparisonPicker }
            }
            .padding(.horizontal, DKSpace.page)
            .padding(.bottom, DKSpace.xxl)
        }
        .dkPageBackground()
        .dkOpaqueBars()
        .navigationTitle("Verlauf")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: refreshToken) { load() }
        .onChange(of: model.needsReload) { _, needs in if needs { load() } }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.timeline")
    }

    /// The rebuild walkthrough shows its banner once at the root; other test views show it here.
    private var showsOwnBanner: Bool {
        let options = LaunchOptions.current
        return options.usesTestScenario && !TimelineDemo.liveClockScenarios.contains(options.scenario ?? "")
    }

    /// New ring values, finished syncs and a return to the foreground reload the window.
    private var refreshToken: String {
        "\(ring.snapshot.lastHeartRate?.timestamp.timeIntervalSince1970 ?? 0)|\(ring.lastHistorySync?.timeIntervalSince1970 ?? 0)|\(sources.syncing.count)|\(scenePhase == .active)|\(savedWorkouts.count)|\(savedWorkouts.last?.endedAt.timeIntervalSince1970 ?? 0)"
    }

    private func load() {
        if !opened {
            model.open(focus)
            opened = true
        } else if !TimelineDemo.isActive {
            model.followLive()
        }
        let insights = TimelineDemo.isActive ? [TimelineDemo.insight(now: model.now)] : coachInsights
        withAnimation(MotionEvent.measurementLands.resolvedAnimation(reduceMotion: reduceMotion, frozen: frozen)) {
            model.reload(context: modelContext, profileID: sources.ownerProfileID, coachInsights: insights,
                         trainings: { WorkoutLog(context: modelContext, calendar: model.calendar).entries(in: $0) })
        }
        guard !model.landing.isEmpty else { return }
        Task {
            try? await Task.sleep(for: .seconds(1.4))
            withAnimation(MotionEvent.measurementLands.resolvedAnimation(reduceMotion: reduceMotion, frozen: frozen)) {
                model.clearLanding()
            }
        }
    }

    // MARK: Controls

    private var rangePicker: some View {
        // Wraps instead of scrolling sideways: every range stays fully on screen (a half-visible chip failed
        // the contrast audit) and nothing hides at large text sizes.
        HStack(alignment: .top, spacing: DKSpace.s) {
            ranges
            Spacer(minLength: 0)
            DKInfoButton(title: "Verlauf", text: infoText, identifier: "timeline.info")
        }
    }

    /// What the Verlauf shows, behind the ⓘ (no hint texts on the screen).
    private var infoText: String {
        model.resolution == .original
            ? "Tippe auf die Spuren oder halte und ziehe: Die Linie zeigt in jeder Spur Wert und Uhrzeit. Mit zwei Fingern zoomen, mit einem wischen. Jeder Punkt ist eine echte Messung mit ihrer Uhrzeit, Lücken bleiben leer."
            : "Über zwei Tage zeigt der Verlauf Mittel- oder Summenwerte je Abschnitt; die Fläche zeigt die Spanne. Zum Einzelwert hineinzoomen."
    }

    /// Thin overlay of yesterday or the mean of the last seven days (day scale only).
    private var comparisonPicker: some View {
        FlowLayout(spacing: DKSpace.s) {
            Text("Vergleich")
                .font(DKFont.label)
                .foregroundStyle(DKColor.textSecondary)
                .frame(minHeight: DKSize.minTouch)
            ForEach(TrackComparisonMode.allCases, id: \.self) { mode in
                DKChip(title: Self.title(of: mode), isSelected: model.comparison == mode) {
                    model.setComparison(mode)
                }
                .accessibilityIdentifier("timeline.compare.\(mode.rawValue)")
            }
        }
        .sensoryFeedback(.selection, trigger: model.comparison)
    }

    static func title(of mode: TrackComparisonMode) -> String {
        switch mode {
        case .off: "Aus"
        case .yesterday: "Gestern"
        case .week: "7-Tage-Mittel"
        }
    }

    private var ranges: some View {
        FlowLayout(spacing: DKSpace.s) {
            ForEach(TimelineRange.allCases, id: \.self) { range in
                DKChip(title: Self.title(of: range), isSelected: model.range == range) {
                    withAnimation(MotionEvent.rangeChange.resolvedAnimation(reduceMotion: reduceMotion, frozen: frozen)) {
                        model.setRange(range)
                    }
                }
                .accessibilityIdentifier("timeline.range.\(range.rawValue)")
            }
        }
        .sensoryFeedback(.selection, trigger: model.range)
    }

    private var windowBar: some View {
        HStack(spacing: DKSpace.s) {
            Button { model.page(forward: false) } label: {
                Image(systemName: "chevron.left").frame(minWidth: DKSize.minTouch, minHeight: DKSize.minTouch)
            }
            .accessibilityLabel("Früher")
            .accessibilityIdentifier("timeline.earlier")
            Text(windowTitle)
                .font(DKFont.label)
                .foregroundStyle(DKColor.textPrimary)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
                .wraps()
                .accessibilityIdentifier("timeline.window")
            Button { model.page(forward: true) } label: {
                Image(systemName: "chevron.right").frame(minWidth: DKSize.minTouch, minHeight: DKSize.minTouch)
            }
            .accessibilityLabel("Später")
            .accessibilityIdentifier("timeline.later")
            Button { model.zoom(from: model.visible, factor: 0.5, anchor: 0.5) } label: {
                Image(systemName: "minus.magnifyingglass").frame(minWidth: DKSize.minTouch, minHeight: DKSize.minTouch)
            }
            .accessibilityLabel("Herauszoomen")
            Button { model.zoom(from: model.visible, factor: 2, anchor: 0.5) } label: {
                Image(systemName: "plus.magnifyingglass").frame(minWidth: DKSize.minTouch, minHeight: DKSize.minTouch)
            }
            .accessibilityLabel("Hineinzoomen")
        }
        .foregroundStyle(DKColor.accent)
        .font(DKFont.label)
    }

    private var windowTitle: String {
        let calendar = model.calendar
        let style = model.visible.duration <= 2 * 86_400 ? TimelineModel.dayClock(calendar) : TimelineModel.dayOnly(calendar)
        return "\(model.visible.start.formatted(style)) – \(model.visible.end.formatted(style))"
    }

    // MARK: Tracks

    @ViewBuilder
    private var tracks: some View {
        let window = model.visible
        let resolution = model.resolution
        // Opened for sleep (sleep tile, "Letzte Nacht"): phases first. Otherwise the value tracks come first,
        // so the scrub area starts high on the screen and a tap in its middle never lands under the tab bar.
        let options = LaunchOptions.current
        let sleepFirst = focus?.track == .sleepPhases || (options.usesTestScenario && options.scenario == "timelineHypnogram")
        VStack(alignment: .leading, spacing: DKSpace.m) {
            if sleepFirst, !model.visibleSegments.isEmpty {
                SleepSection(model: model, window: window, axisWidth: axisWidth)
            }
            valueTracks(window: window, resolution: resolution)
            if !sleepFirst, !model.visibleSegments.isEmpty {
                SleepSection(model: model, window: window, axisWidth: axisWidth)
            }
            if !model.visibleEvents.isEmpty {
                VStack(alignment: .leading, spacing: DKSpace.xs) {
                    Label("Training und ROOK", systemImage: "figure.run")
                        .font(DKFont.label)
                        .foregroundStyle(DKColor.textPrimary)
                        .labelStyle(TintedIconLabel(tint: MetricStyle.of(.trainingDuration).color))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    axisRow {
                        EventTrack(events: model.visibleEvents, window: window, calendar: model.calendar) { event in
                            model.setCursor(event.interval.start.addingTimeInterval(event.interval.duration / 2))
                        }
                        .overlay { CursorLine(model: model) }
                    }
                    axisRow { TimeRuler(window: window, calendar: model.calendar) }
                }
            }
            if model.hasLoaded, model.tracks.isEmpty {
                DKCard {
                    Text("Noch keine Werte vom Ring oder aus Apple Health.")
                        .font(DKFont.body)
                        .foregroundStyle(DKColor.textSecondary)
                        .wraps()
                }
            }
        }
        .dkMotion(.rangeChange, value: model.range)
    }

    /// A row on the shared time axis: the y-axis gutter first, then the content.
    private func axisRow<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: axisWidth).accessibilityHidden(true)
            content()
        }
    }

    /// Pulse, HRV, SpO₂, stress and movement under one scrub surface (`timeline.chart`).
    private func valueTracks(window: DateInterval, resolution: TimelineResolution) -> some View {
        let timeTicks = TimeTicks.ticks(for: window, calendar: model.calendar).map(\.date)
        return VStack(alignment: .leading, spacing: DKSpace.m) {
            ForEach(TimelineModel.valueTracks, id: \.self) { track in
                if let drawn = model.drawn(track) {
                    let kind = drawn.kind
                    let yTicks = AxisTicks.values(in: drawn.yDomain)
                    VStack(alignment: .leading, spacing: DKSpace.xs) {
                        TrackHeader(kind: kind, values: drawn.values, resolution: resolution)
                        HStack(spacing: 0) {
                            YAxisLabels(ticks: yTicks, domain: drawn.yDomain, probeID: "timeline.axis.value.\(track.rawValue)")
                                .frame(width: axisWidth)
                            ValueTrackChart(kind: kind, values: drawn.values, gaps: drawn.gaps, window: window,
                                            yDomain: drawn.yDomain, landing: model.landing,
                                            showsPoints: resolution == .original && drawn.values.count <= 160,
                                            comparison: drawn.comparison, yTicks: yTicks, timeTicks: timeTicks,
                                            calendar: model.calendar)
                                .equatable()
                                .overlay { CursorLine(model: model) }
                                .overlay { CursorBadge(model: model, track: track) }
                        }
                        .frame(height: kind.aggregation == .cumulative ? 56 : 84)
                    }
                }
            }
            // One row of clock times under the value tracks; every track has the dashed grid at the same ticks.
            axisRow { TimeRuler(window: window, calendar: model.calendar, probeID: "timeline.axis.time") }
        }
        .overlay { ScrubSurface(model: model, leading: axisWidth) }
    }

    static func title(of range: TimelineRange) -> String {
        switch range {
        case .day: "Tag"
        case .week: "Woche"
        case .month: "Monat"
        case .quarter: "3 Monate"
        case .year: "Jahr"
        }
    }
}

/// Hypnogram, the selected phase and the lane names. Its own view: only it reads the selected segment, so
/// picking a phase or scrubbing does not rebuild the whole Verlauf.
private struct SleepSection: View {
    let model: TimelineModel
    let window: DateInterval
    let axisWidth: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: DKSpace.s) {
            Label("Schlafphasen", systemImage: "moon.stars")
                .font(DKFont.label)
                .foregroundStyle(DKColor.textPrimary)
                .labelStyle(TintedIconLabel(tint: MetricStyle.of(.sleepDuration).color))
            HStack(spacing: 0) {
                Color.clear.frame(width: axisWidth).accessibilityHidden(true)
                VStack(spacing: 2) {
                    HypnogramTrack(segments: model.visibleSegments, window: window, selected: model.selectedSegment,
                                   calendar: model.calendar) { segment in
                        model.select(segment)
                    }
                    .overlay { CursorLine(model: model) }
                    TimeRuler(window: window, calendar: model.calendar)
                }
            }
            // The longest interval text is reserved (hidden), so picking or clearing a phase never moves the
            // tracks below.
            ZStack(alignment: .topLeading) {
                if let longest = model.visibleSegments.map({ hypnogramText($0) }).max(by: { $0.count < $1.count }) {
                    Text(longest)
                        .font(DKFont.label)
                        .wraps()
                        .hidden()
                        .accessibilityHidden(true)
                }
                if let segment = model.selectedSegment {
                    Text(hypnogramText(segment))
                        .font(DKFont.label)
                        .foregroundStyle(DKColor.textPrimary)
                        .wraps()
                        .accessibilityIdentifier("hypnogram.selection")
                }
            }
            HypnogramLegendColumn(hasUnknown: model.visibleSegments.contains { $0.phase == .unknown })
        }
        .dkMotion(.pointSelect, value: model.selectedSegment?.id)
    }

    private func hypnogramText(_ segment: SleepSegment) -> String {
        var text = "\(Hypnogram.describe(segment, calendar: model.calendar)) · \(segment.source.title)"
        if segment.phase == .unknown { text += " · Code \(segment.rawCode), vom Ring nicht zugeordnet" }
        return text
    }
}

/// The shared cursor drawn over one track (thin line). Reads only the cursor, so the charts stay untouched.
struct CursorLine: View {
    let model: TimelineModel
    var body: some View {
        GeometryReader { proxy in
            if let cursor = model.cursor {
                let x = CGFloat(model.fraction(of: cursor)) * proxy.size.width
                Rectangle()
                    .fill(DKColor.textPrimary.opacity(0.85))
                    .frame(width: 1.5, height: proxy.size.height)
                    .offset(x: x - 0.75)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// One surface over the value tracks: tap sets the cursor, hold and drag scrubs, horizontal drag moves the
/// window, pinch zooms. VoiceOver: swipe up/down moves to the next/previous original point.
///
/// Tap, hold-to-scrub and pan are read from one drag recogniser (simultaneous with the scroll view) instead of
/// three competing gestures: with a tap, a sequenced long press and a pan on the same view, a second tap shortly
/// after the first sometimes never reached the tap handler (UI test: the cursor stayed on the first point).
struct ScrubSurface: View {
    let model: TimelineModel
    /// Width of the y-axis gutter: the time axis starts after it.
    var leading: CGFloat = 0
    @State private var touch: Touch?
    @State private var zoomStart: DateInterval?

    /// One finger on the surface: when it went down, the window then, and what the touch turned into.
    private struct Touch {
        enum Mode { case undecided, scrub, pan, scroll }
        let began: Date
        let window: DateInterval
        var mode: Mode = .undecided
    }

    /// Holding this long before moving scrubs; moving earlier pans (horizontal) or scrolls (vertical).
    private static let holdToScrub: TimeInterval = 0.25
    private static let moveSlop: CGFloat = 12

    var body: some View {
        let _ = TimelineProbe.body("Fläche")
        GeometryReader { proxy in
            let width = max(proxy.size.width - leading, 1)
            Color.clear
                .contentShape(Rectangle())
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .local)
                        .onChanged { value in changed(value, width: width) }
                        .onEnded { value in ended(value, width: width) }
                )
                .simultaneousGesture(
                    MagnifyGesture()
                        .onChanged { value in
                            let start = zoomStart ?? model.visible
                            zoomStart = start
                            model.zoom(from: start, factor: Double(value.magnification),
                                       anchor: Double((value.startLocation.x - leading) / width))
                        }
                        .onEnded { _ in zoomStart = nil }
                )
        }
        .sensoryFeedback(.selection, trigger: model.selectedPoint?.id)
        .accessibilityElement()
        .accessibilityLabel("Zeitspuren")
        .accessibilityValue(chartValue)
        .accessibilityHint("Nach oben oder unten wischen springt zum nächsten oder vorigen Messpunkt.")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: model.stepCursor(forward: true)
            case .decrement: model.stepCursor(forward: false)
            @unknown default: break
            }
        }
        .accessibilityIdentifier("timeline.chart")
    }

    private var chartValue: String {
        let value = model.cursorRows.first.map { "\($0.title) \($0.value), \($0.time)" } ?? "Kein Zeitpunkt gewählt"
        // UI tests read the last touch from here; VoiceOver in normal use only hears the value.
        return LaunchOptions.current.usesTestScenario ? "\(value); Eingabe: \(model.lastInput); \(TimelineProbe.summary)" : value
    }

    private func changed(_ value: DragGesture.Value, width: CGFloat) {
        var current = touch ?? Touch(began: value.time, window: model.visible)
        let dx = value.translation.width, dy = value.translation.height
        if current.mode == .undecided {
            let moved = max(abs(dx), abs(dy)) >= Self.moveSlop
            let held = value.time.timeIntervalSince(current.began) >= Self.holdToScrub
            if held, !moved || abs(dx) >= abs(dy) {
                current.mode = .scrub
            } else if moved {
                current.mode = abs(dx) > abs(dy) * 1.5 ? .pan : .scroll
            }
        }
        switch current.mode {
        case .scrub:
            record("Halten", (value.location.x - leading) / width)
        case .pan:
            model.pan(from: current.window, by: -Double(dx / width) * current.window.duration)
        case .undecided, .scroll:
            break
        }
        touch = current
    }

    /// Sets the cursor at a fraction of the width and notes the input for UI tests.
    private func record(_ kind: String, _ fraction: CGFloat) {
        let started = Date.now
        defer { TimelineProbe.step(milliseconds: Date.now.timeIntervalSince(started) * 1000) }
        let time = model.time(atFraction: Double(fraction))
        model.setCursor(time)
        // The note is for UI tests only; in normal use it would wake the surface on every drag step.
        guard LaunchOptions.current.usesTestScenario else { return }
        model.lastInput = "\(kind) \(String(format: "%.2f", Double(fraction))) → \(time.formatted(TimelineModel.clock(model.calendar)))"
    }

    private func ended(_ value: DragGesture.Value, width: CGFloat) {
        defer { touch = nil }
        guard let current = touch else {
            // Down and up in one event: a tap.
            record("Tippen", (value.location.x - leading) / width)
            return
        }
        let still = max(abs(value.translation.width), abs(value.translation.height)) < Self.moveSlop
        if current.mode == .undecided, still {
            record("Tippen", (value.location.x - leading) / width)
        } else {
            model.lastInput = "\(current.mode)"
        }
    }
}

/// What the cursor points at, for every track: value, original measuring time, and the source on request.
struct CursorReadout: View {
    let model: TimelineModel
    @Binding var showsSource: Bool

    /// Always the same rows (one line per track) and the same buttons, so setting or moving the cursor never
    /// changes the card's height and never moves the tracks below. Without a cursor it shows each track's newest
    /// value. Only "Quelle", asked for by the person, adds lines.
    var body: some View {
        let _ = TimelineProbe.body("Anzeige")
        let atCursor = model.cursor != nil
        let rows = atCursor ? model.cursorRows : model.latestRows
        if !rows.isEmpty {
            DKCard {
                VStack(alignment: .leading, spacing: DKSpace.m) {
                    VStack(alignment: .leading, spacing: DKSpace.s) {
                        Text(heading(atCursor: atCursor))
                            .font(DKFont.caption)
                            .foregroundStyle(DKColor.textSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        ForEach(rows) { row in line(row, sources: atCursor && showsSource) }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(label(rows))
                    .accessibilityIdentifier("timeline.selection")
                    pointButtons(hasSource: atCursor && rows.contains(where: { $0.source != nil }))
                }
            }
        }
        // No spring and no selection haptic per cursor step: a drag sends dozens of steps (suspected in the
        // long busy time after a scrub, see TimelineProbe). The haptic for a newly picked original point
        // stays on the scrub surface.
    }

    /// "AM CURSOR · TRAINING · 45 MIN" or "ZULETZT GEMESSEN"; one line.
    private func heading(atCursor: Bool) -> String {
        guard atCursor else { return "ZULETZT GEMESSEN" }
        if let event = model.cursorEvent { return "AM CURSOR · TRAINING · \(event.detail.uppercased())" }
        return "AM CURSOR"
    }

    /// One line per track: name, value, and the measuring time (or "keine Messung" in a gap).
    private func line(_ row: CursorRow, sources: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: DKSpace.s) {
                Text(row.title)
                    .font(DKFont.label)
                    .foregroundStyle(DKColor.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: DKSpace.xs)
                Text(row.value)
                    .font(DKFont.bodyEmphasis)
                    .foregroundStyle(DKColor.textPrimary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(row.value == "–" ? "keine Messung" : row.time)
                    .font(DKFont.label)
                    .foregroundStyle(DKColor.textSecondary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            if sources, let source = row.source {
                Text(source).font(DKFont.caption).foregroundStyle(DKColor.textTertiary).wraps()
            }
        }
    }

    private func pointButtons(hasSource: Bool) -> some View {
        FlowLayout(spacing: DKSpace.s) {
            Button("Voriger Punkt") { model.stepCursor(forward: false) }
                .buttonStyle(DKPillButtonStyle())
                .accessibilityIdentifier("timeline.previousPoint")
            Button("Nächster Punkt") { model.stepCursor(forward: true) }
                .buttonStyle(DKPillButtonStyle())
                .accessibilityIdentifier("timeline.nextPoint")
            // Its place is always kept (hidden without a source), so the row never rewraps when the cursor moves.
            if hasSource {
                Button(showsSource ? "Quelle aus" : "Quelle") { showsSource.toggle() }
                    .buttonStyle(DKTextButtonStyle())
                    .accessibilityIdentifier("timeline.source")
            } else {
                Button("Quelle aus") {}
                    .buttonStyle(DKTextButtonStyle())
                    .hidden()
                    .accessibilityHidden(true)
            }
        }
    }

    private func label(_ rows: [CursorRow]) -> String {
        rows.map { row in
            [row.title, row.value, row.note == nil ? "gemessen \(row.time)" : row.time, row.note].compactMap { $0 }.joined(separator: " ")
        }
        .joined(separator: "; ")
    }
}
