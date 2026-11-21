import PulseCore
import SwiftData
import SwiftUI

/// Entry card for the expert round on the companion screen (label of a NavigationLink).
struct ConferenceEntryLabel: View {
    var body: some View {
        Card {
            HStack(alignment: .firstTextBaseline) {
                CompanionCardTitle(title: CompanionPrompts.conferenceTitle, systemImage: "person.3")
                Spacer(minLength: Spacing.s)
                Image(systemName: "chevron.right")
                    .foregroundStyle(Palette.inkMuted)
                    .accessibilityHidden(true)
            }
            Text("Vier Blickwinkel auf deinen Tag: Herz, Schlaf, Sport und Ernährung. KI-Rollen, keine Ärzte.")
                .font(Typography.caption)
                .foregroundStyle(Palette.inkMuted)
                .wraps()
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

/// The expert round (I11): four AI roles look at the same local facts, then a synthesis. Sent through the
/// Analyse module's Claude client only after the preview was confirmed; the last round is shown on open.
struct ConferenceView: View {
    let store: CompanionStore
    @Environment(\.modelContext) private var modelContext
    @State private var runner = ConferenceRunner()
    @State private var preparation: ConferencePreparation?
    @Query(sort: \StoredConference.createdAt, order: .reverse) private var conferences: [StoredConference]

    var body: some View {
        ZStack {
            ScreenBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.l) {
                    if LaunchOptions.current.usesTestScenario { TestBanner() }
                    Text("Vier Rollen schauen auf dieselben Werte deines Tages, jede aus ihrem Blickwinkel. Danach fasst eine Moderation zusammen und zeigt auch, wo sich die Rollen nicht einig sind.")
                        .font(Typography.body)
                        .foregroundStyle(Palette.ink)
                        .wraps()
                    ConferenceDisclaimerCard(mode: runner.safetyMode)
                    if !runner.hasKey { ConferenceKeyCard() }
                    askSection
                    if runner.isRunning {
                        ConferenceProgressCard(activeStepID: runner.activeStepID, finished: runner.finishedStepIDs)
                    }
                    if let message = runner.errorMessage {
                        FailureCard(message: message)
                            .accessibilityIdentifier("conference.error")
                    }
                    if let last = conferences.first {
                        ConferenceResult(conference: last)
                    } else {
                        SectionHeader(title: "Die Rollen")
                        ForEach(CompanionPrompts.conferenceRoles) { role in
                            ConferenceRoleCard(role: role)
                        }
                    }
                }
                .padding(.horizontal, Spacing.l)
                .padding(.bottom, Spacing.xl)
            }
        }
        .navigationTitle(CompanionPrompts.conferenceTitle)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $preparation) { item in
            ConferencePreviewSheet(preparation: item) {
                Task { await runner.run(item, modelContext: modelContext) }
            }
            .preferredColorScheme(.dark)
        }
        .screenIdentifier(CompanionUI.conferenceScenario)
    }

    private var askSection: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Button {
                preparation = runner.prepare(day: store.today, modelContext: modelContext)
            } label: {
                Label("Expertenrunde fragen", systemImage: "person.3")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(store.today == nil || runner.isRunning)
            .opacity(store.today == nil || runner.isRunning ? 0.5 : 1)
            .accessibilityIdentifier("conference.ask")
            if store.today == nil {
                Text("Erst Morgenbericht erstellen: Die Rollen brauchen die ausgewertete Nacht von heute. Auf dem Begleiter-Screen zum Aktualisieren nach unten ziehen.")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.inkMuted)
                    .wraps()
            } else {
                Text("Vor dem Senden siehst du genau, welche Werte an Claude gehen, und was es ungefähr kostet.")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.inkMuted)
                    .wraps()
            }
        }
    }
}

/// Always visible: who speaks. Clinical mode (default) introduces the specialist roles without disclaimers;
/// descriptive mode keeps the earlier "no doctors, no diagnosis" card.
private struct ConferenceDisclaimerCard: View {
    let mode: SafetyMode

    var body: some View {
        Card {
            Label(mode == .clinical ? "Vier Fachrollen" : "Keine Ärzte, keine Diagnose",
                  systemImage: mode == .clinical ? "stethoscope" : "hand.raised")
                .font(Typography.label)
                .foregroundStyle(Palette.ink)
                .wraps()
            Text(CompanionPrompts.conferenceIntro(mode))
                .font(Typography.caption)
                .foregroundStyle(Palette.ink)
                .wraps()
            Text(mode == .clinical
                 ? "Bei Warnzeichen steht die Dringlichkeit ganz oben. Im Notfall 112."
                 : "Die Rollen sind KI-Stimmen von Claude, keine echten Fachleute. Sie beschreiben Muster in deinen eigenen Werten und machen Vorschläge. Bei Beschwerden lass dich ärztlich beraten, im Notfall 112.")
                .font(Typography.caption)
                .foregroundStyle(Palette.inkMuted)
                .wraps()
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("conference.disclaimer")
    }
}

/// No Anthropic key yet: the key lives in the Analyse settings ("KI-Anbieter"), shared with this round.
private struct ConferenceKeyCard: View {
    var body: some View {
        Card {
            Label("Kein Claude-Schlüssel hinterlegt", systemImage: "key")
                .font(Typography.label)
                .foregroundStyle(Palette.ink)
                .wraps()
            Text("Die Expertenrunde nutzt denselben Schlüssel, dasselbe Modell und dasselbe Monatsbudget wie die Analyse.")
                .font(Typography.caption)
                .foregroundStyle(Palette.inkMuted)
                .wraps()
            NavigationLink {
                IntelligenceSettingsView()
            } label: {
                Label("KI-Anbieter öffnen", systemImage: "gearshape")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(SecondaryButtonStyle())
            .accessibilityIdentifier("conference.keySettings")
        }
    }
}

/// One line per role plus the synthesis while the round runs.
private struct ConferenceProgressCard: View {
    let activeStepID: String?
    let finished: Set<String>

    var body: some View {
        Card {
            SectionHeader(title: "Die Runde läuft")
            ForEach(CompanionPrompts.conferenceRoles) { role in
                row(id: role.id, title: role.title, symbol: role.symbol)
            }
            row(id: ConferenceRunner.synthesisID, title: "Zusammenfassung", symbol: "text.bubble")
        }
        .accessibilityIdentifier("conference.progress")
    }

    private func row(id: String, title: String, symbol: String) -> some View {
        HStack(spacing: Spacing.m) {
            Image(systemName: symbol)
                .foregroundStyle(Palette.neuralViolet)
                .frame(width: 28)
                .accessibilityHidden(true)
            Text(title)
                .font(Typography.label)
                .foregroundStyle(Palette.ink)
                .wraps()
            Spacer(minLength: Spacing.s)
            if finished.contains(id) {
                Image(systemName: "checkmark.circle")
                    .foregroundStyle(Palette.bioCyan)
                    .accessibilityLabel("fertig")
            } else if activeStepID == id {
                ProgressView()
                    .tint(Palette.bioCyan)
                    .accessibilityLabel("Claude schreibt")
            } else {
                Image(systemName: "circle")
                    .foregroundStyle(Palette.inkMuted)
                    .accessibilityLabel("wartet")
            }
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
    }
}

/// The stored round: one card per role, then the synthesis with its own disagreement block.
private struct ConferenceResult: View {
    let conference: StoredConference

    var body: some View {
        SectionHeader(title: "Letzte Runde")
        Text(footer)
            .font(Typography.caption)
            .foregroundStyle(Palette.inkMuted)
            .wraps()
        ForEach(conference.statements) { statement in
            ConferenceStatementCard(statement: statement)
        }
        ConferenceSynthesisCard(synthesis: conference.synthesis, withheld: conference.synthesisWithheld)
        Card {
            SectionHeader(title: "Gesendete Fakten")
            Text(conference.factsText)
                .font(Typography.caption)
                .foregroundStyle(Palette.inkMuted)
                .textSelection(.enabled)
                .wraps()
        }
    }

    private var footer: String {
        var parts = [conference.createdAt.formatted(date: .abbreviated, time: .shortened)]
        if !conference.modelID.isEmpty { parts.append(ClaudeModel.model(id: conference.modelID).displayName) }
        if let cost = conference.costUSD { parts.append(IntelligenceEngine.dollars(cost)) }
        return parts.joined(separator: " · ")
    }
}

private struct ConferenceStatementCard: View {
    let statement: ConferenceStatement

    var body: some View {
        Card {
            Label(statement.title, systemImage: statement.symbol)
                .font(Typography.label)
                .foregroundStyle(Palette.neuralViolet)
                .wraps()
                .accessibilityAddTraits(.isHeader)
            if statement.withheld {
                Label(statement.text, systemImage: "hand.raised")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.inkMuted)
                    .wraps()
            } else {
                StatementBadge(kind: .interpretation)
                Text(statement.text)
                    .font(Typography.body)
                    .foregroundStyle(Palette.ink)
                    .wraps()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("conference.role.\(statement.roleID)")
    }
}

private struct ConferenceSynthesisCard: View {
    let synthesis: String
    let withheld: Bool

    var body: some View {
        Card {
            Label("Zusammenfassung", systemImage: "text.bubble")
                .font(Typography.label)
                .foregroundStyle(Palette.bioCyan)
                .wraps()
                .accessibilityAddTraits(.isHeader)
            if withheld {
                Label(synthesis, systemImage: "hand.raised")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.inkMuted)
                    .wraps()
            } else {
                StatementBadge(kind: .interpretation)
                ForEach(CompanionConference.sections(of: synthesis)) { section in
                    ConferenceSectionView(section: section)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("conference.synthesis")
    }
}

private struct ConferenceSectionView: View {
    let section: ConferenceSection

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            if !section.title.isEmpty {
                Text(section.title)
                    .font(Typography.label)
                    .foregroundStyle(section.isDisagreement ? Palette.neuralViolet : Palette.ink)
                    .wraps()
                    .accessibilityAddTraits(.isHeader)
            }
            if !section.body.isEmpty {
                Text(section.body)
                    .font(Typography.body)
                    .foregroundStyle(Palette.ink)
                    .wraps()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(section.isDisagreement ? Spacing.m : 0)
        .background {
            if section.isDisagreement {
                RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                    .stroke(Palette.neuralViolet.opacity(0.6), lineWidth: 1)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(section.isDisagreement ? "conference.disagreement" : "conference.section")
    }
}

/// "Das wird gesendet": exact fact list, five requests, estimate and monthly budget; sends only on "Senden".
private struct ConferencePreviewSheet: View {
    let preparation: ConferencePreparation
    let onSend: @MainActor () -> Void
    @Environment(\.dismiss) private var dismiss

    private var preview: SendPreview { preparation.preview }

    var body: some View {
        NavigationStack {
            ZStack {
                ScreenBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.l) {
                        Card {
                            Text("Das wird gesendet").font(Typography.title).foregroundStyle(Palette.ink).wraps()
                            Text("\(CompanionConference.requestCount) Anfragen an \(preview.model.displayName): vier Rollen und eine Zusammenfassung. Jede Anfrage enthält diese Fakten:")
                                .font(Typography.caption).foregroundStyle(Palette.inkMuted).wraps()
                            Text(preparation.facts)
                                .font(Typography.caption)
                                .foregroundStyle(Palette.ink)
                                .textSelection(.enabled)
                                .wraps()
                                .accessibilityIdentifier("conference.facts")
                        }
                        Card {
                            SectionHeader(title: "Bleibt auf dem iPhone")
                            ForEach(SendPreview.neverSent, id: \.self) { item in
                                Label(item, systemImage: "lock")
                                    .font(Typography.caption).foregroundStyle(Palette.inkMuted).wraps()
                            }
                        }
                        Card {
                            SectionHeader(title: "Kosten")
                            Text("Geschätzt \(preview.estimate.text) für alle \(CompanionConference.requestCount) Anfragen, abgerechnet über dein Anthropic-Konto.")
                                .font(Typography.caption).foregroundStyle(Palette.ink).wraps()
                            Text(budgetLine)
                                .font(Typography.caption).foregroundStyle(Palette.inkMuted).wraps()
                            if preparation.spending.status == .warning {
                                Text(verbatim: "Mehr als 80 % des Monatsbudgets sind verbraucht.")
                                    .font(Typography.caption).foregroundStyle(Palette.ink).wraps()
                            }
                        }
                        if let blocker = preparation.blocker {
                            Card {
                                Label(blocker, systemImage: "hand.raised")
                                    .font(Typography.caption).foregroundStyle(Palette.ink).wraps()
                                NavigationLink {
                                    IntelligenceSettingsView()
                                } label: {
                                    Label("KI-Anbieter öffnen", systemImage: "gearshape")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(SecondaryButtonStyle())
                            }
                        }
                        Button("Senden") {
                            dismiss()
                            onSend()
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(preparation.blocker != nil)
                        .opacity(preparation.blocker == nil ? 1 : 0.5)
                        .accessibilityIdentifier("conference.send")
                    }
                    .padding(Spacing.l)
                }
            }
            .navigationTitle("Vor dem Senden")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } } }
        }
    }

    private var budgetLine: String {
        let spending = preparation.spending
        return "Diesen Monat: \(IntelligenceEngine.dollars(spending.spentUSD)) von \(IntelligenceEngine.dollars(spending.limitUSD)) verbraucht, noch \(preview.sendsRemaining) Sendungen frei. Die Runde zählt als eine Sendung."
    }
}

struct ConferenceRoleCard: View {
    let role: ConferenceRole

    var body: some View {
        Card {
            Label(role.title, systemImage: role.symbol)
                .font(Typography.label)
                .foregroundStyle(Palette.neuralViolet)
                .wraps()
            Text(role.focus)
                .font(Typography.caption)
                .foregroundStyle(Palette.ink)
                .wraps()
        }
        .accessibilityElement(children: .combine)
    }
}
