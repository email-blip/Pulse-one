import PulseCore
import SwiftUI

/// A checked report: every sentence with its type, evidence and notes; then the check log and the cost.
struct ReportView: View {
    let analysis: StoredAnalysis

    var body: some View {
        ZStack {
            ScreenBackground()
            ScrollView {
                VStack(spacing: Spacing.l) {
                    if LaunchOptions.current.usesTestScenario { TestBanner() }
                    if analysis.failed {
                        FailureCard(message: analysis.errorMessage)
                    } else if let report = analysis.decodeResult(AnalysisReport.self) {
                        ReportBody(report: report, context: analysis.context, flagged: analysis.flagged)
                    } else if let answer = analysis.decodeResult(QuestionAnswer.self) {
                        AnswerBody(answer: answer, context: analysis.context, flagged: analysis.flagged)
                    } else if let reply = analysis.decodeResult(ConsultationReply.self) {
                        ConsultationTurnView(turn: ConsultationTurn(date: analysis.createdAt, role: .claude, text: reply.reply,
                                                                    reply: reply, flagged: analysis.flagged),
                                             context: analysis.context) { _ in }
                    } else if let board = analysis.decodeResult(HypothesisBoard.self) {
                        HypothesisBody(board: board, context: analysis.context)
                    }
                    if !analysis.toolLog.isEmpty {
                        Card {
                            SectionHeader(title: "Claude hat abgefragt")
                            ForEach(analysis.toolLog.split(separator: "\n").map(String.init), id: \.self) { line in
                                Label(line, systemImage: "magnifyingglass")
                                    .font(Typography.caption).foregroundStyle(Palette.inkMuted).wraps()
                            }
                        }
                    }
                    CheckLogView(issues: analysis.issues)
                    RunFooter(analysis: analysis)
                }
                .padding(Spacing.l)
            }
        }
        .navigationTitle(analysis.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct ReportBody: View {
    let report: AnalysisReport
    let context: HealthAnalysisContext?
    let flagged: [String: String]

    var body: some View {
        VStack(spacing: Spacing.l) {
            if report.medicalReferral.level != ReferralLevel.none {
                Card {
                    StatementBadge(kind: .medicalCheck)
                    Text(report.medicalReferral.reason).font(Typography.body).foregroundStyle(Palette.ink).wraps()
                }
            }
            statements("Kurz gesagt", report.summary)
            statements("Datenlage", report.dataSituation)
            ForEach(Array(report.sections.enumerated()), id: \.offset) { _, section in
                statements(section.title, section.statements)
            }
            if !report.actions.isEmpty {
                Card {
                    SectionHeader(title: "Für die nächsten Tage")
                    ForEach(Array(report.actions.enumerated()), id: \.offset) { _, action in
                        StatementRow(text: action.text, kind: action.domain == .doctor ? .medicalCheck : .suggestion,
                                     evidence: EvidenceItem.resolve(action.evidence, in: context))
                    }
                }
            }
            statements("Unsicherheiten", report.uncertainties)
            if !report.openQuestions.isEmpty {
                Card {
                    SectionHeader(title: "Offene Fragen")
                    ForEach(report.openQuestions, id: \.self) { question in
                        Label(question, systemImage: "questionmark.circle")
                            .font(Typography.caption).foregroundStyle(Palette.ink).wraps()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func statements(_ title: String, _ list: [ReportStatement]) -> some View {
        if !list.isEmpty {
            Card {
                SectionHeader(title: title)
                ForEach(Array(list.enumerated()), id: \.offset) { _, statement in
                    StatementRow(text: statement.text, kind: statement.type.badgeKind,
                                 evidence: EvidenceItem.resolve(statement.evidence, in: context),
                                 flag: flagged[statement.text])
                }
            }
        }
    }
}

struct AnswerBody: View {
    let answer: QuestionAnswer
    let context: HealthAnalysisContext?
    let flagged: [String: String]

    var body: some View {
        VStack(spacing: Spacing.l) {
            Card {
                SectionHeader(title: "Antwort")
                if answer.statements.isEmpty {
                    Text("Claude konnte keine geprüfte Aussage machen.").font(Typography.caption).foregroundStyle(Palette.inkMuted)
                }
                ForEach(Array(answer.statements.enumerated()), id: \.offset) { _, statement in
                    StatementRow(text: statement.text, kind: statement.type.badgeKind,
                                 evidence: EvidenceItem.resolve(statement.evidence, in: context),
                                 flag: flagged[statement.text])
                }
            }
            if !answer.followUps.isEmpty {
                Card {
                    SectionHeader(title: "Weiterfragen")
                    ForEach(answer.followUps, id: \.self) { followUp in
                        Label(followUp, systemImage: "arrow.turn.down.right")
                            .font(Typography.caption).foregroundStyle(Palette.ink).wraps()
                    }
                }
            }
        }
    }
}

struct HypothesisBody: View {
    let board: HypothesisBoard
    let context: HealthAnalysisContext?

    var body: some View {
        VStack(spacing: Spacing.l) {
            ForEach(Array(board.circumstances.enumerated()), id: \.offset) { _, hypothesis in
                Card {
                    StatementRow(text: hypothesis.text, kind: .interpretation,
                                 evidence: EvidenceItem.resolve(hypothesis.evidence, in: context))
                    Text(hypothesis.fit.title).font(Typography.caption.weight(.semibold)).foregroundStyle(Palette.inkMuted)
                    Label(hypothesis.counterCheck, systemImage: "checkmark.circle")
                        .font(Typography.caption).foregroundStyle(Palette.ink).wraps()
                }
            }
            if !board.note.isEmpty {
                Text(board.note).font(Typography.caption).foregroundStyle(Palette.inkMuted).wraps()
            }
        }
    }
}

/// Model, time and real cost of a run (spec §2 "Analysehistorie").
struct RunFooter: View {
    let analysis: StoredAnalysis

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(analysis.createdAt.formatted(date: .abbreviated, time: .shortened))
            if analysis.modelID == IntelligenceEngine.localModelID {
                Text("Auf dem iPhone beantwortet, nichts gesendet.")
            } else {
                let model = analysis.respondingModel.isEmpty ? analysis.modelID : analysis.respondingModel
                Text("\(ClaudeModel.model(id: model).displayName) · \(analysis.inputTokens + analysis.cacheReadTokens + analysis.cacheWriteTokens) Tokens hin, \(analysis.outputTokens) zurück · \(IntelligenceEngine.dollars(analysis.costUSD))")
            }
        }
        .font(Typography.caption)
        .foregroundStyle(Palette.inkMuted)
        .frame(maxWidth: .infinity, alignment: .leading)
        .wraps()
    }
}
