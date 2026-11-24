import PulseCore
import SwiftData
import SwiftUI

// Detective, experiments and body biography left the productive app with the rebuild (Auftrag 04); their
// logic stays in PulseCore and their stored records stay untouched.

// MARK: History

struct AnalysisHistoryView: View {
    @Query(sort: \StoredAnalysis.createdAt, order: .reverse) private var analyses: [StoredAnalysis]
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        ZStack {
            ScreenBackground()
            ScrollView {
                VStack(spacing: Spacing.m) {
                    if LaunchOptions.current.usesTestScenario { TestBanner() }
                    if analyses.isEmpty {
                        EmptyState(title: "Noch keine Analysen", message: "Berichte und Fragen an Claude erscheinen hier mit Datum und Kosten.",
                                   systemImage: "clock")
                    }
                    ForEach(analyses) { analysis in
                        NavigationLink(value: IntelligenceRoute.analysis(analysis)) {
                            Card {
                                Text(analysis.question.isEmpty ? analysis.title : analysis.question)
                                    .font(Typography.label).foregroundStyle(Palette.ink).wraps()
                                RunFooter(analysis: analysis)
                                if analysis.failed {
                                    Text(analysis.errorMessage).font(Typography.caption).foregroundStyle(Palette.ink).wraps()
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    if !analyses.isEmpty {
                        Button("Verlauf löschen", role: .destructive) { deleteAll() }
                            .buttonStyle(SecondaryButtonStyle())
                    }
                }
                .padding(Spacing.l)
            }
        }
        .navigationTitle("Verlauf")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func deleteAll() {
        for analysis in analyses { modelContext.delete(analysis) }
        try? modelContext.save()
    }
}
