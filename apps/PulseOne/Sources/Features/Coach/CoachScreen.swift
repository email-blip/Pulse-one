import SwiftUI

/// Placeholder root of the Coach tab. The Coach team replaces this file (INTEGRATION.md).
struct CoachScreen: View {
    var body: some View {
        NavigationStack {
            ZStack {
                ScreenBackground()
                ScrollView {
                    VStack(spacing: Spacing.l) {
                        if LaunchOptions.current.usesTestScenario { TestBanner() }
                        EmptyState(title: "Coach ist in Arbeit", message: "Dein Tagesplan aus Belastung und Erholung kommt mit diesem Bereich.", systemImage: "figure.run")
                    }
                    .padding(Spacing.l)
                }
            }
            .navigationTitle("Coach")
            .profileToolbar()
        }
        .screenIdentifier("coach")
    }
}
