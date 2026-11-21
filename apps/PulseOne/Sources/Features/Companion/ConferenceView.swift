import PulseCore
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
            Text("Vier Blickwinkel auf deine Woche: Herz, Schlaf, Sport und Ernährung. KI-Rollen, keine Ärzte.")
                .font(Typography.caption)
                .foregroundStyle(Palette.inkMuted)
                .wraps()
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

/// The expert round (I11): four AI roles look at the same local facts, then a synthesis.
/// The Claude client is not part of this build yet, so the start button is disabled and says why.
struct ConferenceView: View {
    private let roles = CompanionPrompts.conferenceRoles

    var body: some View {
        ZStack {
            ScreenBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.l) {
                    if LaunchOptions.current.usesTestScenario { TestBanner() }
                    Text("Vier Rollen schauen auf dieselben Werte deiner letzten Tage, jede aus ihrem Blickwinkel. Danach fasst eine Moderation zusammen und zeigt auch, wo sich die Rollen nicht einig sind.")
                        .font(Typography.body)
                        .foregroundStyle(Palette.ink)
                        .wraps()
                    StatementBadge(kind: .interpretation)
                    ForEach(roles) { role in
                        ConferenceRoleCard(role: role)
                    }
                    disclaimer
                    startButton
                }
                .padding(.horizontal, Spacing.l)
                .padding(.bottom, Spacing.xl)
            }
        }
        .navigationTitle(CompanionPrompts.conferenceTitle)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var disclaimer: some View {
        Card {
            Label("Keine Ärzte, keine Diagnose", systemImage: "hand.raised")
                .font(Typography.label)
                .foregroundStyle(Palette.ink)
                .wraps()
            Text(CompanionPrompts.conferenceDisclaimer)
                .font(Typography.caption)
                .foregroundStyle(Palette.ink)
                .wraps()
            Text("Die Rollen sind KI-Stimmen von Claude, keine echten Fachleute. Sie beschreiben Muster in deinen eigenen Werten und machen Vorschläge. Bei Beschwerden lass dich ärztlich beraten, im Notfall 112.")
                .font(Typography.caption)
                .foregroundStyle(Palette.inkMuted)
                .wraps()
            Text("Bevor etwas gesendet wird, siehst du genau, welche Werte an Claude gehen, und gibst sie frei. Namen, Orte und Gerätenummern werden nie gesendet.")
                .font(Typography.caption)
                .foregroundStyle(Palette.inkMuted)
                .wraps()
        }
        .accessibilityElement(children: .combine)
    }

    private var startButton: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Button {} label: {
                Label("Expertenrunde fragen (bald)", systemImage: "lock")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(true)
            .accessibilityHint("Noch nicht verfügbar")
            .accessibilityIdentifier("companion.conference.start")
            Text("Kommt mit der Claude-Anbindung. Bis dahin läuft der Begleiter komplett lokal auf diesem iPhone.")
                .font(Typography.caption)
                .foregroundStyle(Palette.inkMuted)
                .wraps()
        }
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
