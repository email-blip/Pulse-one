import SwiftUI

/// Placeholder root of the Analyse tab. The Analyse team replaces this file (INTEGRATION.md).
struct IntelligenceHubView: View {
    var body: some View {
        NavigationStack {
            ZStack {
                ScreenBackground()
                ScrollView {
                    VStack(spacing: Spacing.l) {
                        if LaunchOptions.current.usesTestScenario { TestBanner() }
                        EmptyState(title: "Analyse ist in Arbeit", message: "Claude-Analysen deiner Daten, Fragen und Experimente kommen mit diesem Bereich.", systemImage: "sparkles")
                    }
                    .padding(Spacing.l)
                }
            }
            .navigationTitle("Analyse")
            .profileToolbar()
        }
        .screenIdentifier("intelligence")
    }
}
