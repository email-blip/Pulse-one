import PulseCore
import SwiftData
import SwiftUI

/// Top of the Coach tab: ROOK's statement and the one conversation with him (no second character). Quick
/// corrections stay local; typed questions go to Claude under the check-ins' standing permission.
/// Identifiers: `rook.conversation`, `rook.turn.<n>`, `rook.input`, `rook.send`.
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
                        Label("ROOK denkt nach …", systemImage: "ellipsis")
                            .font(Typography.caption).foregroundStyle(Palette.inkMuted)
                    }
                }
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
                Text("Korrekturen wirken sofort auf dem iPhone. Fragen gehen mit deinen Tageskennzahlen an Claude, wie die automatischen Checks.")
                    .font(Typography.caption).foregroundStyle(Palette.inkMuted).wraps()
            }
        }
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
