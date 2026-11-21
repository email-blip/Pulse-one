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
    /// Model ids the key may use (`GET /v1/models`), also the connection test.
    func models(apiKey: String) async throws -> [String]
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
                let response = try AnthropicResponse.decode(data)
                switch response.stopReason {
                case "refusal": throw AnthropicError.refusal
                case "max_tokens": throw AnthropicError.truncated
                default: return ClaudeReply(response: response, raw: data)
                }
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

    func models(apiKey: String) async throws -> [String] {
        guard !apiKey.isEmpty else { throw AnthropicError.missingKey }
        var request = URLRequest(url: AnthropicAPI.modelsURL)
        for (field, value) in AnthropicAPI.modelHeaders(apiKey: apiKey) { request.setValue(value, forHTTPHeaderField: field) }
        let (data, status, retryAfter) = try await perform(request)
        guard status == 200 else { throw AnthropicError.from(status: status, body: data, retryAfter: retryAfter) }
        let list = try JSONDecoder().decode(JSONValue.self, from: data)
        return list["data"]?.arrayValue?.compactMap { $0["id"]?.stringValue } ?? []
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
    func models(apiKey: String) async throws -> [String] { ClaudeModel.all.map(\.id) }

    func send(_ body: JSONValue, apiKey: String) async throws -> ClaudeReply {
        let schema = body["output_config"]?["format"]?["schema"]
        let properties = schema?["properties"]
        let text: String
        let firstUser = body["messages"]?.arrayValue?.first?["content"]?.arrayValue?.first?["text"]?.stringValue ?? "{}"
        let context = try? JSONDecoder().decode(HealthAnalysisContext.self, from: Data(firstUser.utf8))
        let facts = context?.facts ?? []
        if properties?["summary"] != nil {
            text = Self.report(facts: facts)
        } else if properties?["circumstances"] != nil {
            text = Self.hypotheses(facts: facts, analogIDs: context?.events.filter { $0.type == "analog_day" }.map(\.id) ?? [])
        } else if properties?["blockDays"] != nil {
            text = #"{"title":"Kaffee nach 14 Uhr","targetKind":"sleep_duration","conditionA":"Kaffee wie gewohnt","conditionB":"kein Kaffee nach 14 Uhr","blockDays":5,"blocks":4,"washoutDays":1,"notesNeeded":["Uhrzeit des letzten Kaffees"],"rationale":"Schlafdauer reagiert innerhalb weniger Tage; vier Blöcke gleichen Wochentage aus."}"#
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
