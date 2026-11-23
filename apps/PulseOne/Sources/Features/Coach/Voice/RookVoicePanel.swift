import PulseCore
import SwiftUI

/// Talking with ROOK: one big microphone button, then hands-free. Shows what ROOK hears live and the last turns.
/// The conversation starts only on a tap and ends with the button, ~30 s of silence, a call, or leaving the app.
struct RookVoicePanel: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var voice = VoiceConversation.shared

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            HStack(spacing: Spacing.m) {
                micButton
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(voice.isActive ? "Gespräch mit ROOK" : "Mit ROOK sprechen")
                        .font(Typography.title)
                        .foregroundStyle(Palette.ink)
                        .wraps()
                    Text(statusLine)
                        .font(Typography.caption)
                        .foregroundStyle(voice.phase == .speaking ? Palette.bioCyan : Palette.inkMuted)
                        .wraps()
                        .accessibilityIdentifier("rook.voice.status")
                }
                Spacer(minLength: 0)
            }
            if voice.isActive || !voice.turns.isEmpty {
                transcript
            }
            if let problem = voice.problem {
                Text(problem.text)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.pulseCoral)
                    .wraps()
                    .accessibilityIdentifier("rook.voice.problem")
            }
        }
        .padding(Spacing.l)
        .background(
            RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                .fill(Palette.surfaceRaised)
                .overlay(RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                    .strokeBorder(voice.isActive ? Palette.bioCyan.opacity(0.6) : Palette.hairline, lineWidth: 1))
        )
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { voice.stop() }
        }
        .onDisappear { voice.stop() }
    }

    private var micButton: some View {
        Button {
            Task { await voice.toggle() }
        } label: {
            ZStack {
                Circle()
                    .fill(voice.isActive
                          ? AnyShapeStyle(RadialGradient(colors: [Palette.bioCyan, Palette.neuralViolet.opacity(0.7)],
                                                         center: .center, startRadius: 2, endRadius: 40))
                          : AnyShapeStyle(Palette.surfaceButton))
                Circle().strokeBorder(Palette.bioCyan.opacity(0.7), lineWidth: 1.5)
                Image(systemName: voice.isActive ? "stop.fill" : "mic.fill")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(voice.isActive ? Palette.obsidian : Palette.bioCyan)
                    .symbolEffect(.pulse, isActive: voice.phase == .listening && !reduceMotion)
            }
            .frame(width: 72, height: 72)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.start, trigger: voice.isActive) { _, active in active }
        .sensoryFeedback(.stop, trigger: voice.isActive) { _, active in !active }
        .accessibilityLabel(voice.isActive ? "Gespräch beenden" : "Mit ROOK sprechen")
        .accessibilityHint(voice.isActive ? "" : "Danach hört ROOK zu, bis du das Gespräch beendest.")
        .accessibilityValue(statusLine)
        .accessibilityIdentifier("rook.voice")
    }

    private var statusLine: String {
        switch voice.phase {
        case .idle: "Tippen und einfach losreden. Ich antworte laut."
        case .listening: voice.partial.isEmpty ? "Ich höre zu …" : "Ich höre zu"
        case .thinking: "Ich denke nach …"
        case .speaking: "ROOK spricht. Red einfach dazwischen."
        }
    }

    private var transcript: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            ForEach(voice.turns.suffix(4)) { turn in
                line(speaker: turn.speaker == .rook ? "ROOK" : "Du", text: turn.text, rook: turn.speaker == .rook)
            }
            if voice.phase == .listening, !voice.partial.isEmpty {
                line(speaker: "Du", text: voice.partial, rook: false)
                    .opacity(0.75)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("rook.voice.transcript")
    }

    private func line(speaker: String, text: String, rook: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(speaker)
                .font(Typography.motto)
                .tracking(1)
                .foregroundStyle(rook ? Palette.bioCyan : Palette.inkMuted)
            Text(text)
                .font(Typography.body)
                .foregroundStyle(Palette.ink)
                .wraps()
        }
        .accessibilityElement(children: .combine)
    }
}
