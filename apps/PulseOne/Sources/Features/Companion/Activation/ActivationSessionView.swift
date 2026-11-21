import PulseCore
import SwiftUI

/// Guided activation session, full screen: overview → warm-up → each round with a big target, a "Geschafft"
/// button and an adjustable count (holds with a countdown) → rest countdown → end with feedback and progress.
/// Can be ended early; the partial result is saved. Timers use wall-clock deadlines, so leaving the app for a
/// moment does not stretch a rest.
struct ActivationSessionView: View {
    let store: ActivationStore
    let plan: ActivationPlan
    /// Speak short cues with the companion's voice (the companion preference "Morgenbericht vorlesen").
    var speaks = false

    enum Phase: Equatable {
        case overview
        case exercise(Int)
        case rest(after: Int)
        case end
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.reduceMotionEffective) private var reduceMotion
    @State private var phase: Phase = .overview
    /// Seeded once from `plan`; a presented session never changes its plan.
    @State private var steps: [ActivationRunStep] = []
    @State private var done: [Int: Int] = [:]
    /// Count (reps or seconds) of the current step; starts at the target, adjustable.
    @State private var value = 0
    @State private var startedAt: Date?
    @State private var holdStartedAt: Date?
    @State private var holdDeadline: Date?
    @State private var restDeadline: Date?
    /// Seconds left of the running countdown (rest or hold).
    @State private var remaining = 0
    /// Bumped on every round change and timer end: one source for haptics.
    @State private var cue = 0
    @State private var feedback: ActivationFeedback?
    @State private var progressLines: [String] = []
    @State private var saved = false
    @State private var speaker = BriefingSpeaker()

    var body: some View {
        ZStack {
            ScreenBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.l) {
                    if LaunchOptions.current.usesTestScenario { TestBanner() }
                    content
                }
                .padding(.horizontal, Spacing.l)
                .padding(.vertical, Spacing.xl)
            }
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: cue)
        .task(id: timerKey) { await runTimer() }
        .onAppear { if steps.isEmpty { steps = ActivationRun.steps(for: plan) } }
        .onDisappear { speaker.stop() }
        .screenIdentifier(CompanionUI.activationScenario)
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .overview:
            ActivationOverview(plan: plan, onStart: { begin() }, onClose: { dismiss() })
        case .exercise(let index):
            if let step = runStep(at: index) {
                ActivationExerciseStep(step: step, position: index + 1, total: steps.count, value: $value,
                                       holdRunning: holdDeadline != nil, remaining: remaining,
                                       onDone: { markDone(index) }, onToggleHold: { toggleHold(step) },
                                       onEndEarly: { endEarly() })
            }
        case .rest(after: let index):
            ActivationRestStep(remaining: remaining, next: runStep(at: index + 1),
                               onSkip: { finishRest(after: index) }, onEndEarly: { endEarly() })
        case .end:
            ActivationEndStep(plan: plan, results: currentResults, isComplete: isComplete, feedback: feedback,
                              saved: saved, progressLines: progressLines, onFeedback: { choose($0) }, onFinish: { finish() })
        }
    }

    // MARK: Flow

    private func runStep(at index: Int) -> ActivationRunStep? {
        steps.indices.contains(index) ? steps[index] : nil
    }

    private var currentResults: [ActivationBlockResult] {
        ActivationRun.results(plan: plan, steps: steps, done: done)
    }

    private var isComplete: Bool {
        steps.allSatisfy { done[$0.id] != nil }
    }

    private func begin() {
        if steps.isEmpty { steps = ActivationRun.steps(for: plan) }
        startedAt = CompanionUI.now
        if steps.isEmpty {
            phase = .end
        } else {
            enter(0)
        }
    }

    private func enter(_ index: Int) {
        guard let step = runStep(at: index) else {
            phase = .end
            return
        }
        value = step.targetValue
        holdStartedAt = nil
        holdDeadline = nil
        restDeadline = nil
        change(to: .exercise(index))
        cue += 1
        speak(cueText(step))
    }

    private func markDone(_ index: Int) {
        if let holdStartedAt, holdDeadline != nil {
            value = heldSeconds(since: holdStartedAt)
        }
        holdStartedAt = nil
        holdDeadline = nil
        done[index] = max(value, 0)
        guard let step = runStep(at: index), index + 1 < steps.count else {
            change(to: .end)
            cue += 1
            return
        }
        let rest = Self.effectiveRest(step.restAfter)
        if rest > 0 {
            restDeadline = Date.now.addingTimeInterval(Double(rest))
            remaining = rest
            change(to: .rest(after: index))
            speak("Pause")
        } else {
            enter(index + 1)
        }
    }

    private func finishRest(after index: Int) {
        restDeadline = nil
        enter(index + 1)
    }

    private func toggleHold(_ step: ActivationRunStep) {
        if let holdStartedAt, holdDeadline != nil {
            value = heldSeconds(since: holdStartedAt)
            self.holdStartedAt = nil
            holdDeadline = nil
            return
        }
        let target = max(step.targetValue, 1)
        let start = Date.now
        holdStartedAt = start
        holdDeadline = start.addingTimeInterval(Double(target))
        remaining = target
    }

    private func heldSeconds(since start: Date) -> Int {
        max(Int(Date.now.timeIntervalSince(start).rounded()), 0)
    }

    private func endEarly() {
        if case .exercise(let index) = phase, let holdStartedAt, holdDeadline != nil {
            done[index] = heldSeconds(since: holdStartedAt)
        }
        holdStartedAt = nil
        holdDeadline = nil
        restDeadline = nil
        speaker.stop()
        change(to: .end)
    }

    private func choose(_ choice: ActivationFeedback) {
        guard !saved else { return }
        feedback = choice
        save(feedback: choice)
    }

    private func finish() {
        if !saved { save(feedback: nil) }
        speaker.stop()
        dismiss()
    }

    private func save(feedback: ActivationFeedback?) {
        let end = CompanionUI.now
        let result = ActivationResult(plan: plan, results: currentResults, feedback: feedback, finishedAt: end)
        progressLines = store.save(result: result, startedAt: startedAt ?? end)
        saved = true
    }

    private func change(to next: Phase) {
        if reduceMotion {
            phase = next
        } else {
            withAnimation(Self.phaseAnimation) { phase = next }
        }
    }

    private static let phaseAnimation = Animation.spring(duration: 0.35, bounce: 0.05)

    /// Rests are kept short in UI tests, but long enough to tap "Pause überspringen".
    static func effectiveRest(_ seconds: Int) -> Int {
        LaunchOptions.current.isUITesting ? min(max(seconds, 0), 5) : max(seconds, 0)
    }

    // MARK: Timer

    private var timerKey: String {
        switch phase {
        case .rest(after: let index): "rest-\(index)"
        case .exercise(let index): holdDeadline == nil ? "idle-\(index)" : "hold-\(index)"
        case .overview, .end: "idle"
        }
    }

    /// Ticks four times a second while a countdown runs; publishes only whole-second changes.
    private func runTimer() async {
        while !Task.isCancelled {
            guard let deadline = restDeadline ?? holdDeadline else { return }
            let left = max(Int(deadline.timeIntervalSinceNow.rounded(.up)), 0)
            if left != remaining { remaining = left }
            if left == 0 {
                timerEnded()
                return
            }
            try? await Task.sleep(for: .milliseconds(250))
        }
    }

    private func timerEnded() {
        cue += 1
        if case .rest(after: let index) = phase {
            finishRest(after: index)
            return
        }
        if case .exercise(let index) = phase, let step = runStep(at: index), holdDeadline != nil {
            value = step.targetValue
            holdStartedAt = nil
            holdDeadline = nil
            speak("Geschafft")
        }
    }

    // MARK: Voice

    private func cueText(_ step: ActivationRunStep) -> String {
        let name = ActivationLibrary.exercise(step.block.exerciseID)?.name ?? "Übung"
        let amount: String = step.isHold ? "\(step.targetValue) Sekunden" : "\(step.targetValue) Mal"
        if step.isWarmUp { return "Aufwärmen: \(name), \(amount)" }
        return "Runde \(step.round) von \(step.roundCount): \(name), \(amount)"
    }

    private func speak(_ text: String) {
        guard speaks else { return }
        speaker.speak(text)
    }
}

// MARK: - Overview

private struct ActivationOverview: View {
    let plan: ActivationPlan
    let onStart: () -> Void
    let onClose: () -> Void

    var body: some View {
        Card {
            CompanionCardTitle(title: plan.slot.title, systemImage: plan.slot.symbol)
            Text(plan.summary)
                .font(Typography.title)
                .foregroundStyle(Palette.ink)
                .wraps()
                .accessibilityAddTraits(.isHeader)
            Text(plan.reason)
                .font(Typography.body)
                .foregroundStyle(Palette.inkMuted)
                .wraps()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("activation.overview")
        if !plan.warmUp.isEmpty {
            SectionHeader(title: "Aufwärmen")
            ForEach(plan.warmUp) { block in
                ActivationBlockRow(block: block, rounds: max(block.rounds, 1))
            }
        }
        SectionHeader(title: plan.format == .circuit ? "Zirkel · \(ActivationText.rounds(max(plan.circuitRounds, 1)))" : "Übungen")
        ForEach(plan.blocks) { block in
            ActivationBlockRow(block: block, rounds: plan.format == .circuit ? 1 : max(block.rounds, 1))
        }
        Button(action: onStart) {
            Label("Los geht's", systemImage: "play.fill")
        }
        .buttonStyle(PrimaryButtonStyle())
        .accessibilityIdentifier("activation.begin")
        Button("Später", action: onClose)
            .buttonStyle(SecondaryButtonStyle())
            .accessibilityIdentifier("activation.close")
        Text("Bewege dich nur im schmerzfreien Bereich. Bei Schmerz, Schwindel oder Druck auf der Brust hörst du auf.")
            .font(Typography.caption)
            .foregroundStyle(Palette.inkMuted)
            .wraps()
    }
}

/// One exercise of the overview: target, rounds and the first steps.
private struct ActivationBlockRow: View {
    let block: ActivationBlock
    let rounds: Int

    var body: some View {
        let exercise = ActivationLibrary.exercise(block.exerciseID)
        Card {
            Text(ActivationText.target(block))
                .font(Typography.label)
                .foregroundStyle(Palette.ink)
                .wraps()
            if rounds > 1 {
                Text("\(rounds) Sätze")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.bioCyan)
                    .wraps()
            }
            if let exercise {
                ForEach(Array(exercise.steps.prefix(2)), id: \.self) { line in
                    Text(line)
                        .font(Typography.caption)
                        .foregroundStyle(Palette.inkMuted)
                        .wraps()
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Exercise

private struct ActivationExerciseStep: View {
    let step: ActivationRunStep
    let position: Int
    let total: Int
    @Binding var value: Int
    let holdRunning: Bool
    let remaining: Int
    let onDone: () -> Void
    let onToggleHold: () -> Void
    let onEndEarly: () -> Void

    var body: some View {
        let exercise = ActivationLibrary.exercise(step.block.exerciseID)
        let name = exercise?.name ?? "Übung"
        Card {
            Text(roundText)
                .font(Typography.motto)
                .tracking(1)
                .foregroundStyle(Palette.bioCyan)
                .wraps()
            Text(name)
                .font(Typography.title)
                .foregroundStyle(Palette.ink)
                .wraps()
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("activation.exerciseName")
            ActivationBigTarget(step: step, holdRunning: holdRunning, remaining: remaining)
            if let exercise {
                ActivationHowTo(exercise: exercise)
            }
        }
        .accessibilityElement(children: .contain)
        if step.isHold {
            Button(action: onToggleHold) {
                Label(holdRunning ? "Halten beenden" : "Halten starten",
                      systemImage: holdRunning ? "stop.fill" : "timer")
            }
            .buttonStyle(SecondaryButtonStyle())
            .accessibilityIdentifier("activation.holdToggle")
        }
        Stepper(value: $value, in: 0...maxValue) {
            Text(step.isHold ? "Gehalten: \(value) s" : "Geschafft: \(value)")
                .font(Typography.body)
                .foregroundStyle(Palette.ink)
                .wraps()
        }
        .accessibilityIdentifier("activation.stepper")
        Button(action: onDone) {
            Label("Geschafft", systemImage: "checkmark")
        }
        .buttonStyle(PrimaryButtonStyle())
        .accessibilityIdentifier("activation.done")
        Button("Einheit beenden", action: onEndEarly)
            .buttonStyle(SecondaryButtonStyle())
            .accessibilityIdentifier("activation.endEarly")
    }

    private var roundText: String {
        let round = step.isWarmUp ? "AUFWÄRMEN" : "RUNDE \(step.round) VON \(step.roundCount)"
        return "\(round) · SCHRITT \(position)/\(total)"
    }

    private var maxValue: Int { max(step.targetValue * 3, 10) }
}

/// The big number: repetitions, or the hold countdown while it runs.
private struct ActivationBigTarget: View {
    let step: ActivationRunStep
    let holdRunning: Bool
    let remaining: Int
    @ScaledMetric(relativeTo: .largeTitle) private var size: CGFloat = 64

    var body: some View {
        let shown = holdRunning ? remaining : step.targetValue
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("\(shown)")
                .font(Typography.vital(size: size))
                .foregroundStyle(Palette.ink)
                .contentTransition(.numericText())
                .wraps()
            Text(step.isHold ? (holdRunning ? "Sekunden noch halten" : "Sekunden halten") : "Wiederholungen")
                .font(Typography.label)
                .foregroundStyle(Palette.inkMuted)
                .wraps()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText(shown))
        .accessibilityIdentifier("activation.target")
    }

    private func accessibilityText(_ shown: Int) -> String {
        if step.isHold {
            return holdRunning ? "Noch \(shown) Sekunden halten" : "\(shown) Sekunden halten"
        }
        return "\(shown) Wiederholungen"
    }
}

/// Steps, easier option and safety line, folded away by default.
private struct ActivationHowTo: View {
    let exercise: Exercise

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: Spacing.s) {
                ForEach(Array(exercise.steps.enumerated()), id: \.element) { index, line in
                    Text("\(index + 1). \(line)")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.ink)
                        .wraps()
                }
                if let easier = exercise.easier {
                    Text("Leichter: \(easier)")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.inkMuted)
                        .wraps()
                }
                Text(exercise.safety)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.inkMuted)
                    .wraps()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, Spacing.s)
        } label: {
            Text("So geht's")
                .font(Typography.label)
                .foregroundStyle(Palette.ink)
                .wraps()
        }
        .tint(Palette.bioCyan)
        .accessibilityIdentifier("activation.howTo")
    }
}

// MARK: - Rest

private struct ActivationRestStep: View {
    let remaining: Int
    let next: ActivationRunStep?
    let onSkip: () -> Void
    let onEndEarly: () -> Void
    @ScaledMetric(relativeTo: .largeTitle) private var size: CGFloat = 64

    var body: some View {
        Card {
            CompanionCardTitle(title: "Pause", systemImage: "pause.circle")
            Text("\(remaining)")
                .font(Typography.vital(size: size))
                .foregroundStyle(Palette.ink)
                .contentTransition(.numericText())
                .wraps()
                .accessibilityLabel("Noch \(remaining) Sekunden Pause")
            if let next {
                Text("Als Nächstes: \(ActivationText.target(next.block))")
                    .font(Typography.body)
                    .foregroundStyle(Palette.inkMuted)
                    .wraps()
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("activation.rest")
        Button(action: onSkip) {
            Label("Pause überspringen", systemImage: "forward.fill")
        }
        .buttonStyle(PrimaryButtonStyle())
        .accessibilityIdentifier("activation.skipRest")
        Button("Einheit beenden", action: onEndEarly)
            .buttonStyle(SecondaryButtonStyle())
            .accessibilityIdentifier("activation.endEarly")
    }
}

// MARK: - End

private struct ActivationEndStep: View {
    let plan: ActivationPlan
    let results: [ActivationBlockResult]
    let isComplete: Bool
    let feedback: ActivationFeedback?
    let saved: Bool
    let progressLines: [String]
    let onFeedback: (ActivationFeedback) -> Void
    let onFinish: () -> Void

    var body: some View {
        Card {
            CompanionCardTitle(title: plan.slot.title, systemImage: "checkmark.circle")
            Text(isComplete ? "Geschafft. Gut gemacht." : "Für heute beendet. Jede Runde zählt.")
                .font(Typography.title)
                .foregroundStyle(Palette.ink)
                .wraps()
                .accessibilityAddTraits(.isHeader)
            ForEach(results, id: \.blockID) { result in
                ActivationResultRow(result: result)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("activation.end")
        SectionHeader(title: "Wie war es?")
        ForEach(ActivationFeedback.allCases, id: \.self) { choice in
            Button { onFeedback(choice) } label: {
                Label(choice.title, systemImage: feedback == choice ? "checkmark.circle.fill" : "circle")
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(saved && feedback != choice)
            .accessibilityIdentifier("activation.feedback.\(choice.rawValue)")
        }
        if saved {
            ActivationProgressCard(lines: progressLines)
        }
        Button("Fertig", action: onFinish)
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityIdentifier("activation.finish")
    }
}

private struct ActivationResultRow: View {
    let result: ActivationBlockResult

    var body: some View {
        let name = ActivationLibrary.exercise(result.exerciseID)?.name ?? "Übung"
        let isHold = ActivationLibrary.isHold(result.exerciseID)
        let parts = result.done.map { isHold ? "\($0) s" : "\($0)" }
        Text(parts.isEmpty ? "\(name): ausgelassen" : "\(name): \(parts.joined(separator: " + "))")
            .font(Typography.body)
            .foregroundStyle(Palette.ink)
            .wraps()
    }
}

private struct ActivationProgressCard: View {
    let lines: [String]

    var body: some View {
        Card {
            CompanionCardTitle(title: "Fortschritt", systemImage: "chart.line.uptrend.xyaxis")
            if lines.isEmpty {
                Text("Gespeichert. Die nächste Einheit passt sich daran an.")
                    .font(Typography.body)
                    .foregroundStyle(Palette.ink)
                    .wraps()
            } else {
                ForEach(lines, id: \.self) { line in
                    Text(line)
                        .font(Typography.body)
                        .foregroundStyle(Palette.ink)
                        .wraps()
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("activation.progress")
    }
}
