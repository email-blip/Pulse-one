import Foundation
import Observation
import PulseCore
import SwiftData

/// What the person confirms before an expert round: the exact fact list, the preview (cost estimate, model,
/// sends left) and, if sending is not possible, why.
struct ConferencePreparation: Identifiable, Sendable {
    let id = UUID()
    let facts: String
    let preview: SendPreview
    let blocker: String?
    let spending: SpendingBudget
}

/// Runs the "Expertenrunde" (BEGLEITER-KREATIVTEAM.md §5) through the Analyse module's Claude client:
/// same key, transport, selected model, send/money budget and cost records. Nothing is sent before the
/// preview is confirmed; every reply passes the local check before it is shown or stored.
@MainActor
@Observable
final class ConferenceRunner {
    /// Progress id of the synthesis step (role ids come from `CompanionPrompts.conferenceRoles`).
    static let synthesisID = "synthesis"
    /// Kind of the `StoredAnalysis` cost record.
    static let analysisKind = "conference"

    let engine: IntelligenceEngine
    private(set) var isRunning = false
    /// Role (or synthesis) currently waiting for Claude.
    private(set) var activeStepID: String?
    private(set) var finishedStepIDs: Set<String> = []
    /// Calm German message of the last failed round, nil otherwise.
    private(set) var errorMessage: String?

    init(engine: IntelligenceEngine = IntelligenceEngine()) {
        self.engine = engine
    }

    var hasKey: Bool { engine.services.hasKey }

    /// Builds the preview for today's companion day; nil without a day (no morning briefing yet).
    func prepare(day: CompanionDay?, modelContext: ModelContext) -> ConferencePreparation? {
        guard let day else { return nil }
        let facts = CompanionPrompts.minimalFacts(day)
        let preview = SendPreview.conference(facts: facts, model: engine.settings.model,
                                             sendBudget: engine.sendBudget(in: modelContext))
        return ConferencePreparation(facts: facts, preview: preview,
                                     blocker: blocker(for: preview, modelContext: modelContext),
                                     spending: engine.spendingBudget(in: modelContext))
    }

    /// Key and budgets as in the Analyse module, plus the consent categories the fact list touches.
    func blocker(for preview: SendPreview, modelContext: ModelContext) -> String? {
        if let reason = engine.blocker(for: preview, modelContext: modelContext) { return reason }
        let missing = CompanionConference.missingConsent(in: engine.settings.consent)
        guard !missing.isEmpty else { return nil }
        let names = missing.map(\.title).joined(separator: ", ")
        return "Die Expertenrunde sendet Werte aus diesen Bereichen, die unter Profil → KI-Anbieter nicht freigegeben sind: \(names)."
    }

    /// Four role rounds one after another, then the synthesis. Usage of every call is summed on one
    /// `StoredAnalysis`, also when a later call fails.
    func run(_ preparation: ConferencePreparation, modelContext: ModelContext) async {
        guard !isRunning else { return }
        // Checked again right before sending (budget may have changed while the preview was open).
        if let reason = blocker(for: preparation.preview, modelContext: modelContext) {
            errorMessage = reason
            return
        }
        isRunning = true
        errorMessage = nil
        finishedStepIDs = []
        defer {
            isRunning = false
            activeStepID = nil
        }

        let model = preparation.preview.model
        let facts = preparation.facts
        let record = StoredAnalysis(kind: Self.analysisKind, title: CompanionPrompts.conferenceTitle, model: model,
                                    contextJSON: "")
        modelContext.insert(record)
        var usage = TokenUsage()
        var responder = model.id
        var statements: [ConferenceStatement] = []
        do {
            for role in CompanionPrompts.conferenceRoles {
                activeStepID = role.id
                let prompt = CompanionPrompts.conferenceRound(role: role, facts: facts)
                let response = try await engine.sendPlainText(system: prompt.system, user: prompt.user, model: model,
                                                              effort: CompanionConference.roleEffort)
                usage = usage + response.usage
                responder = response.model
                let screened = CompanionConference.screen(response.text)
                statements.append(ConferenceStatement(role: role, text: screened.text, withheld: screened.withheld))
                finishedStepIDs.insert(role.id)
            }

            activeStepID = Self.synthesisID
            var contributions: [(ConferenceRole, String)] = []
            for (role, statement) in zip(CompanionPrompts.conferenceRoles, statements) {
                contributions.append((role, statement.withheld ? CompanionConference.withheldForSynthesis : statement.text))
            }
            let prompt = CompanionPrompts.conferenceSynthesis(facts: facts, statements: contributions)
            let response = try await engine.sendPlainText(system: prompt.system, user: prompt.user, model: model,
                                                          effort: CompanionConference.synthesisEffort)
            usage = usage + response.usage
            responder = response.model
            let synthesis = CompanionConference.screen(response.text)
            finishedStepIDs.insert(Self.synthesisID)

            record.apply(usage, responder: responder, model: model)
            modelContext.insert(StoredConference(createdAt: engine.now, factsText: facts, statements: statements,
                                                 synthesis: synthesis.text, synthesisWithheld: synthesis.withheld,
                                                 costUSD: record.costUSD, modelID: responder))
        } catch {
            record.apply(usage, responder: responder, model: model)
            record.fail(error)
            errorMessage = IntelligenceEngine.message(for: error)
        }
        try? modelContext.save()
    }
}
