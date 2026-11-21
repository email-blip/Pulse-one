import PulseCore
import SwiftData
import SwiftUI

/// Coach summary on TODAY: the day's decision and main session. Details live in the Coach tab.
struct CoachTodayCard: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(SourcesStore.self) private var sources
    @State private var snapshot: CoachSnapshot?
    @State private var loaded = false

    var body: some View {
        Group {
            if let snapshot {
                Card {
                    HStack {
                        Label("Coach", systemImage: "figure.run")
                            .font(Typography.label)
                            .foregroundStyle(Palette.bioCyan)
                        Spacer()
                        StatementBadge(kind: .suggestion)
                    }
                    Text(snapshot.plan.suggested.kind == .rest
                         ? snapshot.plan.suggested.title
                         : "\(snapshot.plan.suggested.title) · \(snapshot.plan.suggested.minutes) min · \(snapshot.plan.suggested.intensity.title)")
                        .font(Typography.body)
                        .foregroundStyle(Palette.ink)
                        .wraps()
                    Text(snapshot.plan.decision.title + ". Details im Tab „Coach“.")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.inkMuted)
                        .wraps()
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("today.coach")
            } else if loaded {
                Card {
                    Label("Coach", systemImage: "figure.run")
                        .font(Typography.label)
                        .foregroundStyle(Palette.bioCyan)
                    Text("Im Tab „Coach“ bekommst du einen Tagesplan aus Belastung und Erholung, auch ganz ohne Sportart.")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.inkMuted)
                        .wraps()
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("today.coach")
            }
        }
        .task(id: sources.syncing.count) {
            let now = LaunchOptions.current.usesTestScenario ? TestScenario.fixedTime : Date.now
            snapshot = CoachRepository(context: modelContext).snapshot(now: now, profileID: sources.ownerProfileID)
            loaded = true
        }
    }
}
