import PulseCore
import SwiftData
import SwiftUI

/// HEALTH: every kind with data in the last 90 days, newest value and number of days. Opens the
/// detail with charts for day, week, month and three months.
struct HealthScreen: View {
    @Environment(SourcesStore.self) private var sources
    @Environment(\.modelContext) private var modelContext
    @State private var rows: [HealthRow] = []
    @State private var loaded = false
    @State private var path: [SampleKind] = LaunchOptions.current.usesTestScenario && LaunchOptions.current.scenario == "healthDetail"
        ? [.restingHeartRate] : []

    struct HealthRow: Identifiable, Equatable {
        let kind: SampleKind
        let latest: String
        let days: Int
        var id: String { kind.rawValue }
    }

    /// Display order on HEALTH.
    static let order: [SampleKind] = [.heartRate, .restingHeartRate, .heartRateVariability, .oxygenSaturation,
                                      .respiratoryRate, .sleepDuration, .steps, .activeEnergy, .distance,
                                      .trainingDuration, .elevationGain, .basalEnergy, .vo2Max, .skinTemperature,
                                      .skinTemperatureDeviation, .bodyTemperature, .bodyMass, .height]

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                ScreenBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.m) {
                        if LaunchOptions.current.usesTestScenario { TestBanner() }
                        if rows.isEmpty, loaded {
                            EmptyState(title: "Noch keine Verläufe",
                                       message: "Verbinde deinen Ring oder Apple Health. Verläufe erscheinen, sobald Werte gespeichert sind.",
                                       systemImage: "chart.xyaxis.line")
                        }
                        ForEach(rows) { row in
                            NavigationLink(value: row.kind) {
                                HStack(spacing: Spacing.m) {
                                    Image(systemName: row.kind.systemImage)
                                        .font(.title3)
                                        .foregroundStyle(Palette.bioCyan)
                                        .frame(width: 32)
                                        .accessibilityHidden(true)
                                    VStack(alignment: .leading, spacing: Spacing.xs) {
                                        Text(row.kind.title)
                                            .font(Typography.label)
                                            .foregroundStyle(Palette.ink)
                                            .wraps()
                                        Text("\(row.latest) · \(row.days) \(row.days == 1 ? "Tag" : "Tage") mit Daten")
                                            .font(Typography.caption)
                                            .foregroundStyle(Palette.inkMuted)
                                            .wraps()
                                    }
                                    Spacer(minLength: 0)
                                    Image(systemName: "chevron.right")
                                        .foregroundStyle(Palette.inkMuted)
                                        .accessibilityHidden(true)
                                }
                                .padding(Spacing.l)
                                .background(RoundedRectangle(cornerRadius: Radius.medium, style: .continuous).fill(Palette.surfaceRaised))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("health.\(row.kind.rawValue)")
                        }
                    }
                    .padding(.horizontal, Spacing.l)
                    .padding(.bottom, Spacing.xl)
                }
            }
            .navigationTitle("Gesundheit")
            .profileToolbar()
            .navigationDestination(for: SampleKind.self) { MetricDetailScreen(kind: $0) }
            .task(id: sources.syncing.count) { reload() }
        }
        .screenIdentifier("health")
    }

    private func reload() {
        let reader = SampleReader(context: modelContext)
        let now = LaunchOptions.current.usesTestScenario ? TestScenario.fixedTime : Date.now
        let since = Calendar.current.date(byAdding: .day, value: -90, to: now) ?? now
        let samples = reader.samples(Set(Self.order), since: since, profileID: sources.ownerProfileID)
        rows = Self.order.compactMap { kind in
            let days = DailySeries.build(samples, kind: kind, calendar: .current)
            guard let last = days.last else { return nil }
            return HealthRow(kind: kind, latest: "\(kind.display(last.value)) \(kind.displayUnit)", days: days.count)
        }
        loaded = true
    }
}
