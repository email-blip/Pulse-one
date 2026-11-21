import Foundation
import PulseCore
import SwiftData

/// SwiftData models of the Analyse module. Every field has a default, so later additions migrate lightly.
enum IntelligenceModels {
    static let all: [any PersistentModel.Type] = [StoredAnalysis.self, StoredNote.self, StoredInsight.self, StoredExperiment.self]
}

/// One run of Claude (report, question, detective, experiment plan) with what was sent, what came back,
/// the check log and the real cost (spec §2 "Analysehistorie"). Stays on the device.
@Model
final class StoredAnalysis {
    var id: UUID = UUID()
    var createdAt: Date = Date.now
    /// daily, weekly, monthly, question, detective, experiment
    var kindRaw: String = ""
    var title: String = ""
    var question: String = ""
    var modelID: String = ""
    /// Model that actually answered (a fallback may answer instead).
    var respondingModel: String = ""
    var contextVersion: Int = 1
    var promptVersion: Int = 1
    var contextJSON: String = ""
    /// Validated result (AnalysisReport, QuestionAnswer, HypothesisBoard or ExperimentPlan JSON).
    var resultJSON: String = ""
    var issuesJSON: String = "[]"
    var flaggedJSON: String = "{}"
    /// Tool calls of a question, one line each ("Claude hat abgefragt: …").
    var toolLog: String = ""
    var inputTokens: Int = 0
    var outputTokens: Int = 0
    var cacheReadTokens: Int = 0
    var cacheWriteTokens: Int = 0
    var costUSD: Double = 0
    /// ok, failed
    var statusRaw: String = "ok"
    var errorMessage: String = ""

    init(kind: String, title: String, model: ClaudeModel, contextJSON: String, question: String = "") {
        id = UUID()
        createdAt = .now
        kindRaw = kind
        self.title = title
        modelID = model.id
        self.contextJSON = contextJSON
        self.question = question
    }

    var issues: [ValidationIssue] {
        (try? JSONDecoder().decode([ValidationIssue].self, from: Data(issuesJSON.utf8))) ?? []
    }

    var flagged: [String: String] {
        (try? JSONDecoder().decode([String: String].self, from: Data(flaggedJSON.utf8))) ?? [:]
    }

    var context: HealthAnalysisContext? {
        try? JSONDecoder().decode(HealthAnalysisContext.self, from: Data(contextJSON.utf8))
    }

    func decodeResult<T: Decodable>(_ type: T.Type) -> T? {
        try? JSONDecoder().decode(T.self, from: Data(resultJSON.utf8))
    }

    var failed: Bool { statusRaw != "ok" }
}

/// Evening note: the free text stays here; only confirmed tags may be shared (creative lab idea 4).
@Model
final class StoredNote {
    var id: UUID = UUID()
    var date: Date = Date.now
    var text: String = ""
    var tagsRaw: String = ""
    var mood: Int?

    init(_ event: ContextEvent) {
        id = event.id
        date = event.date
        text = event.text
        tagsRaw = event.tags.map(\.rawValue).joined(separator: ",")
        mood = event.mood
    }

    var event: ContextEvent {
        ContextEvent(id: id, date: date, tags: tagsRaw.split(separator: ",").compactMap { ContextTag(rawValue: String($0)) },
                     mood: mood, text: text)
    }
}

/// Body biography card (creative lab idea 5), stored as JSON so the core type stays the single source.
@Model
final class StoredInsight {
    var id: UUID = UUID()
    var payload: Data = Data()
    var createdAt: Date = Date.now

    init(_ card: InsightCard) {
        id = card.id
        createdAt = card.createdAt
        payload = (try? JSONEncoder().encode(card)) ?? Data()
    }

    var card: InsightCard? { try? JSONDecoder().decode(InsightCard.self, from: payload) }

    func update(_ card: InsightCard) { payload = (try? JSONEncoder().encode(card)) ?? payload }
}

/// Self-experiment with its plan and state (creative lab idea 3).
@Model
final class StoredExperiment {
    var id: UUID = UUID()
    var question: String = ""
    var planJSON: Data = Data()
    var startDate: Date = Date.now
    var createdAt: Date = Date.now
    /// running, finished, cancelled
    var statusRaw: String = "running"
    var resultSummary: String = ""

    init(question: String, plan: ExperimentPlan, start: Date) {
        id = UUID()
        self.question = question
        planJSON = (try? JSONEncoder().encode(plan)) ?? Data()
        startDate = start
        createdAt = .now
    }

    var plan: ExperimentPlan? { try? JSONDecoder().decode(ExperimentPlan.self, from: planJSON) }
}
