import Foundation
import PulseCore

/// One finished call: the decoded response and the raw bytes (needed to replay the assistant turn).
struct ClaudeReply: Sendable {
    let response: AnthropicResponse
    let raw: Data
}

/// Sends request bodies to Anthropic. The live version uses URLSession; test scenarios use canned replies
/// and never touch the network (spec §6).
protocol ClaudeTransport: Sendable {
    func send(_ body: JSONValue, apiKey: String) async throws -> ClaudeReply
    /// Whether the key may use this model (`GET /v1/models/{id}`), also the connection test.
    func hasModel(_ id: String, apiKey: String) async throws -> Bool
}

struct URLSessionTransport: ClaudeTransport {
    let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 600
        configuration.timeoutIntervalForResource = 900
        configuration.urlCache = nil
        session = URLSession(configuration: configuration)
    }

    func send(_ body: JSONValue, apiKey: String) async throws -> ClaudeReply {
        guard !apiKey.isEmpty else { throw AnthropicError.missingKey }
        var request = URLRequest(url: AnthropicAPI.messagesURL)
        request.httpMethod = "POST"
        for (field, value) in AnthropicAPI.headers(apiKey: apiKey) { request.setValue(value, forHTTPHeaderField: field) }
        request.httpBody = try body.encoded()
        var attempt = 0
        while true {
            let (data, status, retryAfter) = try await perform(request)
            if status == 200 {
                // Refusals and cut-off answers are billed too; the engine records their usage, then fails.
                return ClaudeReply(response: try AnthropicResponse.decode(data), raw: data)
            }
            let error = AnthropicError.from(status: status, body: data, retryAfter: retryAfter)
            // At most two repeats with growing pauses (spec §3.2 "Fehler").
            guard error.isRetryable, attempt < 2 else { throw error }
            attempt += 1
            var wait = 2 * attempt
            if case .rateLimited(let seconds?) = error { wait = min(seconds, 30) }
            try await Task.sleep(for: .seconds(wait))
        }
    }

    func hasModel(_ id: String, apiKey: String) async throws -> Bool {
        guard !apiKey.isEmpty else { throw AnthropicError.missingKey }
        var request = URLRequest(url: AnthropicAPI.modelURL(id))
        for (field, value) in AnthropicAPI.modelHeaders(apiKey: apiKey) { request.setValue(value, forHTTPHeaderField: field) }
        let (data, status, retryAfter) = try await perform(request)
        if status == 200 { return true }
        if status == 404 { return false }
        throw AnthropicError.from(status: status, body: data, retryAfter: retryAfter)
    }

    private func perform(_ request: URLRequest) async throws -> (Data, Int, String?) {
        do {
            let (data, response) = try await session.data(for: request)
            let http = response as? HTTPURLResponse
            return (data, http?.statusCode ?? 0, http?.value(forHTTPHeaderField: "retry-after"))
        } catch let error as URLError where [.notConnectedToInternet, .networkConnectionLost, .timedOut,
                                              .cannotFindHost, .cannotConnectToHost, .dataNotAllowed].contains(error.code) {
            throw AnthropicError.offline
        }
    }
}

/// Canned answers for screenshots and UI tests. They cite the facts the request carries, so the real
/// validator runs on them.
struct MockTransport: ClaudeTransport {
    func hasModel(_ id: String, apiKey: String) async throws -> Bool { ClaudeModel.all.contains { $0.id == id } }

    func send(_ body: JSONValue, apiKey: String) async throws -> ClaudeReply {
        let schema = body["output_config"]?["format"]?["schema"]
        let properties = schema?["properties"]
        let text: String
        let firstUser = body["messages"]?.arrayValue?.first?["content"]?.arrayValue?.first?["text"]?.stringValue ?? "{}"
        // A consultation opening carries the context JSON on its own line.
        let context = ([firstUser] + firstUser.components(separatedBy: "\n")).lazy
            .compactMap { try? JSONDecoder().decode(HealthAnalysisContext.self, from: Data($0.utf8)) }.first
        let facts = context?.facts ?? []
        if schema == nil {
            // Plain-text requests (Begleiter "Expertenrunde"): canned role statements and synthesis.
            text = CompanionConference.mockReply(system: body["system"]?.arrayValue?.first?["text"]?.stringValue ?? "")
        } else if properties?["differentials"] != nil {
            let turns = body["messages"]?.arrayValue?.count ?? 1
            text = Self.consultation(facts: facts, followUp: turns > 1)
        } else if properties?["summary"] != nil {
            text = Self.report(facts: facts)
        } else if properties?["circumstances"] != nil {
            text = Self.hypotheses(facts: facts, analogIDs: context?.events.filter { $0.type == "analog_day" }.map(\.id) ?? [])
        } else if properties?["blockDays"] != nil {
            text = #"{"title":"Kaffee nach 14 Uhr","targetKind":"sleep_duration","conditionA":"Kaffee wie gewohnt","conditionB":"kein Kaffee nach 14 Uhr","blockDays":5,"blocks":6,"washoutDays":1,"notesNeeded":["Uhrzeit des letzten Kaffees"],"rationale":"Schlafdauer reagiert innerhalb weniger Tage; sechs Blöcke gleichen Wochentage aus und reichen für eine Auswertung."}"#
        } else {
            text = #"{"statements":[{"text":"In der Testansicht beantwortet Claude keine echten Fragen.","type":"interpretation","evidence":[]}],"followUps":[]}"#
        }
        let response: JSONValue = [
            "id": "msg_test", "model": "claude-opus-5-5", "stop_reason": "end_turn", "type": "message", "role": "assistant",
            "content": .array([.object(["type": "text", "text": .string(text)])]),
            "usage": ["input_tokens": 4_200, "output_tokens": 1_900, "cache_read_input_tokens": 0, "cache_creation_input_tokens": 0],
        ]
        let data = try response.encoded()
        return ClaudeReply(response: try AnthropicResponse.decode(data), raw: data)
    }

    static func report(facts: [AnalysisFact]) -> String {
        func statement(_ text: String, _ type: String, _ ids: [String]) -> JSONValue {
            .object(["text": .string(text), "type": .string(type), "evidence": .array(ids.map { .string($0) })])
        }
        var summary: [JSONValue] = []
        var sections: [JSONValue] = []
        if let rhr = facts.first(where: { $0.kind == SampleKind.restingHeartRate.rawValue }) {
            summary.append(statement("Dein Ruhepuls lag im Median bei \(FactUnits.text(rhr.value, unit: rhr.unit)).", "measured", [rhr.id]))
            if let b = rhr.baseline {
                let position = rhr.value > b.p75 ? "über" : rhr.value < b.p25 ? "unter" : "innerhalb"
                sections.append(.object(["kind": "period_comparison", "title": "Vergleich mit deinem üblichen Bereich",
                                         "statements": .array([statement("Das liegt \(position) deines üblichen Bereichs von \(FactUnits.text(b.p25, unit: "")) bis \(FactUnits.text(b.p75, unit: rhr.unit)).", "computed", [rhr.id])])]))
            }
        }
        if let sleep = facts.first(where: { $0.kind == SampleKind.sleepDuration.rawValue }) {
            summary.append(statement("Du hast im Median \(FactUnits.text(sleep.value, unit: sleep.unit)) geschlafen.", "measured", [sleep.id]))
        }
        if let steps = facts.first(where: { $0.kind == SampleKind.steps.rawValue }) {
            sections.append(.object(["kind": "movement_recovery", "title": "Bewegung",
                                     "statements": .array([statement("Im Mittel \(Int(steps.value)) Schritte pro Tag.", "computed", [steps.id]),
                                                           statement("Ruhigere und bewegtere Tage wechselten sich ab; ein klares Muster zeigt diese Woche nicht.", "interpretation", [steps.id])])]))
        }
        let report: JSONValue = [
            "summary": .array(summary),
            "dataSituation": .array([statement("Für die meisten Tage liegen Werte vor.", "observation", facts.prefix(1).map(\.id))]),
            "sections": .array(sections),
            "openQuestions": ["Gab es Tage mit ungewohnt viel Stress?"],
            "uncertainties": .array([statement("Ringmessungen in der Nacht können durch Bewegung ungenau sein.", "interpretation", [])]),
            "actions": .array([.object(["text": "Achte diese Woche auf gleichmäßige Zubettgehzeiten.", "domain": "sleep", "evidence": .array([])])]),
            "medicalReferral": ["level": "none", "reason": "", "evidence": .array([])],
        ]
        return report.encodedString()
    }

    static func consultation(facts: [AnalysisFact], followUp: Bool) -> String {
        var assessment: [JSONValue] = []
        var evidence: [JSONValue] = []
        if let rhr = facts.first(where: { $0.kind == SampleKind.restingHeartRate.rawValue }) {
            evidence = [.string(rhr.id)]
            assessment.append(.object(["text": .string("Dein Ruhepuls lag im Median bei \(FactUnits.text(rhr.value, unit: rhr.unit))."),
                                       "type": "measured", "evidence": .array(evidence)]))
        }
        assessment.append(.object(["text": "Insgesamt wirkt dein Herz-Kreislauf-System stabil, die Erholung ist aber nicht an allen Tagen vollständig.",
                                   "type": "interpretation", "evidence": .array(evidence)]))
        let reply = followUp
            ? "Danke, das hilft. Ohne Fieber und Halsschmerzen wird ein Infekt unwahrscheinlicher; dann spricht mehr für eine Belastungsspitze."
            : "Ich habe mir deine letzten vier Wochen angesehen. Dein Ruhepuls und deine Erholung passen am ehesten zu einer hohen Belastung in den letzten Tagen. Für ein klares Bild brauche ich noch ein paar Angaben von dir."
        let consultation: JSONValue = [
            "reply": .string(reply),
            "assessment": .array(assessment),
            "differentials": .array([
                .object(["name": "Unvollständige Erholung nach Belastung", "likelihoodPercent": 55,
                         "reasoning": "Ruhepuls am oberen Rand deines Bereichs, kürzere Nächte.",
                         "supporting": ["Ruhepuls am oberen Rand", "kürzere Nächte"], "against": ["keine Beschwerden notiert"],
                         "workup": ["Ruhepuls und HRV drei Tage morgens beobachten"], "evidence": .array(evidence)]),
                .object(["name": "Beginnender Infekt", "likelihoodPercent": 20,
                         "reasoning": "Ein steigender Ruhepuls geht Infekten oft ein bis zwei Tage voraus.",
                         "supporting": ["Ruhepuls erhöht"], "against": ["kein Fieber bekannt"],
                         "workup": ["Temperatur morgens messen", "bei Fieber über 38,5 Grad Hausarzt"], "evidence": .array(evidence)]),
            ]),
            "recommendations": .array([
                .object(["area": "training", "priority": "high", "text": "Zwei Tage nur locker trainieren, Puls unter 130.", "evidence": .array([])]),
                .object(["area": "sleep", "priority": "medium", "text": "Diese Woche jeden Abend vor 23 Uhr ins Bett.", "evidence": .array([])]),
                .object(["area": "workup", "priority": "low", "text": "Beim nächsten Hausarzttermin Blutbild und Ruhe-EKG ansprechen.", "evidence": .array([])]),
            ]),
            "anamnesisQuestions": ["Wie fühlst du dich heute, von 1 bis 10?", "Hast du Fieber, Halsschmerzen oder Gliederschmerzen?",
                                   "Nimmst du regelmäßig Medikamente?"],
            "urgency": "routine",
            "urgencyReason": "Nichts Akutes, aber im Blick behalten.",
            "memory": "Ruhepuls am oberen Rand, Verdacht auf unvollständige Erholung (55 %), Infekt 20 %.",
        ]
        return consultation.encodedString()
    }

    static func hypotheses(facts: [AnalysisFact], analogIDs: [String]) -> String {
        let ids = (facts.prefix(1).map(\.id) + analogIDs.prefix(2)).map { JSONValue.string($0) }
        let board: JSONValue = [
            "circumstances": .array([.object([
                "text": "Frühere Tage mit ähnlichen Werten standen öfter zusammen mit kurzen Nächten.",
                "fit": "partial",
                "counterCheck": "Wenn es am Schlaf liegt, sollte der Wert nach der nächsten langen Nacht sinken.",
                "evidence": .array(ids),
            ])]),
            "note": "Das sind Beobachtungen aus deinen eigenen Daten, keine Ursachen.",
        ]
        return board.encodedString()
    }
}
