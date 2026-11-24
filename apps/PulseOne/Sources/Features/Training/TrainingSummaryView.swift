import PulseCore
import SwiftData
import SwiftUI

/// After the session: what was done, how hard it felt (1–10), and what the ring measured – three separate
/// statements. Saved into the day's timeline (track `training`) only on "Speichern".
struct TrainingSummaryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(SourcesStore.self) private var sources
    @State private var exertion: Int?
    @State private var reaction: WorkoutReaction?
    private var training: TrainingController { .shared }

    private let columns = [GridItem(.adaptive(minimum: 56), spacing: Spacing.s)]

    var body: some View {
        ScrollView {
            if let summary = training.summary {
                VStack(alignment: .leading, spacing: Spacing.l) {
                    if LaunchOptions.current.usesTestScenario { TestBanner() }
                    Text(summary.finishedAsPlanned ? "Geschafft." : "Einheit beendet.")
                        .font(.system(.largeTitle, design: .rounded).weight(.bold))
                        .foregroundStyle(Palette.ink)
                        .wraps()
                        .accessibilityAddTraits(.isHeader)
                    execution(summary)
                    effort
                    if let reaction { measured(reaction) }
                    Button("Speichern") { save(summary) }
                        .buttonStyle(PrimaryButtonStyle())
                        .accessibilityIdentifier("workout.save")
                    Button("Verwerfen") { training.close() }
                        .buttonStyle(SecondaryButtonStyle())
                        .accessibilityIdentifier("workout.discard")
                }
                .padding(Spacing.l)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.workoutSummary")
        .task { loadReaction() }
    }

    private func execution(_ summary: WorkoutSummary) -> some View {
        Card {
            Text("DURCHFÜHRUNG")
                .font(Typography.motto)
                .tracking(1)
                .foregroundStyle(Palette.inkMuted)
            Text("\(summary.title) · \(summary.minutes) min")
                .font(Typography.title)
                .foregroundStyle(Palette.ink)
                .wraps()
            Text(summary.executionText)
                .font(Typography.caption)
                .foregroundStyle(Palette.ink)
                .wraps()
        }
        .accessibilityElement(children: .combine)
    }

    private var effort: some View {
        Card {
            Text("ANSTRENGUNG")
                .font(Typography.motto)
                .tracking(1)
                .foregroundStyle(Palette.inkMuted)
            Text("Wie hart war es? 1 ist ganz leicht, 10 ging nicht mehr.")
                .font(Typography.caption)
                .foregroundStyle(Palette.ink)
                .wraps()
            LazyVGrid(columns: columns, spacing: Spacing.s) {
                ForEach(1...10, id: \.self) { value in
                    Button {
                        exertion = value
                        training.setExertion(value)
                    } label: {
                        Text("\(value)")
                            .font(Typography.label.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .foregroundStyle(exertion == value ? Palette.obsidian : Palette.ink)
                            .background(Capsule().fill(exertion == value ? Palette.pulseCoral : Palette.surfaceButton))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Anstrengung \(value) von 10")
                    .accessibilityAddTraits(exertion == value ? .isSelected : [])
                    .accessibilityIdentifier("workout.exertion.\(value)")
                }
            }
        }
    }

    private func measured(_ reaction: WorkoutReaction) -> some View {
        Card {
            HStack {
                Text("GEMESSEN")
                    .font(Typography.motto)
                    .tracking(1)
                    .foregroundStyle(Palette.inkMuted)
                Spacer()
                StatementBadge(kind: .measured)
            }
            if let average = reaction.averageHeartRate, let peak = reaction.maxHeartRate {
                Text("Puls im Schnitt \(Int(average.rounded())), höchster \(Int(peak.rounded())) Schläge pro Minute")
                    .font(Typography.body)
                    .foregroundStyle(Palette.ink)
                    .wraps()
            }
            Text("\(reaction.sampleCount) Messungen während der Einheit")
                .font(Typography.caption)
                .foregroundStyle(Palette.inkMuted)
                .wraps()
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("workout.measured")
    }

    /// Pulse values of the session window from the stored samples (ring or Apple Health), nothing invented.
    private func loadReaction() {
        guard let summary = training.summary else { return }
        exertion = summary.perceivedExertion
        let samples = SampleReader(context: modelContext)
            .samples([.heartRate], since: summary.startedAt, profileID: sources.ownerProfileID)
            .map { (date: $0.start, bpm: $0.value) }
        reaction = WorkoutReaction.measure(heartRate: samples, during: summary.interval)
        training.setReaction(reaction)
    }

    private func save(_ summary: WorkoutSummary) {
        var saved = summary
        saved.perceivedExertion = exertion
        saved.reaction = reaction
        WorkoutLog(context: modelContext).save(saved, profileID: sources.ownerProfileID)
        training.markSaved(at: saved.endedAt)
        training.close()
    }
}
