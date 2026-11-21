import PulseCore
import SwiftData
import SwiftUI

/// The consultation ("Sprechstunde", owner decision 2026-11-21): a conversation with Claude as a team of
/// internist, sports physician and coach. Anamnesis questions, possible diagnoses with probabilities,
/// work-up and a plan. The conversation stays on the iPhone; its summary goes into the next one.
struct ConsultationView: View {
    let engine: IntelligenceEngine
    @State var consultation: StoredConsultation?
    @Environment(\.modelContext) private var modelContext
    @Environment(SourcesStore.self) private var sources
    @Environment(ProfileStore.self) private var profileStore
    @State private var draft = ""
    @State private var pending: PendingSend?
    @State private var blocker: String?
    @State private var turns: [ConsultationTurn] = []
    @Environment(\.reduceMotionEffective) private var reduceMotion

    var body: some View {
        ZStack {
            ScreenBackground()
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: Spacing.l) {
                        if LaunchOptions.current.usesTestScenario { TestBanner() }
                        if turns.isEmpty { introCard }
                        ForEach(turns) { turn in
                            ConsultationTurnView(turn: turn, context: consultation?.context) { question in
                                draft = draft.isEmpty ? "Zu „\(question)“: " : draft + "\nZu „\(question)“: "
                            }
                            .id(turn.id)
                        }
                        if let activity = engine.activity { WorkingCard(text: activity).id("working") }
                        if let blocker {
                            Text(blocker).font(Typography.caption).foregroundStyle(Palette.ink).wraps()
                        }
                        inputCard.id("input")
                    }
                    .padding(Spacing.l)
                }
                .onChange(of: turns.count) { _, _ in
                    guard let last = turns.last?.id else { return }
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) { proxy.scrollTo(last, anchor: .top) }
                }
            }
        }
        .navigationTitle("Sprechstunde")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $pending) { item in
            SendPreviewView(preview: item.preview, blocker: item.blocker, onSend: item.send)
        }
        .onAppear { turns = consultation?.turns ?? [] }
        // Pushed from the Analyse tab, so the scenario never matches: always mark the screen for UI tests.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.consultation")
    }

    private var introCard: some View {
        Card {
            SectionHeader(title: "Sprechstunde mit Claude")
            Text("Claude schaut sich deine Werte der letzten vier Wochen an wie ein Team aus Internist, Sportmediziner und Coach: Einschätzung, mögliche Diagnosen mit Wahrscheinlichkeit, was man abklären sollte, und was du tun kannst.")
                .font(Typography.body).foregroundStyle(Palette.ink).wraps()
            Text("Erzähl gern, wie du dich fühlst und was dich beschäftigt. Claude stellt Rückfragen wie in einer Anamnese. Das Gespräch bleibt auf deinem iPhone; eine Zusammenfassung fließt ins nächste Gespräch ein.")
                .font(Typography.caption).foregroundStyle(Palette.inkMuted).wraps()
        }
    }

    private var inputCard: some View {
        Card {
            if SafetyRules.isEmergency(draft) {
                Label(SafetyRules.consultationEmergencyNotice, systemImage: "exclamationmark.triangle.fill")
                    .font(Typography.label).foregroundStyle(Palette.pulseCoral).wraps()
                    .accessibilityIdentifier("consultation.emergency")
            }
            TextField(turns.isEmpty ? "Wie geht es dir? Zum Beispiel: Seit Tagen müde, Knie links zieht beim Laufen."
                                    : "Deine Antwort an Claude", text: $draft, axis: .vertical)
                .font(Typography.body)
                .foregroundStyle(Palette.ink)
                .lineLimit(2...8)
                .padding(Spacing.m)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Palette.surfaceButton))
                .accessibilityIdentifier("consultation.input")
            Button(turns.isEmpty ? "Sprechstunde beginnen" : "Senden") { send() }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(engine.activity != nil || (!turns.isEmpty && draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
                .accessibilityIdentifier("consultation.send")
            Text(turns.isEmpty ? "Vor dem ersten Senden siehst du genau, welche Werte an Claude gehen."
                               : "Geht an Claude: deine Nachricht und der bisherige Gesprächsverlauf.")
                .font(Typography.caption).foregroundStyle(Palette.inkMuted).wraps()
        }
    }

    private func send() {
        let text = draft
        if let consultation {
            let preview = engine.consultationPreview(context: consultation.context ?? emptyContext, modelContext: modelContext)
            blocker = engine.blocker(for: preview, modelContext: modelContext)
            guard blocker == nil else { return }
            draft = ""
            run(text, in: consultation)
            return
        }
        // First message: the visible preview of everything that leaves the iPhone.
        let context = engine.consultationContext(modelContext: modelContext, owner: sources.ownerProfileID,
                                                 profile: profileStore.profile)
        let preview = engine.consultationPreview(context: context, modelContext: modelContext)
        pending = PendingSend(preview: preview, blocker: engine.blocker(for: preview, modelContext: modelContext)) {
            let created = StoredConsultation(context: context)
            modelContext.insert(created)
            consultation = created
            draft = ""
            run(text, in: created)
        }
    }

    private func run(_ text: String, in consultation: StoredConsultation) {
        Task {
            // Show the person's message at once; the reply follows.
            turns = consultation.turns + [ConsultationTurn(date: engine.now, role: .person,
                                                           text: text.isEmpty ? ConsultationBuilder.startMessage : text,
                                                           emergencyNotice: SafetyRules.isEmergency(text))]
            await engine.consult(text, in: consultation, modelContext: modelContext, owner: sources.ownerProfileID)
            turns = consultation.turns
        }
    }

    private var emptyContext: HealthAnalysisContext {
        QuestionTools.context(facts: [], correlations: [], events: [], consent: engine.settings.consent, now: engine.now)
    }
}

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

/// A possible diagnosis: name, probability bar, what speaks for and against, and how to clarify it.
struct DifferentialRow: View {
    let diagnosis: DifferentialDiagnosis
    let context: HealthAnalysisContext?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            HStack(alignment: .firstTextBaseline) {
                Text(diagnosis.name).font(Typography.label).foregroundStyle(Palette.ink).wraps()
                Spacer(minLength: Spacing.s)
                Text("\(diagnosis.likelihoodPercent) %").font(Typography.label).foregroundStyle(Palette.bioCyan)
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.surfaceButton)
                    Capsule().fill(Palette.bioCyan)
                        .frame(width: geometry.size.width * CGFloat(diagnosis.likelihoodPercent) / 100)
                }
            }
            .frame(height: 6)
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
        .accessibilityLabel("\(diagnosis.name), Wahrscheinlichkeit etwa \(diagnosis.likelihoodPercent) Prozent")
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
