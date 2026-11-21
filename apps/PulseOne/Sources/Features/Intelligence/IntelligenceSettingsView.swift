import SwiftUI

/// Placeholder for the AI provider settings (API key, model, sharing, budget). The Intelligence team replaces this file.
struct IntelligenceSettingsView: View {
    var body: some View {
        ZStack {
            ScreenBackground()
            EmptyState(title: "KI-Anbieter", message: "Hier gibst du später deinen eigenen Claude-Schlüssel ein. Er bleibt im Schlüsselbund dieses iPhones.",
                       systemImage: "key")
                .padding(Spacing.l)
        }
        .navigationTitle("KI-Anbieter")
    }
}
