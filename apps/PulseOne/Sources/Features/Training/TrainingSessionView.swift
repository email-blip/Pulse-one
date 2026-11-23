import PulseCore
import SwiftData
import SwiftUI

/// Presents the training session full screen from anywhere (Coach tab, ROOK's action on the dashboard).
/// Apply once near the root: `.trainingSessionCover()`.
struct TrainingSessionCover: ViewModifier {
    @Environment(\.modelContext) private var modelContext
    @Environment(SourcesStore.self) private var sources
    @Environment(\.reduceMotionEffective) private var reduceMotion
    @Environment(\.freezeAnimations) private var freeze

    func body(content: Content) -> some View {
        @Bindable var training = TrainingController.shared
        return content.fullScreenCover(isPresented: $training.isPresented) {
            // A cover starts a new presentation: hand over the environment explicitly.
            TrainingSessionView()
                .environment(sources)
                .modelContext(modelContext)
                .environment(\.reduceMotionEffective, reduceMotion)
                .environment(\.freezeAnimations, freeze)
                .modifier(DynamicTypeOverride(size: LaunchOptions.current.dynamicTypeSize))
        }
    }
}

extension View {
    func trainingSessionCover() -> some View { modifier(TrainingSessionCover()) }
}

/// The running session: big exercise name, moving figure, timer from timestamps, next phase, controls.
/// The summary takes over the same screen when the session ends.
struct TrainingSessionView: View {
    @Environment(\.scenePhase) private var scenePhase
    private var training: TrainingController { .shared }

    var body: some View {
        ZStack {
            ScreenBackground()
            if training.summary != nil {
                TrainingSummaryView()
            } else if let session = training.session {
                TrainingRunView(session: session, title: training.title)
            }
        }
        .preferredColorScheme(.dark)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { training.refresh() }
        }
    }
}

struct TrainingRunView: View {
    let session: WorkoutSession
    let title: String
    @Environment(\.reduceMotionEffective) private var reduceMotion
    @Environment(\.freezeAnimations) private var freeze
    @ScaledMetric(relativeTo: .largeTitle) private var timerSize: CGFloat = 76
    private var training: TrainingController { .shared }

    private var step: WorkoutStep? { session.currentStep }
    private var exercise: Exercise? { step.flatMap { ExerciseLibrary.exercise($0.exerciseID) } }

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.l) {
                header
                if LaunchOptions.current.usesTestScenario { TestBanner() }
                phaseChip
                Text(headline)
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                    .foregroundStyle(Palette.ink)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.6)
                    .wraps()
                    .accessibilityAddTraits(.isHeader)
                if let detail = detailLine {
                    Text(detail)
                        .font(Typography.label)
                        .foregroundStyle(Palette.inkMuted)
                        .multilineTextAlignment(.center)
                        .wraps()
                }
                ExerciseFigure(pattern: session.phase == .rest ? nil : exercise?.pattern,
                               isRest: session.phase == .rest,
                               isMoving: session.state == .running && !reduceMotion && !freeze)
                timer
                if let next = nextLine {
                    Text(next)
                        .font(Typography.caption)
                        .foregroundStyle(Palette.inkMuted)
                        .multilineTextAlignment(.center)
                        .wraps()
                        .accessibilityIdentifier("workout.next.label")
                }
                if session.phase == .work, let howTo = exercise?.steps.first {
                    Label(howTo, systemImage: "info.circle")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.inkMuted)
                        .wraps()
                }
                controls
            }
            .padding(.horizontal, Spacing.l)
            .padding(.bottom, Spacing.xl)
        }
        .scrollBounceBehavior(.basedOnSize)
        .sensoryFeedback(.impact(weight: .medium), trigger: "\(session.stepIndex)-\(session.phase.rawValue)")
        .sensoryFeedback(.success, trigger: session.state == .finished)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.workout")
    }

    // MARK: Parts

    private var header: some View {
        HStack {
            Button("Beenden") { training.finish() }
                .font(Typography.label)
                .foregroundStyle(Palette.ink)
                .frame(minHeight: 44)
                .accessibilityIdentifier("workout.finish")
            Spacer()
            Text("Abschnitt \(min(session.stepIndex + 1, session.steps.count)) von \(session.steps.count)")
                .font(Typography.caption)
                .foregroundStyle(Palette.inkMuted)
        }
        .padding(.top, Spacing.s)
    }

    private var phaseChip: some View {
        Text(phaseLabel.uppercased())
            .font(Typography.motto)
            .tracking(1.5)
            .foregroundStyle(Palette.obsidian)
            .padding(.horizontal, Spacing.m)
            .padding(.vertical, Spacing.xs)
            .background(Capsule().fill(phaseColor))
            .accessibilityLabel(phaseLabel)
            .accessibilityIdentifier("workout.state")
            .accessibilityValue(session.state.rawValue)
    }

    private var phaseLabel: String {
        switch session.state {
        case .idle: "Bereit"
        case .paused: "Pausiert"
        case .finished, .cancelled: "Ende"
        case .running: session.phase == .rest ? "Pause" : "Übung"
        }
    }

    private var phaseColor: Color {
        switch session.state {
        case .paused: Palette.inkMuted
        case .running: session.phase == .rest ? Palette.bioCyan : Palette.pulseCoral
        default: Palette.neuralViolet
        }
    }

    private var headline: String {
        if session.state == .idle { return title }
        if session.phase == .rest { return "Pause" }
        return step?.title ?? title
    }

    private var detailLine: String? {
        if session.state == .idle {
            return "\(session.steps.count) Abschnitte · ca. \(WorkoutBuilder.estimatedMinutes(session.steps)) Minuten"
        }
        guard session.phase == .work, let step else { return nil }
        let reps = step.repetitions.map { "\($0) Wiederholungen" }
        return [reps, step.variant].compactMap { $0 }.joined(separator: " · ").nilIfEmpty
    }

    private var nextLine: String? {
        guard session.state == .running || session.state == .paused else {
            return session.state == .idle ? session.steps.first.map { "Zuerst: \($0.title)" } : nil
        }
        if session.phase == .rest {
            return session.nextStep.map { "Danach: \($0.title)" }
        }
        guard let step else { return nil }
        guard let next = session.nextStep else { return "Danach: geschafft" }
        return step.restSeconds > 0 ? "Danach: \(step.restSeconds) s Pause · \(next.title)" : "Danach: \(next.title)"
    }

    @ViewBuilder
    private var timer: some View {
        if session.state == .idle {
            EmptyView()
        } else if session.phaseLength != nil {
            TimelineView(.periodic(from: .now, by: 0.5)) { context in
                let remaining = session.remaining(at: context.date) ?? 0
                let length = max(session.phaseLength ?? 1, 1)
                ZStack {
                    Circle()
                        .stroke(Palette.hairline, lineWidth: 8)
                    Circle()
                        .trim(from: 0, to: CGFloat(remaining / length))
                        .stroke(phaseColor, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text(Self.clock(remaining))
                        .font(.system(size: timerSize, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(Palette.ink)
                        .minimumScaleFactor(0.4)
                        .lineLimit(1)
                        .padding(Spacing.l)
                        .accessibilityLabel(Self.clock(remaining))
                        .accessibilityIdentifier("workout.remaining")
                }
                .frame(maxWidth: 260, maxHeight: 260)
                .aspectRatio(1, contentMode: .fit)
            }
        } else if let reps = step?.repetitions {
            Text("\(reps)×")
                .font(.system(size: timerSize, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(Palette.ink)
                .minimumScaleFactor(0.4)
                .lineLimit(1)
                .accessibilityLabel("\(reps) Wiederholungen")
                .accessibilityIdentifier("workout.remaining")
        }
    }

    @ViewBuilder
    private var controls: some View {
        VStack(spacing: Spacing.m) {
            switch session.state {
            case .idle:
                Button { training.start() } label: { Label("Start", systemImage: "play.fill") }
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("workout.start")
            case .running:
                if session.phase == .work, session.phaseLength == nil {
                    Button { training.next() } label: { Label("Fertig", systemImage: "checkmark") }
                        .buttonStyle(PrimaryButtonStyle())
                        .accessibilityIdentifier("workout.next")
                }
                Button { training.pause() } label: { Label("Pause", systemImage: "pause.fill") }
                    .buttonStyle(SecondaryButtonStyle())
                    .accessibilityIdentifier("workout.pause")
                skipButton
            case .paused:
                Button { training.resume() } label: { Label("Fortsetzen", systemImage: "play.fill") }
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("workout.resume")
                skipButton
            case .finished, .cancelled:
                EmptyView()
            }
        }
    }

    private var skipButton: some View {
        Button { training.skip() } label: {
            Label(session.phase == .rest ? "Pause überspringen" : "Überspringen", systemImage: "forward.end")
        }
        .buttonStyle(SecondaryButtonStyle())
        .accessibilityIdentifier("workout.skip")
    }

    /// "0:42", "12:05".
    static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.up)))
        return "\(total / 60):" + String(format: "%02d", total % 60)
    }
}

/// Placeholder figure until team 02's moving figure/3D lands: a symbol per movement pattern that breathes while
/// the phase runs (still under Reduce Motion and in screenshots).
struct ExerciseFigure: View {
    let pattern: MovementPattern?
    let isRest: Bool
    let isMoving: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [(isRest ? Palette.bioCyan : Palette.pulseCoral).opacity(0.35), .clear],
                                     center: .center, startRadius: 4, endRadius: 110))
            Image(systemName: symbol)
                .font(.system(size: 84, weight: .regular))
                .foregroundStyle(Palette.ink)
                .symbolEffect(.breathe, isActive: isMoving)
        }
        .frame(width: 200, height: 170)
        .accessibilityHidden(true)
    }

    private var symbol: String {
        if isRest { return "figure.cooldown" }
        switch pattern {
        case .push, .pull: return "figure.strengthtraining.traditional"
        case .squat, .lunge: return "figure.cross.training"
        case .hinge, .core: return "figure.core.training"
        case .endurance: return "figure.walk"
        case .mobility: return "figure.flexibility"
        case .breathing: return "lungs"
        case .balance: return "figure.mind.and.body"
        case .jump: return "figure.jumprope"
        case nil: return "figure.run"
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
