import PulseCore
import SwiftData
import SwiftUI

/// Top of the Coach tab: ROOK's statement and the one free conversation with him (no second character). Quick
/// corrections stay local; what the person types or says goes to Claude under the check-ins' standing permission.
/// Identifiers: `rook.conversation`, `rook.turn.<n>`, `rook.streaming`, `rook.input`, `rook.send`.
struct RookConversationSection: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(SourcesStore.self) private var sources
    @Environment(ProfileStore.self) private var profile
    @State private var store = RookStore.shared
    @State private var draft = ""
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            RookCard(onAsk: { inputFocused = true })
            if !visibleTurns.isEmpty {
                Card {
                    SectionHeader(title: "Gespräch")
                    ForEach(Array(visibleTurns.enumerated()), id: \.element.id) { index, turn in
                        bubble(turn).accessibilityIdentifier("rook.turn.\(index)")
                    }
                    if store.isThinking {
                        if store.streamingText.isEmpty {
                            Label("ROOK denkt nach …", systemImage: "ellipsis")
                                .font(Typography.caption).foregroundStyle(Palette.inkMuted)
                        } else {
                            bubble(RookTurn(at: store.now, role: .rook, text: store.streamingText))
                                .accessibilityIdentifier("rook.streaming")
                        }
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("rook.conversation")
            }
            Card {
                TextField("Frag ROOK oder sag ihm, was nicht passt", text: $draft, axis: .vertical)
                    .font(Typography.body)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1...4)
                    .focused($inputFocused)
                    .padding(Spacing.m)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Palette.surfaceButton))
                    .accessibilityIdentifier("rook.input")
                Button("Senden") { send() }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.isThinking)
                    .accessibilityIdentifier("rook.send")
                // 05's voice channel: microphone button and live transcript; answers come from
                // RookStore.shared.talk(_:onSentence:) and share this conversation's memory.
                RookVoicePanel()
                Text("Red mit ROOK wie mit einem Menschen. Korrekturen wirken sofort auf dem iPhone, Antworten kommen mit deinen Tageskennzahlen von Claude, wie die automatischen Checks.")
                    .font(Typography.caption).foregroundStyle(Palette.inkMuted).wraps()
            }
        }
        .task { store.configure(modelContext: modelContext, owner: sources.ownerProfileID, profile: profile.profile) }
        // The two demonstration cases mark this section as their screen.
        .screenIdentifier(RookDemo.Case.positive.rawValue)
        .screenIdentifier(RookDemo.Case.clarify.rawValue)
    }

    /// The last turns; the full history stays in ROOK's memory.
    private var visibleTurns: [RookTurn] { Array(store.turns.suffix(12)) }

    private func bubble(_ turn: RookTurn) -> some View {
        let isPerson = turn.role == .person
        return HStack {
            if isPerson { Spacer(minLength: Spacing.xl) }
            Text(turn.text)
                .font(Typography.body)
                .foregroundStyle(isPerson ? Palette.obsidian : Palette.ink)
                .padding(Spacing.m)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isPerson ? Palette.bioCyan : Palette.surfaceButton))
                .wraps()
            if !isPerson { Spacer(minLength: Spacing.xl) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel((isPerson ? "Du: " : "ROOK: ") + turn.text)
    }

    private func send() {
        let text = draft
        draft = ""
        Task { await store.send(text, modelContext: modelContext, owner: sources.ownerProfileID, profile: profile.profile) }
    }
}
