import PulseCore
import SwiftData
import SwiftUI

/// The three areas of PULSE ONE (rebuild M1, 2026-11-23): Dashboard · Verlauf · Coach. Profile, ring and
/// status sit discreetly top right; Begleiter, analyses and Sprechstunde open from the dashboard's "Mehr".
enum AppTab: Hashable {
    case dashboard, timeline, coach

    static func forScenario(_ scenario: String?) -> AppTab {
        switch scenario {
        case "timeline", "timelineHypnogram", "timelineYear", "health", "healthDetail": .timeline
        case "coach", "rookPositive", "rookClarify": .coach
        default: .dashboard
        }
    }
}

struct MainTabView: View {
    let options: LaunchOptions
    @State private var navigator: AppNavigator
    @State private var showProfile: Bool
    @Environment(RingStore.self) private var ring
    @Environment(SourcesStore.self) private var sources
    @Environment(ProfileStore.self) private var profile
    @Environment(CompanionStore.self) private var companion
    @Environment(CheckInService.self) private var checkIns
    @Environment(\.modelContext) private var modelContext
    @Environment(\.reduceMotionEffective) private var reduceMotion
    @Environment(\.freezeAnimations) private var freeze

    init(options: LaunchOptions) {
        self.options = options
        let scenario = options.usesTestScenario ? options.scenario : nil
        _navigator = State(initialValue: AppNavigator(tab: AppTab.forScenario(scenario),
                                                      showMore: scenario == "intelligence"))
        _showProfile = State(initialValue: options.usesTestScenario && options.scenario == "profile")
    }

    var body: some View {
        @Bindable var navigator = navigator
        TabView(selection: $navigator.tab) {
            Tab("Dashboard", systemImage: "square.grid.2x2", value: AppTab.dashboard) { DashboardScreen() }
            Tab("Verlauf", systemImage: "chart.xyaxis.line", value: AppTab.timeline) { TimelineTab() }
            Tab("Coach", systemImage: "figure.run", value: AppTab.coach) { CoachScreen() }
        }
        .tint(DKColor.accent)
        .environment(navigator)
        // ROOK's evidence ("Warum?", team 04) opens the Verlauf here; its action handler belongs to 05 (#61).
        .environment(\.openTimeline, RookTimelineHandler { [nav = self.navigator] state in nav.openTimeline(state: state) })
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
        .sheet(isPresented: $navigator.showMore) {
            MoreHubSheet(options: options)
                .environment(ring)
                .environment(sources)
                .environment(profile)
                .environment(companion)
                .environment(checkIns)
                .environment(navigator)
                .modelContext(modelContext)
                .environment(\.reduceMotionEffective, reduceMotion)
                .environment(\.freezeAnimations, freeze)
                .preferredColorScheme(.dark)
                .modifier(DynamicTypeOverride(size: options.dynamicTypeSize))
        }
    }
}

/// The Verlauf tab; rebuilt at the requested place whenever a tile, the sleep preview or "Warum?" opens it.
private struct TimelineTab: View {
    @Environment(AppNavigator.self) private var navigator

    var body: some View {
        NavigationStack {
            TimelineScreen(focus: navigator.timelineFocus)
                .id(navigator.timelineRequest)
                .profileToolbar()
        }
    }
}

/// Begleiter, analyses and Sprechstunde (Team 04's hub) until they find their place in Coach; the profile
/// opens as a nested sheet so the hub's own profile button keeps working.
private struct MoreHubSheet: View {
    let options: LaunchOptions
    @State private var showProfile = false
    @Environment(RingStore.self) private var ring
    @Environment(SourcesStore.self) private var sources
    @Environment(ProfileStore.self) private var profile
    @Environment(\.modelContext) private var modelContext
    @Environment(\.reduceMotionEffective) private var reduceMotion
    @Environment(\.freezeAnimations) private var freeze

    var body: some View {
        IntelligenceHubView()
            .environment(\.openProfile) { showProfile = true }
            .sheet(isPresented: $showProfile) {
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
