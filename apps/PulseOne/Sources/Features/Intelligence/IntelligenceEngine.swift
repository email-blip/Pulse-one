import Foundation
import Observation
import PulseCore
import SwiftData

/// Runs the analysis pipeline (spec §3): local context → visible preview → Claude → local check → history.
/// Nothing leaves the iPhone without the preview being confirmed, and nothing unchecked reaches the screen.
@MainActor
@Observable
final class IntelligenceEngine {
    let services: IntelligenceServices
    /// What is running right now, for the progress line ("Claude schreibt den Wochenbericht …").
    private(set) var activity: String?

    /// History reaches back far enough for a monthly report, its 28-day band and 90-day correlations.
    nonisolated static let historyDays = 125

    init(services: IntelligenceServices = .shared) {
        self.services = services
    }

    var settings: IntelligenceSettings { services.settings }
    var now: Date { services.now }

    // MARK: Inputs

    func samples(in modelContext: ModelContext, owner: UUID, days: Int = historyDays) -> [HealthSample] {
        let since = Calendar.current.date(byAdding: .day, value: -days, to: now) ?? now
        let kinds = Set(ConsentCategory.allCases.flatMap(\.kinds))
        return SampleReader(context: modelContext).samples(kinds, since: since, profileID: owner)
    }

    func events(in modelContext: ModelContext, days: Int = historyDays) -> [ContextEvent] {
        let since = Calendar.current.date(byAdding: .day, value: -days, to: now) ?? now
        let descriptor = FetchDescriptor<StoredNote>(predicate: #Predicate { $0.date >= since }, sortBy: [SortDescriptor(\.date)])
        let notes = (try? modelContext.fetch(descriptor)) ?? []
        return notes.map(\.event)
    }

    func profileSummary(_ profile: UserProfile) -> ProfileSummary {
        let sex: String? = profile.sex.flatMap { $0 == .undisclosed ? nil : $0.rawValue }
        return ProfileSummary(ageRange: ProfileSummary.ageRange(birthYear: profile.birthYear, now: now, calendar: .current),
                              sex: sex, goals: [])
    }

    func reportContext(_ kind: AnalysisPeriodKind, modelContext: ModelContext, owner: UUID,
                       profile: UserProfile) -> HealthAnalysisContext {
        ContextBuilder().build(samples: samples(in: modelContext, owner: owner), events: events(in: modelContext),
                               kind: kind, now: now, consent: settings.consent, profile: profileSummary(profile))
    }

    // MARK: Budget

    struct MonthUsage {
        let spentUSD: Double
        let sends: Int
    }

    func monthUsage(in modelContext: ModelContext) -> MonthUsage {
        let calendar = Calendar.current
        let start = calendar.dateInterval(of: .month, for: now)?.start ?? now
        let local = Self.localModelID
        let descriptor = FetchDescriptor<StoredAnalysis>(predicate: #Predicate { $0.createdAt >= start && $0.modelID != local })
        let runs = (try? modelContext.fetch(descriptor)) ?? []
        let spent = runs.reduce(0) { $0 + $1.costUSD }
        return MonthUsage(spentUSD: spent, sends: runs.count)
    }

    func sendBudget(in modelContext: ModelContext) -> SendBudget {
        SendBudget(maxSends: settings.maxSendsPerMonth, used: monthUsage(in: modelContext).sends)
    }

    func spendingBudget(in modelContext: ModelContext) -> SpendingBudget {
        SpendingBudget(limitUSD: settings.monthlyBudgetUSD, spentUSD: monthUsage(in: modelContext).spentUSD)
    }

    func preview(title: String, context: HealthAnalysisContext, system: String, expectedOutputTokens: Int,
                 modelContext: ModelContext) -> SendPreview {
        SendPreview.make(title: title, context: context, consent: settings.consent, model: settings.model,
                         systemPrompt: system, expectedOutputTokens: expectedOutputTokens,
                         sendBudget: sendBudget(in: modelContext))
    }

    /// Reason a send is blocked, or nil. Checked again right before every call.
    func blocker(for preview: SendPreview, modelContext: ModelContext) -> String? {
        if !services.hasKey {
            return "Es ist noch kein Claude-Schlüssel hinterlegt. Du kannst ihn unter Profil → KI-Anbieter eingeben."
        }
        if !sendBudget(in: modelContext).allowsSend {
            return "Das Monatskontingent von \(settings.maxSendsPerMonth) Sendungen ist aufgebraucht. Du kannst es unter KI-Anbieter ändern."
        }
        if !spendingBudget(in: modelContext).allows(preview.estimate) {
            return "Das Monatsbudget von \(Self.dollars(settings.monthlyBudgetUSD)) reicht für diese Analyse nicht mehr. Du kannst es unter KI-Anbieter ändern."
        }
        return nil
    }

    // MARK: Reports

    func runReport(_ kind: AnalysisPeriodKind, context: HealthAnalysisContext, modelContext: ModelContext) async -> StoredAnalysis {
        let model = settings.model
        let record = StoredAnalysis(kind: kind.rawValue, title: kind.title, model: model, contextJSON: context.compactJSON())
        record.promptVersion = IntelligencePrompts.version
        modelContext.insert(record)
        activity = "Claude schreibt den \(kind.title) …"
        defer { activity = nil }
        do {
            let body = AnthropicAPI.body(model: model, system: IntelligencePrompts.report,
                                         messages: [AnthropicAPI.userText(context.compactJSON())],
                                         schema: AnalysisSchema.reportV1, effort: kind.effort)
            let reply = try await call(body)
            record.apply(reply.response.usage, responder: reply.response.model, model: model)
            let validated = try ResponseValidator(context: context).validateReport(json: reply.response.text)
            record.resultJSON = Self.json(validated.report)
            record.issuesJSON = Self.json(validated.issues)
            record.flaggedJSON = Self.json(validated.flagged)
        } catch {
            record.fail(error)
        }
        try? modelContext.save()
        return record
    }

    // MARK: Questions

    /// Answers locally when it is a simple lookup, refuses emergencies without sending, else asks Claude
    /// with local tools (spec §3.3). `askClaude` false means: only try the iPhone.
    func localAnswer(to question: String, modelContext: ModelContext, owner: UUID, profile: UserProfile) -> String? {
        if SafetyRules.isEmergency(question) { return SafetyRules.emergencyReply }
        guard BrainRouter.route(question) == .local else { return nil }
        let context = reportContext(.daily, modelContext: modelContext, owner: owner, profile: profile)
        return LocalSentences.answer(question, context: context)
    }

    func ask(_ question: String, modelContext: ModelContext, owner: UUID) async -> StoredAnalysis {
        let model = settings.model
        let tools = QuestionTools(samples: samples(in: modelContext, owner: owner), events: events(in: modelContext),
                                  consent: settings.consent)
        let record = StoredAnalysis(kind: "question", title: "Frage", model: model, contextJSON: "", question: question)
        record.promptVersion = IntelligencePrompts.version
        modelContext.insert(record)
        activity = "Claude fragt deine Daten ab …"
        defer { activity = nil }

        var messages: [JSONValue] = [AnthropicAPI.userText(question)]
        var nextID = 1
        var facts: [AnalysisFact] = []
        var correlations: [CorrelationFact] = []
        var events: [ContextEventFact] = []
        var log: [String] = []
        var usage = TokenUsage()
        var calls = 0
        var finalText: String?
        var responder = model.id
        do {
            while finalText == nil {
                let body = AnthropicAPI.body(model: model, system: IntelligencePrompts.question, messages: messages,
                                             schema: AnalysisSchema.questionV1, effort: "medium", tools: tools.definitions)
                let reply = try await call(body)
                usage = usage + reply.response.usage
                responder = reply.response.model
                let uses = reply.response.toolUses
                if uses.isEmpty {
                    finalText = reply.response.text
                    break
                }
                guard calls + uses.count <= QuestionTools.maxCalls else {
                    throw QuestionError.tooManyCalls
                }
                let assistant = AnthropicResponse.assistantTurn(rawResponse: reply.raw)
                    ?? JSONValue.object(["role": .string("assistant"), "content": .array([])])
                messages.append(assistant)
                var results: [JSONValue] = []
                for use in uses {
                    calls += 1
                    let output = tools.run(name: use.name ?? "", input: use.input ?? .object([:]), nextID: &nextID)
                    facts += output.facts
                    correlations += output.correlations
                    events += output.events
                    log.append(output.summary)
                    results.append(QuestionTools.resultBlock(toolUseID: use.id ?? "", output: output))
                }
                messages.append(.object(["role": .string("user"), "content": .array(results)]))
            }
            let context = QuestionTools.context(facts: facts, correlations: correlations, events: events,
                                                consent: settings.consent, now: now)
            record.contextJSON = context.compactJSON()
            record.toolLog = log.joined(separator: "\n")
            record.apply(usage, responder: responder, model: model)
            let validated = try ResponseValidator(context: context).validateAnswer(json: finalText ?? "")
            record.resultJSON = Self.json(validated.answer)
            record.issuesJSON = Self.json(validated.issues)
            record.flaggedJSON = Self.json(validated.flagged)
        } catch {
            record.toolLog = log.joined(separator: "\n")
            record.apply(usage, responder: responder, model: model)
            record.fail(error)
        }
        try? modelContext.save()
        return record
    }

    enum QuestionError: Error {
        case tooManyCalls
    }

    // MARK: Detective

    func detectiveCases(modelContext: ModelContext, owner: UUID) -> [DetectiveCase] {
        BodyDetective().cases(samples: samples(in: modelContext, owner: owner), events: events(in: modelContext), now: now)
    }

    func hypothesesContext(for detectiveCase: DetectiveCase, modelContext: ModelContext) -> HealthAnalysisContext {
        BodyDetective().context(for: detectiveCase, events: events(in: modelContext), consent: settings.consent, now: now)
    }

    func runHypotheses(context: HealthAnalysisContext, title: String, modelContext: ModelContext) async -> StoredAnalysis {
        let model = settings.model
        let record = StoredAnalysis(kind: "detective", title: title, model: model, contextJSON: context.compactJSON())
        record.promptVersion = IntelligencePrompts.version
        modelContext.insert(record)
        activity = "Claude sucht Begleitumstände …"
        defer { activity = nil }
        do {
            let body = AnthropicAPI.body(model: model, system: IntelligencePrompts.detective,
                                         messages: [AnthropicAPI.userText(context.compactJSON())],
                                         schema: AnalysisSchema.hypothesesV1, effort: "medium")
            let reply = try await call(body)
            record.apply(reply.response.usage, responder: reply.response.model, model: model)
            let result = try ResponseValidator(context: context).validateHypotheses(json: reply.response.text)
            record.resultJSON = Self.json(result.board)
            record.issuesJSON = Self.json(result.issues)
        } catch {
            record.fail(error)
        }
        try? modelContext.save()
        return record
    }

    // MARK: Experiments

    func experimentRequest(_ question: String) -> String {
        let targets = ExperimentLab.targetKinds.map { "\($0.rawValue) (\($0.title))" }.joined(separator: ", ")
        return "Frage für den Selbstversuch: \(question)\nErlaubte Zielmesswerte (targetKind): \(targets)"
    }

    /// Plans an experiment with Claude; the plan is clamped locally and checked again for medication.
    func planExperiment(_ question: String, modelContext: ModelContext) async -> (plan: ExperimentPlan?, record: StoredAnalysis) {
        let model = settings.model
        let request = experimentRequest(question)
        let record = StoredAnalysis(kind: "experiment", title: "Experiment planen", model: model, contextJSON: "", question: question)
        record.promptVersion = IntelligencePrompts.version
        modelContext.insert(record)
        activity = "Claude plant den Selbstversuch …"
        defer { activity = nil }
        var plan: ExperimentPlan?
        do {
            let body = AnthropicAPI.body(model: model, system: IntelligencePrompts.experiment,
                                         messages: [AnthropicAPI.userText(request)],
                                         schema: AnalysisSchema.experimentPlanV1, effort: "medium")
            let reply = try await call(body)
            record.apply(reply.response.usage, responder: reply.response.model, model: model)
            guard let decoded = try? JSONDecoder().decode(ExperimentPlan.self, from: Data(reply.response.text.utf8)) else {
                throw ValidationError.notJSON
            }
            let clamped = decoded.sanitized()
            let wording = [clamped.title, clamped.conditionA, clamped.conditionB].joined(separator: " ")
            if case .rejected(let reason) = ExperimentLab.admissibility(of: wording) {
                throw PlanError.rejected(reason)
            }
            record.resultJSON = Self.json(clamped)
            plan = clamped
        } catch {
            record.fail(error)
        }
        try? modelContext.save()
        return (plan, record)
    }

    enum PlanError: Error {
        case rejected(String)
    }

    // MARK: Plumbing

    nonisolated static let localModelID = "local"

    private func call(_ body: JSONValue) async throws -> ClaudeReply {
        guard let key = services.secrets.read(), !key.isEmpty else { throw AnthropicError.missingKey }
        return try await services.transport.send(body, apiKey: key)
    }

    nonisolated static func json<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(value) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    nonisolated static func dollars(_ value: Double) -> String {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        return (f.string(from: NSNumber(value: value)) ?? "\(value)") + " $"
    }

    nonisolated static func message(for error: Error) -> String {
        if let error = error as? AnthropicError { return error.message }
        if let error = error as? ValidationError { return error.message }
        if let error = error as? PlanError, case .rejected(let reason) = error { return reason }
        if error is QuestionError { return "Claude hat zu viele Abfragen gebraucht. Bitte die Frage enger stellen." }
        return "Die Analyse ist fehlgeschlagen. Bitte später noch einmal versuchen."
    }
}

extension StoredAnalysis {
    func apply(_ usage: TokenUsage, responder: String, model: ClaudeModel) {
        inputTokens = usage.inputTokens
        outputTokens = usage.outputTokens
        cacheReadTokens = usage.cacheReadInputTokens
        cacheWriteTokens = usage.cacheCreationInputTokens
        // The fallback may answer with another model; price by the one that answered.
        respondingModel = responder
        costUSD = CostEstimator.cost(of: usage, model: ClaudeModel.all.first { $0.id == responder } ?? model)
    }

    func fail(_ error: Error) {
        statusRaw = "failed"
        errorMessage = IntelligenceEngine.message(for: error)
    }
}
