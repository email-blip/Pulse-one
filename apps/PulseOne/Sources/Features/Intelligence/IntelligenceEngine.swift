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

    /// Reason a send is blocked, or nil. During a run, `call` stops a tool loop before it goes over budget.
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
        beginRun(modelContext: modelContext)
        defer { endRun() }
        do {
            let body = AnthropicAPI.body(model: model, system: IntelligencePrompts.report(settings.safetyMode),
                                         messages: [AnthropicAPI.userText(context.compactJSON())],
                                         schema: AnalysisSchema.reportV1, effort: kind.effort)
            let reply = try await call(body)
            record.apply(reply.response.usage, responder: reply.response.model, model: model)
            let validated = try ResponseValidator(context: context, mode: settings.safetyMode).validateReport(json: reply.response.text)
            record.resultJSON = Self.json(validated.report)
            record.issuesJSON = Self.json(validated.issues)
            record.flaggedJSON = Self.json(validated.flagged)
        } catch {
            record.apply(billed, responder: billedResponder ?? model.id, model: model)
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
                                  consent: settings.consent, now: now)
        let record = StoredAnalysis(kind: "question", title: "Frage", model: model, contextJSON: "", question: question)
        record.promptVersion = IntelligencePrompts.version
        modelContext.insert(record)
        activity = "Claude fragt deine Daten ab …"
        beginRun(modelContext: modelContext)
        defer { endRun() }

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
                let body = AnthropicAPI.body(model: model, system: IntelligencePrompts.question(settings.safetyMode), messages: messages,
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
            let validated = try ResponseValidator(context: context, mode: settings.safetyMode).validateAnswer(json: finalText ?? "")
            record.resultJSON = Self.json(validated.answer)
            record.issuesJSON = Self.json(validated.issues)
            record.flaggedJSON = Self.json(validated.flagged)
        } catch {
            record.toolLog = log.joined(separator: "\n")
            record.apply(usage, responder: responder, model: model)
            record.apply(billed, responder: billedResponder ?? model.id, model: model)
            record.fail(error)
        }
        try? modelContext.save()
        return record
    }

    enum QuestionError: Error {
        case tooManyCalls
    }

    // MARK: Consultation (owner decision 2026-11-21)

    /// The consultation starts from the last four weeks: bands, correlations and note tags.
    func consultationContext(modelContext: ModelContext, owner: UUID, profile: UserProfile) -> HealthAnalysisContext {
        reportContext(.monthly, modelContext: modelContext, owner: owner, profile: profile)
    }

    /// Claude's summaries of the latest earlier consultations, newest first.
    func consultationMemory(excluding current: StoredConsultation?, modelContext: ModelContext) -> [String] {
        let descriptor = FetchDescriptor<StoredConsultation>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        let all = (try? modelContext.fetch(descriptor)) ?? []
        return all.filter { $0.id != current?.id && !$0.memory.isEmpty }.prefix(3).map(\.memory)
    }

    func consultationPreview(context: HealthAnalysisContext, modelContext: ModelContext) -> SendPreview {
        preview(title: "Sprechstunde mit Claude", context: context, system: IntelligencePrompts.consultation,
                expectedOutputTokens: 5_000, modelContext: modelContext)
    }

    /// Sends the person's message with the whole conversation; the answer is checked like a report and
    /// appended. Acute symptoms are marked so the emergency notice shows first; the message still goes.
    func consult(_ text: String, in consultation: StoredConsultation, modelContext: ModelContext, owner: UUID) async {
        let model = settings.model
        let message = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var turns = consultation.turns
        turns.append(ConsultationTurn(date: now, role: .person, text: message.isEmpty ? ConsultationBuilder.startMessage : message,
                                      emergencyNotice: SafetyRules.isEmergency(message)))
        consultation.turns = turns
        consultation.updatedAt = now
        if consultation.title == "Sprechstunde", !message.isEmpty {
            consultation.title = String(message.prefix(60))
        }
        let record = StoredAnalysis(kind: "consultation", title: "Sprechstunde", model: model, contextJSON: "", question: message)
        record.promptVersion = IntelligencePrompts.version
        modelContext.insert(record)
        try? modelContext.save()
        activity = "Claude wertet aus und antwortet …"
        beginRun(modelContext: modelContext)
        defer { endRun() }

        let base = consultation.context ?? QuestionTools.context(facts: [], correlations: [], events: [],
                                                                  consent: settings.consent, now: now)
        let memory = consultationMemory(excluding: consultation, modelContext: modelContext)
        let tools = QuestionTools(samples: samples(in: modelContext, owner: owner), events: events(in: modelContext),
                                  consent: settings.consent, now: now)
        var messages = Self.conversation(turns, opening: { first in
            ConsultationBuilder.opening(context: base, memory: memory, message: first)
        })
        var nextID = consultation.nextToolID
        var facts: [AnalysisFact] = []
        var correlations: [CorrelationFact] = []
        var events: [ContextEventFact] = []
        var log: [String] = []
        var usage = TokenUsage()
        var calls = 0
        var responder = model.id
        var claudeTurn = ConsultationTurn(date: now, role: .claude, text: "")
        do {
            var finalText: String?
            while finalText == nil {
                let body = AnthropicAPI.body(model: model, system: IntelligencePrompts.consultation, messages: messages,
                                             schema: AnalysisSchema.consultationV1, effort: "high", tools: tools.definitions)
                let reply = try await call(body)
                usage = usage + reply.response.usage
                responder = reply.response.model
                let uses = reply.response.toolUses
                if uses.isEmpty {
                    finalText = reply.response.text
                    break
                }
                guard calls + uses.count <= QuestionTools.maxCalls else { throw QuestionError.tooManyCalls }
                messages.append(AnthropicResponse.assistantTurn(rawResponse: reply.raw)
                                ?? JSONValue.object(["role": .string("assistant"), "content": .array([])]))
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
            let merged = ConsultationBuilder.merged(base, facts: facts, correlations: correlations, events: events)
            let validated = try ResponseValidator(context: merged, mode: .clinical)
                .validateConsultation(json: finalText ?? "", userText: message)
            claudeTurn.text = validated.reply.reply
            claudeTurn.apiText = finalText ?? ""
            claudeTurn.reply = validated.reply
            claudeTurn.flagged = validated.flagged
            claudeTurn.issues = validated.issues
            consultation.contextJSON = merged.compactJSON()
            consultation.nextToolID = nextID
            if !validated.reply.memory.isEmpty { consultation.memory = validated.reply.memory }
            consultation.urgencyRaw = validated.reply.urgency.rawValue
            record.contextJSON = merged.compactJSON()
            record.resultJSON = Self.json(validated.reply)
            record.issuesJSON = Self.json(validated.issues)
            record.flaggedJSON = Self.json(validated.flagged)
        } catch {
            claudeTurn.errorMessage = Self.message(for: error)
            record.apply(billed, responder: billedResponder ?? model.id, model: model)
            record.fail(error)
        }
        claudeTurn.toolLog = log
        claudeTurn.date = now
        record.toolLog = log.joined(separator: "\n")
        record.apply(billed, responder: billedResponder ?? responder, model: model)
        var all = consultation.turns
        all.append(claudeTurn)
        consultation.turns = all
        consultation.updatedAt = now
        try? modelContext.save()
    }

    /// The conversation as API messages: the first person turn carries the context and memory; failed
    /// replies are left out and turns of the same role are joined, so roles alternate.
    nonisolated static func conversation(_ turns: [ConsultationTurn], opening: (String) -> String) -> [JSONValue] {
        var pairs: [(role: String, text: String)] = []
        var openingDone = false
        for turn in turns {
            let role: String
            let text: String
            switch turn.role {
            case .person:
                role = "user"
                if openingDone {
                    text = turn.text
                } else {
                    text = opening(turn.text)
                    openingDone = true
                }
            case .claude:
                guard !turn.apiText.isEmpty else { continue }
                role = "assistant"
                text = turn.apiText
            }
            if let last = pairs.last, last.role == role {
                pairs[pairs.count - 1].text = last.text + "\n\n" + text
            } else {
                pairs.append((role, text))
            }
        }
        return pairs.map { pair in
            JSONValue.object(["role": .string(pair.role),
                     "content": .array([.object(["type": .string("text"), "text": .string(pair.text)])])])
        }
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
        beginRun(modelContext: modelContext)
        defer { endRun() }
        do {
            let body = AnthropicAPI.body(model: model, system: IntelligencePrompts.detective(settings.safetyMode),
                                         messages: [AnthropicAPI.userText(context.compactJSON())],
                                         schema: AnalysisSchema.hypothesesV1, effort: "medium")
            let reply = try await call(body)
            record.apply(reply.response.usage, responder: reply.response.model, model: model)
            let result = try ResponseValidator(context: context, mode: settings.safetyMode).validateHypotheses(json: reply.response.text)
            record.resultJSON = Self.json(result.board)
            record.issuesJSON = Self.json(result.issues)
        } catch {
            record.apply(billed, responder: billedResponder ?? model.id, model: model)
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
        beginRun(modelContext: modelContext)
        defer { endRun() }
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
            record.apply(billed, responder: billedResponder ?? model.id, model: model)
            record.fail(error)
        }
        try? modelContext.save()
        return (plan, record)
    }

    enum PlanError: Error {
        case rejected(String)
    }

    // MARK: Plain text (used by the Begleiter's Expertenrunde)

    /// One plain-text request without a JSON schema, sent with this module's key and transport. Callers show
    /// their own preview first, check `blocker(for:modelContext:)` right before sending and record the
    /// returned usage on a `StoredAnalysis` (`apply`), so budget, send count and cost views include it.
    func sendPlainText(system: String, user: String, model: ClaudeModel, effort: String) async throws -> AnthropicResponse {
        let body = AnthropicAPI.body(model: model, system: system, messages: [AnthropicAPI.userText(user)],
                                     schema: nil, effort: effort)
        return try await call(body).response
    }

    // MARK: Plumbing

    nonisolated static let localModelID = "local"

    /// Usage of every call of the current run, also of calls that end in a refusal or are cut off, so
    /// the monthly budget counts what Anthropic bills.
    @ObservationIgnored private var billed = TokenUsage()
    @ObservationIgnored private var billedResponder: String?
    /// What the current run may still spend; a tool loop stops before it would go over the budget.
    @ObservationIgnored private var runLimitUSD: Double?

    private func beginRun(modelContext: ModelContext) {
        billed = TokenUsage()
        billedResponder = nil
        runLimitUSD = spendingBudget(in: modelContext).remainingUSD
    }

    private func endRun() {
        activity = nil
        runLimitUSD = nil
    }

    private func call(_ body: JSONValue) async throws -> ClaudeReply {
        guard let key = services.secrets.read(), !key.isEmpty else { throw AnthropicError.missingKey }
        if let limit = runLimitUSD, CostEstimator.cost(of: billed, model: settings.model) >= limit {
            throw BudgetError.exhausted
        }
        let reply = try await services.transport.send(body, apiKey: key)
        billed = billed + reply.response.usage
        billedResponder = reply.response.model
        switch reply.response.stopReason {
        case "refusal": throw AnthropicError.refusal
        case "max_tokens": throw AnthropicError.truncated
        default: return reply
        }
    }

    enum BudgetError: Error {
        case exhausted
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
        if error is BudgetError { return "Das Monatsbudget ist während der Abfragen aufgebraucht worden. Du kannst es unter KI-Anbieter ändern." }
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
