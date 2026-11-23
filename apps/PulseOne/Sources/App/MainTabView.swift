import PulseCore
import SwiftData
import SwiftUI

/// The four areas of PULSE ONE: Heute · Verlauf · Coach · Mehr (core rebuild 2026-11-23, like Oura).
/// Claude, Sprechstunde and the lab tools live under "Mehr". Profile, devices and the ring live in the
/// profile sheet that every tab opens from the top right. Module roots: see INTEGRATION.md.
enum AppTab: Hashable {
    // Nutrition left the tab bar on 2026-11-22 (owner's decision); its code stays for now.
    case today, health, intelligence, coach

    static func forScenario(_ scenario: String?) -> AppTab {
        switch scenario {
        case "health", "healthDetail": .health
        case "intelligence": .intelligence
        case "coach": .coach
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
            Tab("Verlauf", systemImage: "chart.xyaxis.line", value: AppTab.health) { HealthScreen() }
            Tab("Coach", systemImage: "figure.run", value: AppTab.coach) { CoachScreen() }
            Tab("Mehr", systemImage: "ellipsis.circle", value: AppTab.intelligence) { IntelligenceHubView() }
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
