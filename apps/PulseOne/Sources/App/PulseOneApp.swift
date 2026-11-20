import PulseCore
import SwiftData
import SwiftUI

@main
struct PulseOneApp: App {
    private let options = LaunchOptions.current
    private let container: ModelContainer
    @State private var ring: RingStore

    init() {
        let options = LaunchOptions.current
        let container = Self.makeContainer(inMemory: options.isUITesting)
        let ring: RingStore
        if options.usesTestScenario, let scenario = options.scenario {
            ring = RingStore.preview(TestScenario.snapshot(for: scenario))
            TestScenario.insertSampleHistory(for: scenario, into: container.mainContext)
        } else {
            ring = RingStore.live()
        }
        ring.onMeasurement = { measurement in
            container.mainContext.insert(StoredMeasurement(measurement))
        }
        self.container = container
        _ring = State(initialValue: ring)
    }

    var body: some Scene {
        WindowGroup {
            RootView(options: options)
                .environment(ring)
                .modelContainer(container)
                // Cinematic dark is the PULSE ONE base; "Clinical Light" arrives with the design profiles.
                .preferredColorScheme(.dark)
                .modifier(DynamicTypeOverride(size: options.dynamicTypeSize))
        }
    }

    private static func makeContainer(inMemory: Bool) -> ModelContainer {
        let schema = Schema([StoredMeasurement.self])
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

    var body: some View {
        ConnectScreen(options: options)
            .environment(\.reduceMotionEffective, options.reduceMotion ?? systemReduceMotion)
            .environment(\.freezeAnimations, options.usesTestScenario)
            .transaction { if options.usesTestScenario { $0.disablesAnimations = true } }
    }
}

private struct DynamicTypeOverride: ViewModifier {
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
