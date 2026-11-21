import Charts
import PulseCore
import SwiftData
import SwiftUI

/// One kind over time: chart for day/week/month/3 months, the personal band as a shaded area,
/// plain statistics, how the value is computed and the newest raw values with their source.
struct MetricDetailScreen: View {
    let kind: SampleKind
    @Environment(SourcesStore.self) private var sources
    @Environment(\.modelContext) private var modelContext
    @State private var range: TrendRange = .week
    @State private var points: [TrendPoint] = []
    @State private var baseline: BaselineStatus?
    @State private var recent: [HealthSample] = []
    @State private var caveats: [TotalCaveat] = []

    private var now: Date { LaunchOptions.current.usesTestScenario ? TestScenario.fixedTime : .now }

    var body: some View {
        ZStack {
            ScreenBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.l) {
                    if LaunchOptions.current.usesTestScenario { TestBanner() }
                    Picker("Zeitraum", selection: $range) {
                        ForEach(TrendRange.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("detail.range")
                    chartCard
                    if kind == .ringStress { vendorCard } else { bandCard }
                    methodCard
                    recentCard
                }
                .padding(.horizontal, Spacing.l)
                .padding(.bottom, Spacing.xl)
            }
        }
        .navigationTitle(kind.title)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: range) { reload() }
        .screenIdentifier("healthDetail")
    }

    private var isBar: Bool { kind.aggregation == .cumulative || kind.aggregation == .interval }
    private var showsBand: Bool { range != .day && kind != .ringStress && baseline?.baseline != nil }

    /// The ring's stress index is a vendor value: shown as a pattern over the day, never rated.
    private var vendorCard: some View {
        Card {
            Label("Herstellerwert", systemImage: "info.circle")
                .font(Typography.label)
                .foregroundStyle(Palette.bioCyan)
                .wraps()
            Text("Der Stressindex (0–100) wird vom Ring selbst berechnet; wie, legt der Hersteller nicht offen. PULSE ONE zeigt nur, wie er über den Tag verläuft, und bewertet einzelne Werte nicht.")
                .font(Typography.caption)
                .foregroundStyle(Palette.inkMuted)
                .wraps()
        }
    }

    private var chartCard: some View {
        Card {
            if points.isEmpty {
                Text("Keine Werte in diesem Zeitraum.")
                    .font(Typography.body)
                    .foregroundStyle(Palette.inkMuted)
                    .wraps()
            } else {
                Chart {
                    if showsBand, let band = baseline?.baseline, let first = points.first?.date, let last = points.last?.date {
                        RectangleMark(xStart: .value("Beginn", first), xEnd: .value("Ende", last),
                                      yStart: .value("unten", kind.displayNumber(band.lower)),
                                      yEnd: .value("oben", kind.displayNumber(band.upper)))
                            .foregroundStyle(Palette.bioCyan.opacity(0.18))
                            .accessibilityHidden(true)
                    }
                    ForEach(points) { point in
                        if isBar {
                            BarMark(x: .value("Zeit", point.date, unit: range == .day ? .hour : .day),
                                    y: .value(kind.title, kind.displayNumber(point.value)))
                                .foregroundStyle(Palette.bioCyan)
                        } else {
                            LineMark(x: .value("Zeit", point.date), y: .value(kind.title, kind.displayNumber(point.value)))
                                .foregroundStyle(Palette.bioCyan)
                                .interpolationMethod(.monotone)
                            PointMark(x: .value("Zeit", point.date), y: .value(kind.title, kind.displayNumber(point.value)))
                                // Only where the band is shown: hourly points against a band of daily means would mislead.
                                .foregroundStyle(showsBand && (point.value < (baseline?.baseline?.lower ?? -.infinity)
                                                               || point.value > (baseline?.baseline?.upper ?? .infinity))
                                                 ? Palette.neuralViolet : Palette.bioCyan)
                                .symbolSize(30)
                        }
                    }
                }
                .chartYScale(domain: .automatic(includesZero: isBar))
                .chartXAxis {
                    AxisMarks { _ in
                        AxisGridLine().foregroundStyle(Palette.hairline)
                        AxisValueLabel().foregroundStyle(Palette.inkMuted)
                    }
                }
                .chartYAxis {
                    AxisMarks { _ in
                        AxisGridLine().foregroundStyle(Palette.hairline)
                        AxisValueLabel().foregroundStyle(Palette.inkMuted)
                    }
                }
                .frame(height: 220)
                .accessibilityIdentifier("detail.chart")
                if let summary = TrendSeries.summary(points) {
                    Text("Median \(kind.display(summary.median)) · niedrigster \(kind.display(summary.minimum)) · höchster \(kind.display(summary.maximum)) \(kind.displayUnit) · \(points.count) \(range == .day ? "Stunden" : "Tage") mit Daten")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.inkMuted)
                        .wraps()
                }
            }
        }
    }

    private var bandCard: some View {
        Card {
            Label("Dein üblicher Bereich", systemImage: "chart.line.flattrend.xyaxis")
                .font(Typography.label)
                .foregroundStyle(Palette.bioCyan)
                .wraps()
            if let baseline = baseline?.baseline {
                Text("\(kind.display(baseline.lower))–\(kind.display(baseline.upper)) \(kind.displayUnit), Median \(kind.display(baseline.median))")
                    .font(Typography.body)
                    .foregroundStyle(Palette.ink)
                    .wraps()
                Text("Mittlere Hälfte deiner Tageswerte der letzten \(baseline.windowDays) Tage (\(baseline.dayCount) Tage mit Daten). Werte außerhalb sind violett markiert, das ist keine Bewertung.")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.inkMuted)
                    .wraps()
            } else {
                Text(baseline?.summary ?? "Wird berechnet …")
                    .font(Typography.body)
                    .foregroundStyle(Palette.ink)
                    .wraps()
            }
        }
    }

    private var methodCard: some View {
        Card {
            HStack { StatementBadge(kind: .computed); Spacer(minLength: 0) }
            Text("Wie berechnet: \(kind.dailyMeaning) je Tag\(range == .day && !isBar ? ", in der Tagesansicht je Stunde" : ""). Pro Minute oder Stunde zählt nur eine Quelle, damit nichts doppelt gezählt wird. Fehlende Tage bleiben Lücken.")
                .font(Typography.caption)
                .foregroundStyle(Palette.inkMuted)
                .wraps()
            ForEach(caveats, id: \.self) { caveat in
                Label(caveat.label, systemImage: "info.circle")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.ink)
                    .wraps()
            }
        }
    }

    private var recentCard: some View {
        Card {
            HStack { StatementBadge(kind: .measured); Spacer(minLength: 0) }
            if recent.isEmpty {
                Text("Keine Einzelwerte.")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.inkMuted)
            }
            ForEach(recent, id: \.id) { sample in
                HStack {
                    Text("\(kind.display(sample.value)) \(kind.displayUnit)")
                        .font(Typography.body.monospacedDigit())
                        .foregroundStyle(Palette.ink)
                    Spacer(minLength: Spacing.s)
                    Text("\(sample.start.formatted(.dateTime.day().month(.abbreviated).hour().minute().locale(Locale(identifier: "de_DE")))) · \(sample.source.title)")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.inkMuted)
                        .multilineTextAlignment(.trailing)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func reload() {
        let reader = SampleReader(context: modelContext)
        let calendar = Calendar.current
        let start = range.start(now: now, calendar: calendar)
        let windowStart = calendar.date(byAdding: .day, value: -(PersonalBaseline.defaultWindowDays + 1),
                                        to: calendar.startOfDay(for: now)) ?? start
        let samples = reader.samples([kind], since: min(start, windowStart), profileID: sources.ownerProfileID)
        points = TrendSeries.points(samples, kind: kind, range: range, now: now, calendar: calendar)
        let daily = DailySeries.build(samples, kind: kind, calendar: calendar)
        baseline = PersonalBaseline.status(for: daily, kind: kind, before: now, calendar: calendar)
        caveats = Array(Set(daily.flatMap(\.caveats))).sorted()
        recent = Array(samples.filter { $0.start <= now }.sorted { $0.start > $1.start }.prefix(8))
    }
}
