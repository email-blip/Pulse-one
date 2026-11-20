import PulseCore
import SwiftData
import SwiftUI

@main
struct PulseOneApp: App {
    private let options = LaunchOptions.current
    private let container: ModelContainer
    @State private var ring: RingStore
    @State private var sources: SourcesStore

    init() {
        let options = LaunchOptions.current
        let container = Self.makeContainer(inMemory: options.isUITesting)
        let ring: RingStore
        let sources: SourcesStore
        if options.usesTestScenario, let scenario = options.scenario {
            ring = RingStore.preview(TestScenario.snapshot(for: scenario))
            sources = SourcesStore.preview(TestScenario.registry(for: scenario), owner: TestScenario.owner)
            TestScenario.insertSampleHistory(for: scenario, into: container.mainContext)
        } else {
            ring = RingStore.live()
            sources = SourcesStore.live()
        }
        sources.modelContext = container.mainContext
        // Test scenarios run the migration on their in-memory rows every time; the real store once.
        sources.migrateLegacyMeasurements(marker: options.isUITesting ? nil : .standard)
        ring.onMeasurement = { measurement in
            container.mainContext.insert(StoredMeasurement(measurement))
            sources.ingest(measurement)
        }
        self.container = container
        _ring = State(initialValue: ring)
        _sources = State(initialValue: sources)
    }

    var body: some Scene {
        WindowGroup {
            RootView(options: options)
                .environment(ring)
                .environment(sources)
                .modelContainer(container)
                // Cinematic dark is the PULSE ONE base; "Clinical Light" arrives with the design profiles.
                .preferredColorScheme(.dark)
                .modifier(DynamicTypeOverride(size: options.dynamicTypeSize))
        }
    }

    private static func makeContainer(inMemory: Bool) -> ModelContainer {
        let schema = Schema([StoredMeasurement.self, StoredSample.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        if let container = try? ModelContainer(for: schema, configurations: configuration) {
            return container
        }
        // A broken store must not stop the app from connecting to the ring.
        do {
            return try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
        } catch {
            fatalError("SwiftData unavailable: \(error)")
        }
    }
}

/// Applies the system Reduce Motion setting or a UI-test override as one environment value.
struct RootView: View {
    let options: LaunchOptions
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(RingStore.self) private var ring
    @Environment(SourcesStore.self) private var sources

    var body: some View {
        Group {
            // The heart scenario renders the chamber directly so the screenshot needs no tap.
            if options.usesTestScenario, options.scenario == "heart" {
                HeartChamberView()
            } else if options.usesTestScenario, options.scenario == "devices" {
                DevicesScreen(showsClose: false)
            } else {
                ConnectScreen(options: options)
            }
        }
            .environment(\.reduceMotionEffective, options.reduceMotion ?? systemReduceMotion)
            .environment(\.freezeAnimations, options.usesTestScenario)
            .transaction { if options.usesTestScenario { $0.disablesAnimations = true } }
            .onChange(of: ring.snapshot, initial: true) { _, snapshot in sources.noteRing(snapshot) }
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
