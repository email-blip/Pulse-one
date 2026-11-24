import PulseCore
import SwiftData
import SwiftUI

// The consultation screen ("Sprechstunde") left the app with the rebuild (Auftrag 04): ROOK is the one coach.
// The turn views stay so stored consultations still open from the analysis history.

/// One turn: the person's message, or Claude's checked answer in sections.
struct ConsultationTurnView: View {
    let turn: ConsultationTurn
    let context: HealthAnalysisContext?
    let onQuestion: (String) -> Void

    var body: some View {
        switch turn.role {
        case .person: personBubble
        case .claude: claudeAnswer
        }
    }

    private var personBubble: some View {
        VStack(alignment: .trailing, spacing: Spacing.s) {
            if turn.emergencyNotice {
                Label(SafetyRules.consultationEmergencyNotice, systemImage: "exclamationmark.triangle.fill")
                    .font(Typography.label).foregroundStyle(Palette.pulseCoral).wraps()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Text(turn.text)
                .font(Typography.body).foregroundStyle(Palette.ink).wraps()
                .padding(Spacing.m)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Palette.surfaceButton))
                .accessibilityLabel("Du: \(turn.text)")
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.leading, Spacing.xl)
    }

    @ViewBuilder
    private var claudeAnswer: some View {
        if !turn.errorMessage.isEmpty {
            FailureCard(message: turn.errorMessage)
        } else if let reply = turn.reply {
            VStack(spacing: Spacing.l) {
                if reply.urgency != ConsultationUrgency.none { urgencyCard(reply) }
                Card {
                    Label("Claude", systemImage: "stethoscope")
                        .font(Typography.label).foregroundStyle(Palette.bioCyan)
                    Text(reply.reply).font(Typography.body).foregroundStyle(Palette.ink).wraps()
                        .accessibilityIdentifier("consultation.reply")
                }
                if !reply.assessment.isEmpty {
                    Card {
                        SectionHeader(title: "Befund und Einschätzung")
                        ForEach(Array(reply.assessment.enumerated()), id: \.offset) { _, statement in
                            StatementRow(text: statement.text, kind: statement.type.badgeKind,
                                         evidence: EvidenceItem.resolve(statement.evidence, in: context),
                                         flag: turn.flagged[statement.text])
                        }
                    }
                }
                if !reply.differentials.isEmpty {
                    Card {
                        SectionHeader(title: "Mögliche Diagnosen")
                        ForEach(Array(reply.differentials.enumerated()), id: \.offset) { _, diagnosis in
                            DifferentialRow(diagnosis: diagnosis, context: context)
                        }
                    }
                    .accessibilityIdentifier("consultation.differentials")
                }
                if !reply.recommendations.isEmpty { recommendations(reply) }
                if !reply.anamnesisQuestions.isEmpty {
                    Card {
                        SectionHeader(title: "Claude fragt nach")
                        ForEach(reply.anamnesisQuestions, id: \.self) { question in
                            Button { onQuestion(question) } label: {
                                Label(question, systemImage: "arrowshape.turn.up.left")
                                    .font(Typography.body).foregroundStyle(Palette.ink).wraps()
                                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("Übernimmt die Frage in dein Antwortfeld")
                        }
                    }
                }
                if !turn.toolLog.isEmpty {
                    Text("Claude hat abgefragt: " + turn.toolLog.joined(separator: ", "))
                        .font(Typography.caption).foregroundStyle(Palette.inkMuted).wraps()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func urgencyCard(_ reply: ConsultationReply) -> some View {
        Card {
            Label(reply.urgency.title, systemImage: reply.urgency >= .today ? "exclamationmark.triangle.fill" : "stethoscope")
                .font(Typography.label)
                .foregroundStyle(reply.urgency >= .soon ? Palette.pulseCoral : Palette.ink)
                .wraps()
            if !reply.urgencyReason.isEmpty {
                Text(reply.urgencyReason).font(Typography.body).foregroundStyle(Palette.ink).wraps()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("consultation.urgency")
    }

    private func recommendations(_ reply: ConsultationReply) -> some View {
        Card {
            SectionHeader(title: "Was du tun kannst")
            ForEach(Array(reply.recommendations.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .top, spacing: Spacing.m) {
                    Image(systemName: item.area.symbol).foregroundStyle(Palette.bioCyan).frame(width: 28)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(item.area.title) · \(item.priority.title)")
                            .font(Typography.caption).foregroundStyle(Palette.inkMuted).wraps()
                        Text(item.text).font(Typography.body).foregroundStyle(Palette.ink).wraps()
                        if let flag = turn.flagged[item.text] {
                            Label(flag, systemImage: "info.circle")
                                .font(Typography.caption).foregroundStyle(Palette.inkMuted).wraps()
                        }
                    }
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

/// A possible diagnosis: name, how well it fits (three steps, no percentages), what speaks for and against, and how to clarify it.
struct DifferentialRow: View {
    let diagnosis: DifferentialDiagnosis
    let context: HealthAnalysisContext?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            HStack(alignment: .firstTextBaseline) {
                Text(diagnosis.name).font(Typography.label).foregroundStyle(Palette.ink).wraps()
                Spacer(minLength: Spacing.s)
                Text(diagnosis.fit.title).font(Typography.label).foregroundStyle(Palette.bioCyan)
            }
            HStack(spacing: Spacing.xs) {
                ForEach(0..<3, id: \.self) { step in
                    Capsule().fill(step < filledSteps ? Palette.bioCyan : Palette.surfaceButton).frame(height: 6)
                }
            }
            .accessibilityHidden(true)
            if !diagnosis.reasoning.isEmpty {
                Text(diagnosis.reasoning).font(Typography.body).foregroundStyle(Palette.ink).wraps()
            }
            list("Dafür", diagnosis.supporting, symbol: "plus.circle")
            list("Dagegen", diagnosis.against, symbol: "minus.circle")
            list("Abklären", diagnosis.workup, symbol: "stethoscope")
            let evidence = EvidenceItem.resolve(diagnosis.evidence, in: context)
            if !evidence.isEmpty {
                StatementRow(text: "Gestützt auf deine Werte", kind: .computed, evidence: evidence)
            }
        }
        .padding(.vertical, Spacing.s)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(diagnosis.name), \(diagnosis.fit.title)")
    }

    private var filledSteps: Int {
        switch diagnosis.fit {
        case .strong: 3
        case .partial: 2
        case .weak: 1
        case .open: 0
        }
    }

    @ViewBuilder
    private func list(_ title: String, _ items: [String], symbol: String) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Typography.caption.weight(.semibold)).foregroundStyle(Palette.inkMuted)
                ForEach(items, id: \.self) { item in
                    Label(item, systemImage: symbol).font(Typography.caption).foregroundStyle(Palette.ink).wraps()
                }
            }
        }
    }
}
