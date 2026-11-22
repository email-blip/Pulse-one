import PulseCore
import SwiftData
import SwiftUI
import UserNotifications

@main
struct PulseOneApp: App {
    private let options = LaunchOptions.current
    private let container: ModelContainer
    /// Set when the on-disk store could not be opened; the app then runs without saving and says so.
    private let storeProblem: String?
    @State private var ring: RingStore
    @State private var sources: SourcesStore
    @State private var profile: ProfileStore
    /// The one companion store: Begleiter screen, TODAY card and Analyse read the same morning report.
    @State private var companion: CompanionStore
    /// The active companion: automatic check-ins in the morning, at midday and in the evening.
    @State private var checkIns: CheckInService

    init() {
        let options = LaunchOptions.current
        let (container, storeProblem) = Self.makeContainer(inMemory: options.isUITesting)
        let ring: RingStore
        let sources: SourcesStore
        let profile: ProfileStore
        if options.usesTestScenario {
            profile = .preview(setupCompleted: options.scenario != "onboarding")
        } else if options.isUITesting {
            // Real-mode UI test: fresh install without a saved profile on disk.
            profile = .preview(UserProfile(), setupCompleted: false)
        } else {
            profile = .live()
        }
        if options.usesTestScenario, let scenario = options.scenario {
            ring = RingStore.preview(TestScenario.snapshot(for: scenario), trace: TestScenario.trace(for: scenario))
            sources = SourcesStore.preview(TestScenario.registry(for: scenario), owner: TestScenario.owner)
            TestScenario.insertSampleHistory(for: scenario, into: container.mainContext)
        } else {
            ring = RingStore.live()
            sources = SourcesStore.live()
        }
        sources.modelContext = container.mainContext
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
        // Test scenarios run the migration on their in-memory rows every time; the real store once.
        sources.migrateLegacyMeasurements(marker: options.isUITesting ? nil : .standard)
        ring.onMeasurement = { measurement in
            container.mainContext.insert(StoredMeasurement(measurement))
            sources.ingest(measurement)
        }
        ring.onHistory = { observations, deviceID in
            sources.ingestHistory(observations, deviceIdentifier: deviceID)
        }
        // After the test scenario's rows are in, so the store starts from the same data the screens show.
        let companion = CompanionStore(context: container.mainContext)
        let checkIns = CheckInService(context: container.mainContext, ring: ring, sources: sources, profile: profile,
                                      companion: companion, options: options)
        CheckInService.current = checkIns
        if !options.isUITesting { CheckInService.registerBackgroundTask() }
        self.container = container
        self.storeProblem = storeProblem
        _ring = State(initialValue: ring)
        _sources = State(initialValue: sources)
        _profile = State(initialValue: profile)
        _companion = State(initialValue: companion)
        _checkIns = State(initialValue: checkIns)
    }

    var body: some Scene {
        WindowGroup {
            RootView(options: options, storeProblem: storeProblem)
                .environment(ring)
                .environment(sources)
                .environment(profile)
                .environment(companion)
                .environment(checkIns)
                .modelContainer(container)
                // Cinematic dark is the PULSE ONE base; "Clinical Light" arrives with the design profiles.
                .preferredColorScheme(.dark)
                .modifier(DynamicTypeOverride(size: options.dynamicTypeSize))
        }
    }

    /// Opens the store. If the file cannot be opened, the ring still works on a temporary store,
    /// but the user is told that nothing is saved (no silent data loss, architecture 5.0 §6).
    private static func makeContainer(inMemory: Bool) -> (ModelContainer, String?) {
        let schema = Schema(PulseSchema.models)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        let failure: Error
        do {
            return (try ModelContainer(for: schema, configurations: configuration), nil)
        } catch {
            failure = error
        }
        let message = "Die Datenbank konnte nicht geöffnet werden. Neue Messungen werden in dieser Sitzung nicht gespeichert. "
            + "Bitte App neu starten; wenn das bleibt, Claude Bescheid geben. (\(String(describing: failure).prefix(160)))"
        do {
            let temporary = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            return (try ModelContainer(for: schema, configurations: temporary), message)
        } catch {
            fatalError("SwiftData unavailable: \(error)")
        }
    }
}

/// Applies the system Reduce Motion setting or a UI-test override as one environment value.
struct RootView: View {
    let options: LaunchOptions
    var storeProblem: String?
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(RingStore.self) private var ring
    @Environment(SourcesStore.self) private var sources
    @Environment(ProfileStore.self) private var profile
    @Environment(CheckInService.self) private var checkIns

    var body: some View {
        Group {
            // The heart scenario renders the chamber directly so the screenshot needs no tap.
            if options.usesTestScenario, options.scenario == "heart" {
                HeartChamberView()
            } else if options.usesTestScenario, options.scenario == "devices" {
                DevicesScreen(showsClose: false)
            } else if options.usesTestScenario, let scenario = options.scenario, TestScenario.ringScenarios.contains(scenario) {
                // Ring states are captured on the ring screen itself, as before the tab app.
                ConnectScreen(options: options)
            } else if options.usesTestScenario, let scenario = options.scenario, InsightDemo.scenarios.contains(scenario) {
                // The three synthetic insight cases (Codex P1-005), shown on their own with the test banner.
                NavigationStack { InsightScreen(demo: scenario) }
            } else if !profile.setupCompleted {
                SetupView()
            } else {
                MainTabView(options: options)
            }
        }
            .environment(\.reduceMotionEffective, options.reduceMotion ?? systemReduceMotion)
            .environment(\.freezeAnimations, options.usesTestScenario)
            .transaction { if options.usesTestScenario { $0.disablesAnimations = true } }
            .onChange(of: ring.snapshot, initial: true) { _, snapshot in sources.noteRing(snapshot) }
            // Apple Health is read on launch and on every return to the foreground (throttled in the store).
            .onChange(of: scenePhase, initial: true) { _, phase in
                if phase == .active {
                    // Ring history: on connect, and on return to the app when it is due.
                    if !options.usesTestScenario { ring.syncIfDue() }
                    Task {
                        await sources.syncHealthIfDue()
                        // The companion looks at the values by itself when a check-in is due.
                        if profile.setupCompleted {
                            await checkIns.requestNotificationPermission()
                            await checkIns.runIfDue(trigger: "foreground")
                        }
                    }
                } else if phase == .background {
                    checkIns.scheduleBackgroundRefresh()
                }
            }
            .safeAreaInset(edge: .top) {
                if let storeProblem {
                    Label(storeProblem, systemImage: "exclamationmark.triangle.fill")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.obsidian)
                        .padding(Spacing.m)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Palette.pulseCoral)
                        .accessibilityIdentifier("storeProblem")
                }
            }
    }
}

struct DynamicTypeOverride: ViewModifier {
    let size: DynamicTypeSize?
    func body(content: Content) -> some View {
        if let size { content.dynamicTypeSize(size) } else { content }
    }
}

extension EnvironmentValues {
    /// Use this instead of `accessibilityReduceMotion` so UI tests can force it.
    @Entry var reduceMotionEffective: Bool = false
    /// Screenshot runs freeze time-based animation for stable images.
    @Entry var freezeAnimations: Bool = false
}
