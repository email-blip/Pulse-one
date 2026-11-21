import PulseCore
import SwiftData
import SwiftUI

/// TODAY: greeting, source status, the newest values with their personal band, the ring, and the
/// cards the other modules contribute. Shows only stored real values (or the test scenario's, with banner).
struct TodayScreen: View {
    @Environment(RingStore.self) private var ring
    @Environment(SourcesStore.self) private var sources
    @Environment(ProfileStore.self) private var profile
    @Environment(\.modelContext) private var modelContext
    @State private var metrics: [TodayMetric] = []
    @State private var loaded = false
    @State private var customizing = false
    @AppStorage("today.layout") private var layoutData = Data()

    private var layout: TodayLayout { TodayLayout.decode(layoutData.isEmpty ? nil : layoutData) }

    private var visibleMetrics: [TodayMetric] {
        metrics.filter { layout.isVisible(.metric($0.kind)) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                ScreenBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.l) {
                        if LaunchOptions.current.usesTestScenario { TestBanner() }
                        header
                        ForEach(layout.visibleTiles) { tile in tileView(tile) }
                        if visibleMetrics.isEmpty, loaded {
                            EmptyState(title: "Noch keine Werte",
                                       message: "Sobald dein Ring misst oder Apple Health Daten liefert, erscheinen sie hier mit Uhrzeit und Quelle.",
                                       systemImage: "waveform.path.ecg")
                        }
                        Text("PULSE ONE beschreibt deine Werte im Vergleich zu deinem eigenen üblichen Bereich. Keine Diagnose, keine Vorhersage.")
                            .font(Typography.caption)
                            .foregroundStyle(Palette.inkMuted)
                            .wraps()
                    }
                    .padding(.horizontal, Spacing.l)
                    .padding(.bottom, Spacing.xl)
                }
            }
            .navigationTitle("Heute")
            .profileToolbar()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Anpassen") { customizing = true }
                        .accessibilityIdentifier("today.customize")
                }
            }
            .sheet(isPresented: $customizing) {
                TodayCustomizeSheet(layoutData: $layoutData)
                    .preferredColorScheme(.dark)
            }
            .task(id: refreshToken) { reload() }
        }
        .screenIdentifier("today")
    }

    @ViewBuilder
    private func tileView(_ tile: TodayTile) -> some View {
        switch tile {
        case .ring:
            ringCard
        case .appleHealth:
            if sources.healthAvailable, !sources.hasHealth { healthCard }
        case .coach:
            CoachTodayCard()
        case .metric(let kind):
            if let metric = metrics.first(where: { $0.kind == kind }) {
                MetricCard(title: metric.kind.title, systemImage: metric.kind.systemImage, value: metric.value,
                           unit: metric.unit, detail: metric.detail, bandText: metric.bandText,
                           tint: metric.kind == .heartRate || metric.kind == .restingHeartRate ? Palette.pulseCoral : Palette.bioCyan)
                    .accessibilityIdentifier("today.\(metric.kind.rawValue)")
            }
        case .nutrition:
            NutritionTodayCard()
        case .eveningNote:
            EveningNoteCard()
        }
    }

    /// Reload when a new ring value arrives or a Health sync finishes.
    private var refreshToken: String {
        "\(ring.snapshot.lastHeartRate?.timestamp.timeIntervalSince1970 ?? 0)|\(sources.syncing.count)|\(sources.devices.map(\.lastSuccessfulSync).compactMap { $0 }.max()?.timeIntervalSince1970 ?? 0)"
    }

    private func reload() {
        metrics = TodayModel.metrics(reader: SampleReader(context: modelContext), profileID: sources.ownerProfileID,
                                     now: LaunchOptions.current.usesTestScenario ? TestScenario.fixedTime : .now)
        loaded = true
    }

    private var header: some View {
        let now = LaunchOptions.current.usesTestScenario ? TestScenario.fixedTime : Date.now
        return VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(profile.profile.greeting(at: now, calendar: .current))
                .font(Typography.title)
                .foregroundStyle(Palette.ink)
                .wraps()
            Text(now.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "de_DE"))))
                .font(Typography.caption)
                .foregroundStyle(Palette.inkMuted)
                .wraps()
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private var ringCard: some View {
        let snapshot = ring.snapshot
        return Card {
            Label(snapshot.deviceName ?? snapshot.rememberedRing ?? "Ring", systemImage: "circle.circle")
                .font(Typography.label)
                .foregroundStyle(Palette.bioCyan)
                .wraps()
            Text(ringStatus(snapshot))
                .font(Typography.caption)
                .foregroundStyle(Palette.inkMuted)
                .wraps()
            if let reminder = ring.syncReminder {
                Label(reminder, systemImage: "clock.arrow.circlepath")
                    .font(Typography.caption.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                    .wraps()
                    .accessibilityIdentifier("today.syncReminder")
            }
            NavigationLink {
                ConnectScreen(options: LaunchOptions.current)
            } label: {
                Label(snapshot.connection.isConnected ? "Puls jetzt messen" : "Ring verbinden und messen", systemImage: "heart.fill")
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityIdentifier("openRing")
        }
    }

    private func ringStatus(_ snapshot: RingSnapshot) -> String {
        var parts = [snapshot.connection.label]
        if let battery = snapshot.battery { parts.append("Akku \(battery.level) %") }
        if let last = snapshot.lastHeartRate {
            parts.append("zuletzt \(last.value) bpm um \(last.timestamp.formatted(.dateTime.hour().minute().locale(Locale(identifier: "de_DE"))))")
        }
        return parts.joined(separator: " · ")
    }

    private var healthCard: some View {
        EmptyState(title: "Apple Health verbinden",
                   message: "PULSE ONE liest Schlaf, Schritte, Puls und mehr aus Apple Health. Die Daten bleiben auf diesem iPhone.",
                   systemImage: "heart.text.square", actionTitle: "Apple Health verbinden") {
            Task { await sources.connectHealth() }
        }
    }
}
