import SwiftUI

/// Placeholder root of the Ernährung tab. The Ernährung team replaces this file (INTEGRATION.md).
struct NutritionScreen: View {
    var body: some View {
        NavigationStack {
            ZStack {
                ScreenBackground()
                ScrollView {
                    VStack(spacing: Spacing.l) {
                        if LaunchOptions.current.usesTestScenario { TestBanner() }
                        EmptyState(title: "Ernährung ist in Arbeit", message: "Mahlzeiten, Barcode und Wasser kommen mit diesem Bereich.", systemImage: "fork.knife")
                    }
                    .padding(Spacing.l)
                }
            }
            .navigationTitle("Ernährung")
            .profileToolbar()
        }
        .screenIdentifier("nutrition")
    }
}
