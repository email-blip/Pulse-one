import PulseCore
import SwiftUI

/// Full-screen "Guten Morgen" ritual: one calm screen, one big button. After "Ich bin wach" the night is
/// evaluated, then the briefing appears section by section and is read aloud if the person wants that.
struct WakeUpView: View {
    let store: CompanionStore
    let profileID: UUID?
    let birthYear: Int?
    let firstName: String

    enum Step: Equatable {
        case confirm, loading, briefing
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(RingStore.self) private var ring
    @Environment(\.reduceMotionEffective) private var reduceMotion
    @Environment(\.freezeAnimations) private var freeze
    @State private var step: Step = .confirm
    @State private var revealed = 0
    @State private var speaker = BriefingSpeaker()
    @State private var done: Set<String> = []
    @Environment(\.modelContext) private var modelContext
    @State private var activation: ActivationStore?
    @State private var activationPlan: ActivationPlan?

    private static let revealAnimation = Animation.spring(duration: 0.5, bounce: 0.05)

    private var briefing: MorningBriefing? { store.today?.briefing ?? store.latestBriefing }

    var body: some View {
        ZStack {
            SunriseBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.l) {
                    if LaunchOptions.current.usesTestScenario { TestBanner() }
                    switch step {
                    case .confirm:
                        confirmStep
                    case .loading:
                        loadingStep
                    case .briefing:
                        briefingStep
                    }
                }
                .padding(.horizontal, Spacing.l)
                .padding(.vertical, Spacing.xl)
            }
        }
        .sensoryFeedback(.success, trigger: step) { old, new in old == .confirm && new == .loading }
        .onDisappear { speaker.stop() }
        .fullScreenCover(item: $activationPlan, onDismiss: { prepareActivation() }) { plan in
            if let activation {
                ActivationSessionView(store: activation, plan: plan, speaks: store.preferences.speaksBriefing)
                    .environment(\.reduceMotionEffective, reduceMotion)
                    .environment(\.freezeAnimations, freeze)
                    .modifier(DynamicTypeOverride(size: LaunchOptions.current.dynamicTypeSize))
                    .preferredColorScheme(.dark)
            }
        }
        .screenIdentifier(CompanionUI.wakeScenario)
    }

    private var greeting: String {
        firstName.isEmpty ? "Guten Morgen" : "Guten Morgen, \(firstName)"
    }

    private var confirmStep: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            Text(greeting)
                .font(Typography.wordmark)
                .foregroundStyle(Palette.ink)
                .wraps()
                .accessibilityAddTraits(.isHeader)
                .padding(.top, Spacing.xxl)
            Text("Nimm dir einen Moment. Wenn du bereit bist, tippe auf „Ich bin wach“. Dann wertet der Begleiter deine Nacht aus.")
                .font(Typography.body)
                .foregroundStyle(Palette.ink)
                .wraps()
                // Dark backing: the sunrise brightens behind this text while it rises (contrast audit, team 03 patch).
                .padding(Spacing.m)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Palette.obsidian.opacity(0.75)))
            Button(action: confirm) {
                Label("Ich bin wach", systemImage: "sun.max")
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityIdentifier("wake.confirm")
            Button("Später") { dismiss() }
                .buttonStyle(SecondaryButtonStyle())
                .accessibilityIdentifier("wake.later")
        }
    }

    private var loadingStep: some View {
        Card {
            ProgressView()
                .tint(Palette.bioCyan)
            Text(ring.snapshot.connection == .ready ? "Puls wird gemessen" : "Ring-Daten werden geladen")
                .font(Typography.title)
                .foregroundStyle(Palette.ink)
                .wraps()
            Text(ring.snapshot.connection == .ready
                 ? "Bleib etwa 30 Sekunden ruhig sitzen, die Hand still. Danach wird die Nacht mit deinem üblichen Bereich verglichen."
                 : "Bleib kurz sitzen. Die Nacht wird mit deinem üblichen Bereich verglichen.")
                .font(Typography.caption)
                .foregroundStyle(Palette.inkMuted)
                .wraps()
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("wake.loading")
    }

    @ViewBuilder
    private var briefingStep: some View {
        if let briefing {
            WakeBriefingHeader(briefing: briefing, speaker: speaker)
            ForEach(Array(briefing.sections.prefix(revealed))) { section in
                Card { BriefingSectionRow(section: section) }
                    .transition(reduceMotion ? AnyTransition.opacity : AnyTransition.move(edge: .bottom).combined(with: .opacity))
            }
            if revealed >= briefing.sections.count {
                QuickActionChecklist(actions: briefing.actions, done: $done)
                activationButton
                finishButton
            }
        } else {
            EmptyState(title: "Noch kein Morgenbericht",
                       message: store.lastError ?? "Für einen Bericht braucht es Ringdaten der letzten Nacht. Trag den Ring heute Nacht und öffne danach PULSE ONE.",
                       systemImage: "moon.zzz")
            activationButton
            finishButton
        }
    }

    /// Morning activation right after the briefing; hidden when the activation is switched off.
    @ViewBuilder
    private var activationButton: some View {
        if let activation, activation.settings.isEnabled {
            let plan = activation.plan(for: .morning, now: CompanionUI.now)
            let minutes = max(Int((Double(plan.estimatedSeconds) / 60).rounded()), 1)
            Button { activationPlan = plan } label: {
                Label(activation.isDone(.morning) ? "Aktivierung noch einmal (\(minutes) Min)" : "Aktivierung starten (\(minutes) Min)",
                      systemImage: "figure.strengthtraining.functional")
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityIdentifier("wake.activation")
        }
    }

    /// Plans the morning session with the day the briefing just produced.
    private func prepareActivation() {
        let current = activation ?? ActivationStore(context: modelContext)
        activation = current
        current.refresh(now: CompanionUI.now, profileID: profileID, day: store.today)
    }

    private var finishButton: some View {
        Button("Fertig") { finish() }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityIdentifier("wake.done")
    }

    private func confirm() {
        // An alarm-button moment (if waiting) is the more accurate wake time; the store consumes it on refresh.
        let wakeTime = PendingWake.peek() ?? Date.now
        step = .loading
        Task {
            let pulse = await MorningPulse.measure(with: ring, seconds: 30)
            // A refresh started elsewhere (screen, TODAY card) would make this one a no-op: wait for it.
            while store.isRefreshing {
                try? await Task.sleep(for: .milliseconds(200))
            }
            await store.refresh(profileID: profileID, birthYear: birthYear, firstName: firstName,
                                confirmedWake: wakeTime, morningHeartRate: pulse)
            prepareActivation()
            step = .briefing
            await reveal()
        }
    }

    private func reveal() async {
        guard let briefing else { return }
        if store.preferences.speaksBriefing && !LaunchOptions.current.isUITesting {
            speaker.speak(briefing.spokenScript)
        }
        let total = briefing.sections.count
        if reduceMotion || freeze {
            revealed = total
            return
        }
        while revealed < total {
            try? await Task.sleep(for: .milliseconds(700))
            withAnimation(Self.revealAnimation) { revealed += 1 }
        }
    }

    private func finish() {
        speaker.stop()
        dismiss()
    }
}

/// Day type, headline and the read-aloud control of the wake-up briefing.
private struct WakeBriefingHeader: View {
    let briefing: MorningBriefing
    let speaker: BriefingSpeaker

    var body: some View {
        Card {
            Text(briefing.dayType.title.uppercased())
                .font(Typography.motto)
                .tracking(1)
                .foregroundStyle(Palette.bioCyan)
                .wraps()
            Text(briefing.headline)
                .font(Typography.title)
                .foregroundStyle(Palette.ink)
                .wraps()
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("wake.headline")
            SpeakButton(text: briefing.spokenScript, speaker: speaker)
        }
        .accessibilityElement(children: .contain)
    }
}

/// Calm sunrise behind the wake-up flow: a soft glow rises slowly from the bottom edge.
/// Static under Reduce Motion, in screenshot runs and while the app is not active.
struct SunriseBackground: View {
    @Environment(\.reduceMotionEffective) private var reduceMotion
    @Environment(\.freezeAnimations) private var freeze
    @Environment(\.scenePhase) private var scenePhase
    @State private var start = Date.now

    private static let riseSeconds: Double = 45

    var body: some View {
        let still = reduceMotion || freeze || scenePhase != .active
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: still)) { context in
            let elapsed = context.date.timeIntervalSince(start)
            let progress = still ? 0.7 : min(max(elapsed / Self.riseSeconds, 0), 1)
            Canvas { canvas, size in
                Self.draw(in: &canvas, size: size, progress: progress)
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private static func draw(in canvas: inout GraphicsContext, size: CGSize, progress: Double) {
        let sky = CGRect(origin: .zero, size: size)
        canvas.fill(Path(sky), with: .linearGradient(
            Gradient(colors: [Palette.obsidian, Palette.obsidian, Palette.neuralViolet.opacity(0.18 + 0.12 * progress),
                              Palette.pulseCoral.opacity(0.10 + 0.25 * progress)]),
            startPoint: CGPoint(x: size.width / 2, y: 0), endPoint: CGPoint(x: size.width / 2, y: size.height)))

        let radius = max(size.width, 1) * 0.28
        let lift = CGFloat(1.08 - 0.22 * progress)
        let center = CGPoint(x: size.width / 2, y: size.height * lift)
        let glowRadius = radius * 2.6
        let glowRect = CGRect(x: center.x - glowRadius, y: center.y - glowRadius, width: glowRadius * 2, height: glowRadius * 2)
        canvas.fill(Path(ellipseIn: glowRect), with: .radialGradient(
            Gradient(colors: [Palette.pulseCoral.opacity(0.22 * progress + 0.08), Palette.neuralViolet.opacity(0.10), .clear]),
            center: center, startRadius: 0, endRadius: glowRadius))
        let sunRect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        canvas.fill(Path(ellipseIn: sunRect), with: .radialGradient(
            // No bright core: buttons and text pass over the sun and must keep their contrast (audit).
            Gradient(colors: [Palette.pulseCoral.opacity(0.30), Palette.pulseCoral.opacity(0.18), Palette.pulseCoral.opacity(0.03)]),
            center: center, startRadius: 0, endRadius: radius))
    }
}
