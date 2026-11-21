import PulseCore
import SwiftData
import SwiftUI

/// The five areas of PULSE ONE (DESIGN-SYSTEM-5.0 §2). Profile, devices and the ring live in the
/// profile sheet that every tab opens from the top right. Module roots: see INTEGRATION.md.
enum AppTab: Hashable {
    case today, health, intelligence, coach, nutrition

    static func forScenario(_ scenario: String?) -> AppTab {
        switch scenario {
        case "health", "healthDetail": .health
        case "intelligence": .intelligence
        case "coach": .coach
        case "nutrition": .nutrition
        default: .today
        }
    }
}

struct MainTabView: View {
    let options: LaunchOptions
    @State private var tab: AppTab
    @State private var showProfile: Bool
    @Environment(RingStore.self) private var ring
    @Environment(SourcesStore.self) private var sources
    @Environment(ProfileStore.self) private var profile
    @Environment(\.modelContext) private var modelContext
    @Environment(\.reduceMotionEffective) private var reduceMotion
    @Environment(\.freezeAnimations) private var freeze

    init(options: LaunchOptions) {
        self.options = options
        _tab = State(initialValue: AppTab.forScenario(options.scenario))
        _showProfile = State(initialValue: options.usesTestScenario && options.scenario == "profile")
    }

    var body: some View {
        TabView(selection: $tab) {
            Tab("Heute", systemImage: "sun.horizon", value: AppTab.today) { TodayScreen() }
            Tab("Gesundheit", systemImage: "heart.text.square", value: AppTab.health) { HealthScreen() }
            Tab("Analyse", systemImage: "sparkles", value: AppTab.intelligence) { IntelligenceHubView() }
            Tab("Coach", systemImage: "figure.run", value: AppTab.coach) { CoachScreen() }
            Tab("Ernährung", systemImage: "fork.knife", value: AppTab.nutrition) { NutritionScreen() }
        }
        .tint(Palette.bioCyan)
        .environment(\.openProfile) { showProfile = true }
        .sheet(isPresented: $showProfile) {
            // Sheets start a new presentation: hand over the environment explicitly.
            ProfileSheet(options: options)
                .environment(ring)
                .environment(sources)
                .environment(profile)
                .modelContext(modelContext)
                .environment(\.reduceMotionEffective, reduceMotion)
                .environment(\.freezeAnimations, freeze)
                .preferredColorScheme(.dark)
                .modifier(DynamicTypeOverride(size: options.dynamicTypeSize))
        }
    }
}
