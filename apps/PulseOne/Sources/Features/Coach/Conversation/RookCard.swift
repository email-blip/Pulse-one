import PulseCore
import SwiftData
import SwiftUI

/// Performs ROOK's primary action (start a unit, rest, open the timeline). Set by the screen that owns training
/// (05) or navigation (03) with `.environment(\.rookActionHandler, …)`.
struct RookActionHandler: Sendable {
    let perform: @MainActor @Sendable (CoachAction) -> Void
}

/// Opens the Verlauf at a window (03 sets it); evidence under "Warum?" jumps there.
struct RookTimelineHandler: Sendable {
    let open: @MainActor @Sendable (TimelineState) -> Void
}

extension EnvironmentValues {
    @Entry var rookActionHandler: RookActionHandler? = nil
    @Entry var openTimeline: RookTimelineHandler? = nil
}

/// ROOK's statement: orb, headline and two to three sentences, one primary action, "Warum?" and the quick
/// corrections. Used on the dashboard (03) and at the top of the Coach tab. Identifiers for the M1 walkthrough
/// (PRUEFLISTE): `orb`, `rook.insight`, `rook.action`, `rook.why`, `rook.correct`, `correction.<id>`.
struct RookCard: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(SourcesStore.self) private var sources
    @Environment(ProfileStore.self) private var profile
    @Environment(\.rookActionHandler) private var actionHandler
    @State private var store = RookStore.shared
    @State private var showCorrections = false
    @State private var why: RookStatement?
    /// Called for "Wie geht's dir?"-type actions; the Coach tab focuses its input field.
    var onAsk: (() -> Void)?

    var body: some View {
        Card {
            HStack(spacing: Spacing.m) {
                // 02's orb; the plain "orb" identifier stays for 06's M1 walkthrough.
                RookOrb(presence: store.isThinking ? .thinking : (store.current?.insight.direction.presence ?? .idle), size: 44)
                    .accessibilityIdentifier("orb")
                Text(RookLocal.name).font(Typography.label.weight(.semibold)).foregroundStyle(Palette.ink)
                Spacer()
                if let statement = store.current, statement.source == .demo {
                    Text("Testansicht").font(Typography.caption).foregroundStyle(Palette.inkMuted)
                }
            }
            if let statement = store.current {
                content(statement)
            } else {
                // Full ink, not muted: the audit flags muted body text on the card surface.
                Text("Hallo, schön, dass du da bist. Wie fühlst du dich heute? Erzähl es mir, dann planen wir den Tag zusammen.")
                    .font(Typography.body).foregroundStyle(Palette.ink).wraps()
            }
        }
        .task {
            store.load(modelContext: modelContext, owner: sources.ownerProfileID)
            store.configure(modelContext: modelContext, owner: sources.ownerProfileID, profile: profile.profile)
        }
        .sheet(item: $why) { statement in
            RookWhyView(statement: statement) { why = nil }
                .preferredColorScheme(.dark)
        }
    }

    @ViewBuilder
    private func content(_ statement: RookStatement) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text(statement.headline)
                .font(Typography.title)
                .foregroundStyle(Palette.ink)
                .wraps()
            Text(statement.insight.interpretation)
                .font(Typography.body)
                .foregroundStyle(Palette.ink)
                .wraps()
        }
        .contentTransition(.opacity)
        .animation(.easeOut(duration: 0.25), value: statement.insight.interpretation)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(statement.headline + ". " + statement.insight.interpretation)
        .accessibilityIdentifier("rook.insight")

        if let action = statement.insight.action {
            Button(action.title) { perform(action, statement: statement) }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("rook.action")
        }
        HStack(spacing: Spacing.m) {
            Button("Warum?") { why = statement }
                .buttonStyle(SecondaryButtonStyle())
                .accessibilityIdentifier("rook.why")
            Button(showCorrections ? "Fertig" : "Passt nicht?") { showCorrections.toggle() }
                .buttonStyle(SecondaryButtonStyle())
                .accessibilityIdentifier("rook.correct")
        }
        if showCorrections {
            VStack(alignment: .leading, spacing: Spacing.s) {
                ForEach(RookFeedback.allCases) { feedback in
                    Button(feedback.title) {
                        if feedback == .why {
                            why = statement
                        } else {
                            store.apply(feedback)
                        }
                        showCorrections = false
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .accessibilityIdentifier("correction.\(feedback.rawValue)")
                }
            }
            // `.contain` first: an identifier on a plain container would overwrite the buttons' own identifiers.
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("rook.corrections")
        }
    }

    private func perform(_ action: CoachAction, statement: RookStatement) {
        switch action.kind {
        case .seeDoctor, .openTimeline:
            if let actionHandler, action.kind == .openTimeline {
                actionHandler.perform(action)
            } else {
                why = statement
            }
        case .askUser:
            if let onAsk { onAsk() } else { showCorrections = true }
        default:
            actionHandler?.perform(action)
        }
    }
}
