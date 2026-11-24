import PulseCore
import SwiftData
import SwiftUI

/// Where the dashboard navigates inside its own stack.
enum DashboardRoute: Hashable {
    /// The Verlauf, opened from a tile with a zoom transition from `source`.
    case timeline(TimelineFocus, source: String)
    case companion
    case connect
}

/// DASHBOARD (Neubau plan §4): ROOK's statement with one action and "Warum?", then the cockpit tiles in the
/// user's order (long press and drag, or the arrows while arranging), then last night's phases.
struct DashboardScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(SourcesStore.self) private var sources
    @Environment(RingStore.self) private var ring
    @Environment(AppNavigator.self) private var navigator
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.reduceMotionEffective) private var reduceMotion
    @Environment(\.freezeAnimations) private var frozen
    @State private var model = DashboardModel()
    @State private var layout = DashboardLayout.standard(subjectID: nil)
    @State private var layoutLoaded = false
    @State private var editing = LaunchOptions.current.usesTestScenario && LaunchOptions.current.scenario == "dashboardEdit"
    @State private var dropTarget: String?
    @State private var path: [DashboardRoute] = DashboardScreen.initialPath
    @State private var speaker = BriefingSpeaker()
    @Namespace private var zoom

    /// Companion test scenarios open the Begleiter directly (pushed, so it sits in this stack).
    private static var initialPath: [DashboardRoute] {
        let options = LaunchOptions.current
        let companion: Set<String> = ["companion", "companionWake", "companionConference", "companionActivation"]
        return options.usesTestScenario && companion.contains(options.scenario ?? "") ? [.companion] : []
    }

    private var now: Date { TimelineClock.now }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: DKSpace.xl) {
                    if showsOwnBanner { TestBanner() }
                    rook
                    if model.loaded, !model.hasAnyValue { connectRing }
                    cockpit
                    if let night = model.lastNight, let bed = night.inBed {
                        SleepPreview(night: night, calendar: model.calendar) {
                            open(TimelineFocus(track: .sleepPhases, cursor: nil, window: bed.padded(by: 3600)), source: "sleepPreview")
                        }
                        .matchedTransitionSource(id: "sleepPreview", in: zoom)
                    }
                }
                .padding(.horizontal, DKSpace.page)
                .padding(.bottom, DKSpace.xxl)
            }
            .dkPageBackground()
            .modifier(OpaqueUnderTabBar())
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("screen.dashboard")
            // Out of the accessibility tree while the profile or "Mehr" sheet covers it (one "orb" per screen).
            .accessibilityHidden(navigator.coveredBySheet)
            .navigationTitle("Dashboard")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { moreMenu }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: DKSpace.xs) {
                        RingStatusBadge()
                        ProfileButton()
                    }
                }
            }
            .navigationDestination(for: DashboardRoute.self) { route in destination(route) }
            .task(id: refreshToken) { reload() }
            .onDisappear { speaker.stop() }
        }
    }

    private var showsOwnBanner: Bool {
        let options = LaunchOptions.current
        return options.usesTestScenario && !TimelineDemo.liveClockScenarios.contains(options.scenario ?? "")
    }

    private var refreshToken: String {
        let day = Calendar.current.startOfDay(for: .now).timeIntervalSince1970
        return "\(ring.snapshot.lastHeartRate?.timestamp.timeIntervalSince1970 ?? 0)|\(ring.lastHistorySync?.timeIntervalSince1970 ?? 0)|\(sources.syncing.count)|\(day)|\(scenePhase == .active)|\(sources.ownerProfileID)"
    }

    private func reload() {
        if !layoutLoaded {
            // UI tests start a layout test from the standard order (`-resetDashboardLayout YES`).
            if LaunchOptions.current.usesTestScenario, ProcessInfo.processInfo.arguments.contains("-resetDashboardLayout") {
                UserDefaults.standard.removeObject(forKey: layoutKey)
            }
            layout = DashboardLayout.restore(UserDefaults.standard.data(forKey: layoutKey), subjectID: sources.ownerProfileID)
            layoutLoaded = true
        }
        withAnimation(MotionEvent.measurementLands.resolvedAnimation(reduceMotion: reduceMotion, frozen: frozen)) {
            model.reload(context: modelContext, profileID: sources.ownerProfileID, now: now)
        }
    }

    // MARK: ROOK

    /// Team 04's ROOK card (statement, action, "Warum?", corrections); actions and evidence reach the other tabs
    /// through the handlers MainTabView sets. "Vorlesen" reads the statement aloud.
    private var rook: some View {
        VStack(alignment: .trailing, spacing: DKSpace.s) {
            RookCard()
            Button(action: toggleSpeech) {
                Label(speaker.isSpeaking ? "Stopp" : "Vorlesen", systemImage: speaker.isSpeaking ? "stop.fill" : "speaker.wave.2")
            }
            .buttonStyle(DKPillButtonStyle())
            .accessibilityIdentifier("rook.speak")
        }
    }

    /// Without any stored value (real mode before the first sync) the ring is one tap away.
    private var connectRing: some View {
        DKCard {
            Text("Noch keine Werte. Verbinde deinen Ring, dann zeige ich dir hier deine Nacht und deinen Tag.")
                .font(DKFont.body)
                .foregroundStyle(DKColor.textPrimary)
                .wraps()
            Button { path.append(.connect) } label: {
                Label("Ring verbinden", systemImage: "circle.circle")
            }
            .buttonStyle(DKPrimaryButtonStyle())
            .accessibilityIdentifier("openRing")
        }
    }

    private func toggleSpeech() {
        if speaker.isSpeaking {
            speaker.stop()
        } else if let statement = RookStore.shared.current {
            speaker.speak("\(statement.headline) \(statement.insight.interpretation)")
        } else {
            speaker.speak("Hallo, schön, dass du da bist. Wie fühlst du dich heute?")
        }
    }

    // MARK: Cockpit

    private var cockpit: some View {
        VStack(alignment: .leading, spacing: DKSpace.m) {
            DKSectionHeader(title: "Dein Cockpit", actionTitle: editing ? "Fertig" : "Kacheln anordnen",
                            actionIdentifier: editing ? "dashboard.editDone" : "dashboard.edit") {
                withAnimation(MotionEvent.tileSwap.resolvedAnimation(reduceMotion: reduceMotion, frozen: frozen)) {
                    editing.toggle()
                    dropTarget = nil
                }
            }
            if editing {
                Text("Halte eine Kachel gedrückt und zieh sie an ihren Platz, oder nutze die Pfeile. Größe und Sichtbarkeit stellst du an jeder Kachel ein.")
                    .font(DKFont.caption)
                    .foregroundStyle(DKColor.textSecondary)
                    .wraps()
            }
            let shown = editing ? layout.tiles : layout.visibleTiles
            let rows = typeSize.isAccessibilitySize ? shown.map { [$0] } : DashboardGrid.rows(shown)
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .top, spacing: DKSpace.m) {
                    ForEach(row) { tile in cell(tile) }
                    if row.count == 1, row[0].size == .small, !typeSize.isAccessibilitySize {
                        Color.clear.frame(maxWidth: .infinity).accessibilityHidden(true)
                    }
                }
            }
        }
        .dkMotion(.tileSwap, value: layout.tiles.map(\.id))
    }

    private func cell(_ tile: DashboardTile) -> some View {
        let visible = layout.visibleTiles
        let position = visible.firstIndex { $0.id == tile.id }
        return DashboardTileCell(
            tile: tile, reading: model.readings[tile.id], editing: editing, isDropTarget: dropTarget == tile.id,
            canMoveUp: (position ?? 0) > 0, canMoveDown: position.map { $0 < visible.count - 1 } ?? false,
            onOpen: { openTile(tile) },
            onMove: { offset in change { $0.step(id: tile.id, by: offset) } },
            onResize: { size in change { $0.resize(tile.id, to: size) } },
            onToggle: { change { $0.setVisible(tile.id, !tile.isVisible) } })
            .matchedTransitionSource(id: tile.id, in: zoom)
            .draggable(tile.id) {
                Label(tile.title, systemImage: tile.systemImage)
                    .font(DKFont.label)
                    .padding(DKSpace.m)
                    .background(Capsule().fill(DKColor.surfaceRaised))
            }
            .dropDestination(for: String.self) { items, _ in
                guard let moved = items.first, moved != tile.id, let target = layout.tiles.firstIndex(where: { $0.id == tile.id }) else {
                    return false
                }
                change { $0.move(id: moved, to: target) }
                dropTarget = nil
                return true
            } isTargeted: { targeted in
                if targeted { dropTarget = tile.id } else if dropTarget == tile.id { dropTarget = nil }
            }
    }

    private var layoutKey: String {
        DashboardLayout.storageKey(subjectID: sources.ownerProfileID,
                                   namespace: LaunchOptions.current.usesTestScenario ? "test.\(LaunchOptions.current.scenario ?? "")" : nil)
    }

    private func change(_ edit: (inout DashboardLayout) -> Void) {
        withAnimation(MotionEvent.tileSwap.resolvedAnimation(reduceMotion: reduceMotion, frozen: frozen)) {
            edit(&layout)
        }
        UserDefaults.standard.set(layout.encoded(), forKey: layoutKey)
    }

    private func openTile(_ tile: DashboardTile) {
        guard !editing else { return }
        let reading = model.readings[tile.id]
        var window: DateInterval?
        if tile.id == "sleep", let bed = model.lastNight?.inBed { window = bed.padded(by: 3600) }
        open(TimelineFocus(track: tile.track, cursor: window == nil ? reading?.at : nil, window: window), source: tile.id)
    }

    private func open(_ focus: TimelineFocus, source: String) {
        path.append(.timeline(focus, source: source))
    }

    @ViewBuilder
    private func destination(_ route: DashboardRoute) -> some View {
        switch route {
        case .timeline(let focus, let source):
            if reduceMotion {
                TimelineScreen(focus: focus)
            } else {
                TimelineScreen(focus: focus).navigationTransition(.zoom(sourceID: source, in: zoom))
            }
        case .companion:
            CompanionScreen()
        case .connect:
            ConnectScreen(options: LaunchOptions.current)
        }
    }

    /// Older areas that are not rebuilt yet (Begleiter, analyses). Team 04 retires them.
    private var moreMenu: some View {
        Menu {
            Button { path.append(.companion) } label: { Label("Begleiter", systemImage: "sun.horizon") }
            Button { navigator.showMore = true } label: { Label("Analysen", systemImage: "sparkles") }
            Button { path.append(.connect) } label: { Label("Ring und Messung", systemImage: "circle.circle") }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.title3)
                .frame(minWidth: DKSize.minTouch, minHeight: DKSize.minTouch)
        }
        .accessibilityLabel("Mehr")
        .accessibilityIdentifier("dashboard.more")
    }
}

extension DateInterval {
    func padded(by seconds: TimeInterval) -> DateInterval {
        DateInterval(start: start.addingTimeInterval(-seconds), end: end.addingTimeInterval(seconds))
    }
}

/// Discreet ring status next to the profile button: dot + battery while connected.
struct RingStatusBadge: View {
    @Environment(RingStore.self) private var ring
    @Environment(\.openProfile) private var openProfile

    var body: some View {
        let snapshot = ring.snapshot
        let connected = snapshot.connection.isConnected
        Button { openProfile() } label: {
            HStack(spacing: DKSpace.xs) {
                Image(systemName: connected ? "circle.circle.fill" : "circle.circle")
                    .foregroundStyle(connected ? DKColor.accent : DKColor.textTertiary)
                if connected, let battery = snapshot.battery {
                    Text("\(battery.level) %")
                        .font(DKFont.caption)
                        .foregroundStyle(DKColor.textSecondary)
                        .monospacedDigit()
                }
            }
            .frame(minHeight: DKSize.minTouch)
        }
        .accessibilityLabel(connected ? "Ring verbunden" : "Ring nicht verbunden")
        .accessibilityValue(connected ? snapshot.battery.map { "Akku \($0.level) Prozent" } ?? "" : "")
        .accessibilityIdentifier("ring.status")
    }
}
